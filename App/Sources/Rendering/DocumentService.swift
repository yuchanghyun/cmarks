import FileKit
import Foundation
import MarkdownCore
import OSLog
import Synchronization

/// 렌더 파이프라인과 결과 저장소. 스킴 핸들러가 경로로 렌더 결과를 조회한다(설계 문서 §4.4, §4.6).
@MainActor
@Observable
final class DocumentService {
    nonisolated static let scheme = "cmarks-local"
    nonisolated static let assetsBaseURL = URL(string: "\(scheme)://assets/")!
    /// 마크다운으로 취급하는 확장자. 설정에서 바뀌며, 드롭 판정 등 nonisolated 문맥에서도 읽는다.
    nonisolated private static let markdownExtensionsStore = Mutex<Set<String>>(["md", "markdown", "mdown", "mkd", "mkdn", "mdtxt", "mdtext", "mdx", "qmd", "rmd"])
    /// 대용량 정책에서 "전체 표시"를 누른 문서(경로).
    private var fullLoadOverrides: Set<String> = []

    var settings = RenderSettings.github
    private(set) var rendered: [String: RenderedDocument] = [:]

    let pipeline = RenderPipeline(assetsBaseURL: DocumentService.assetsBaseURL)
    private let access = DirectFileAccess()
    private let logger = Logger(subsystem: "com.changhyunyoo.cmarks", category: "perf")

    init() {}

    /// 파일을 읽고 렌더해 저장한다. 읽기와 파싱은 파이프라인 액터에서 돈다.
    func render(_ fileURL: URL) async throws -> RenderedDocument {
        let fileURL = fileURL.standardizedFileURL
        let access = self.access
        var settings = self.settings
        if fullLoadOverrides.contains(fileURL.path) { settings.hugeDocumentBytes = .max }
        let document = try await pipeline.render(fileURL: fileURL, settings: settings) { url in
            let contents = try access.contents(url)
            return RenderPipeline.Input(url: url, data: contents.data, modificationDate: contents.modificationDate)
        }
        rendered[fileURL.path] = document
        let ms = Double(document.renderDuration.components.attoseconds) / 1e15 + Double(document.renderDuration.components.seconds) * 1000
        logger.notice("render \(fileURL.lastPathComponent, privacy: .public) \(document.byteCount) bytes in \(ms, format: .fixed(precision: 2)) ms cache=\(document.fromCache) large=\(document.isLarge) truncated=\(document.isTruncated)")
        return document
    }

    /// 스킴 핸들러용. 저장된 결과가 없으면(예: 웹뷰 자체 새로고침) 지금 렌더한다.
    func pageHTML(forPath path: String) async throws -> String {
        if let document = rendered[path] { return document.pageHTML }
        return try await render(URL(fileURLWithPath: path)).pageHTML
    }

    /// 잘린 문서를 전체 표시. 캐시 키(설정)가 달라져 자연히 다시 렌더된다.
    func allowFullLoad(_ fileURL: URL) {
        fullLoadOverrides.insert(fileURL.standardizedFileURL.path)
    }

    func invalidate(_ fileURL: URL) async {
        rendered.removeValue(forKey: fileURL.path)
        await pipeline.invalidate(path: fileURL.path)
    }

    // MARK: URL 변환

    /// 파일 URL → 웹뷰가 로드하는 문서 URL. 경로를 그대로 실어 상대 링크가 파일 시스템 경로로 풀린다.
    nonisolated static func documentURL(for fileURL: URL, fragment: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "doc"
        components.path = fileURL.standardizedFileURL.path(percentEncoded: false)
        components.fragment = fragment
        return components.url!
    }

    nonisolated static func fileURL(fromDocumentURL url: URL) -> URL? {
        guard url.scheme == scheme, url.host == "doc" else { return nil }
        return URL(fileURLWithPath: url.path(percentEncoded: false))
    }

    nonisolated static func isMarkdown(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return markdownExtensionsStore.withLock { $0.contains(ext) }
    }

    nonisolated static func setMarkdownExtensions(_ extensions: Set<String>) {
        markdownExtensionsStore.withLock { $0 = extensions }
    }
}
