import Foundation
import MarkdownCore

/// 확장 안의 렌더러. 설정은 GitHub 기본값이며 언어만 시스템 설정을 따른다(앱 설정은 샌드박스 밖이라 읽지 않는다).
final class PreviewRenderer: Sendable {
    let assetsRoot: URL
    let settings: RenderSettings
    private let pipeline: RenderPipeline

    init() {
        // 확장 번들의 web 폴더(빌드 스크립트가 mermaid 등 정적 미리보기에 불필요한 것을 빼고 복사한다)
        assetsRoot = Bundle.main.resourceURL!.appending(path: "web")
        var settings = RenderSettings.github
        settings.language = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        self.settings = settings
        pipeline = RenderPipeline(assetsBaseURL: URL(string: "cmarks-local://assets/")!, cacheBytes: 4 << 20)
    }

    func render(_ fileURL: URL) async throws -> RenderedDocument {
        try await pipeline.render(fileURL: fileURL.standardizedFileURL, settings: settings) { url in
            let data = try Data(contentsOf: url)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return RenderPipeline.Input(url: url, data: data, modificationDate: modified)
        }
    }
}
