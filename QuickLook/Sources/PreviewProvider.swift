import Foundation
import MarkdownCore
import OSLog
import QuickLookUI
import UniformTypeIdentifiers

/// Finder Quick Look(스페이스바) 미리보기. 데이터 기반 미리보기(QLPreviewReply, HTML)라 스크립트가 돌지 않으므로
/// 코드 하이라이팅·수식·이모지는 StaticPreviewBuilder가 JavaScriptCore로 미리 처리하고, CSS·폰트·이미지는 인라인/첨부로 넣는다.
/// (확장 안의 WKWebView는 샌드박스에서 웹 프로세스를 띄우지 못해 쓸 수 없다.)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private let renderer = PreviewRenderer()
    private lazy var builder = StaticPreviewBuilder(assetsRoot: renderer.assetsRoot)
    private let logger = Logger(subsystem: "com.changhyunyoo.cmarks.quicklook", category: "preview")

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        logger.notice("preview \(request.fileURL.lastPathComponent, privacy: .public) assets=\(self.renderer.assetsRoot.path, privacy: .public)")
        let document: RenderedDocument
        do {
            document = try await renderer.render(request.fileURL)
        } catch {
            logger.error("render failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        let page = builder.page(bodyHTML: document.bodyHTML, title: document.title, documentURL: request.fileURL,
                                settings: renderer.settings, isLarge: document.isLarge) { url in
            // 미리보기 대상 파일 옆의 이미지. 샌드박스가 막으면 nil → 원래 src를 둔다.
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
            let type = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
            return StaticAttachment(data: data, typeIdentifier: type)
        }
        logger.notice("static page \(page.html.utf8.count) bytes, attachments \(page.attachments.count)")
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 700)) { reply in
            reply.stringEncoding = .utf8
            reply.attachments = page.attachments.mapValues { attachment in
                QLPreviewReplyAttachment(data: attachment.data, contentType: UTType(attachment.typeIdentifier) ?? .data)
            }
            return Data(page.html.utf8)
        }
        return reply
    }
}
