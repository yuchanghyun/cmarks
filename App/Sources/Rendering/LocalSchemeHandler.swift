import Foundation
import UniformTypeIdentifiers
import WebKit

/// `cmarks-local://assets/...` 은 앱 번들의 web 폴더, `cmarks-local://doc/<abs path>` 는 렌더된 문서(마크다운) 또는 로컬 파일(이미지 등).
/// 폰트 로딩을 위해 assets 응답에는 CORS 헤더를 붙인다(PLAN.md §4.4).
@MainActor
final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
    private let documents: DocumentService
    private let assetsRoot: URL
    /// stop 이후에 응답하면 WebKit이 예외를 던지므로 살아 있는 작업만 기록한다.
    private var activeTasks: [ObjectIdentifier: WKURLSchemeTask] = [:]

    init(documents: DocumentService, assetsRoot: URL) {
        self.documents = documents
        self.assetsRoot = assetsRoot
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        activeTasks[id] = urlSchemeTask

        guard let url = urlSchemeTask.request.url, let host = url.host else {
            finish(id, status: 400, body: Data("bad url".utf8), mime: "text/plain")
            return
        }

        switch host {
        case "assets":
            let components = url.pathComponents.dropFirst().filter { $0 != ".." && $0 != "." }
            let fileURL = components.reduce(assetsRoot) { $0.appending(path: $1) }
            serveFile(fileURL, for: id, cors: true)

        case "doc":
            let fileURL = URL(fileURLWithPath: url.path(percentEncoded: false))
            if DocumentService.isMarkdown(fileURL) {
                Task {
                    do {
                        let html = try await documents.pageHTML(forPath: fileURL.path)
                        finish(id, status: 200, body: Data(html.utf8), mime: "text/html; charset=utf-8")
                    } catch {
                        finish(id, status: 404, body: Data(error.localizedDescription.utf8), mime: "text/plain; charset=utf-8")
                    }
                }
            } else {
                serveFile(fileURL, for: id, cors: false)
            }

        default:
            finish(id, status: 404, body: Data("unknown host".utf8), mime: "text/plain")
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        activeTasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))
    }

    // MARK: 응답

    private func serveFile(_ fileURL: URL, for id: ObjectIdentifier, cors: Bool) {
        let mime = Self.mimeType(for: fileURL)
        Task.detached(priority: .userInitiated) {
            let data = try? Self.readFile(fileURL)
            await self.finish(id, status: data == nil ? 404 : 200, body: data ?? Data(), mime: mime, cors: cors)
        }
    }

    nonisolated private static func readFile(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    private func finish(_ id: ObjectIdentifier, status: Int, body: Data, mime: String, cors: Bool = false) {
        guard let task = activeTasks.removeValue(forKey: id), let url = task.request.url else { return }
        var headers = [
            "Content-Type": mime,
            "Content-Length": String(body.count),
            "Cache-Control": "no-store",
        ]
        if cors { headers["Access-Control-Allow-Origin"] = "*" }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }

    nonisolated static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "html", "htm": return "text/html; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "json": return "application/json; charset=utf-8"
        default:
            return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}
