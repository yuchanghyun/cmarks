import Foundation
import Testing
@testable import MarkdownCore

/// 정적 미리보기(Quick Look용). 저장소의 App/Resources/web 번들을 쓴다(없으면 건너뜀).
struct StaticPreviewTests {
    static let assetsRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "App/Resources/web")
    static var hasAssets: Bool { FileManager.default.fileExists(atPath: assetsRoot.appending(path: "vendor/hljs/highlight.min.js").path) }

    static func render(_ markdown: String, settings: RenderSettings = .github, loader: @escaping StaticPreviewBuilder.ImageLoader = { _ in nil }) async throws -> StaticPreviewPage {
        let pipeline = RenderPipeline(assetsBaseURL: URL(string: "cmarks-local://assets/")!)
        let url = URL(fileURLWithPath: "/tmp/static-preview/doc.md")
        let document = try await pipeline.render(fileURL: url, settings: settings) { url in
            RenderPipeline.Input(url: url, data: Data(markdown.utf8), modificationDate: nil)
        }
        let builder = StaticPreviewBuilder(assetsRoot: assetsRoot)
        return builder.page(bodyHTML: document.bodyHTML, title: document.title, documentURL: url, settings: settings, imageLoader: loader)
    }

    @Test func highlightsCodeBlocksWithJavaScriptCore() async throws {
        try #require(Self.hasAssets, "App/Resources/web 번들이 없다: \(Self.assetsRoot.path)")
        let page = try await Self.render("```swift\nlet x = \"a\" < 1\n```\n\n```python\nimport os\n```\n")
        #expect(page.html.contains("hljs-keyword"))
        #expect(page.html.contains("class=\"hljs language-swift\""))
        #expect(page.html.contains("class=\"hljs language-python\""))
        #expect(page.html.contains("&lt; 1") || page.html.contains("&lt;"), "코드 안 < 가 이스케이프되어야 함")
        #expect(!page.html.contains("<script"))
    }

    @Test func rendersMathInlineAndBlocks() async throws {
        try #require(Self.hasAssets, "App/Resources/web 번들이 없다: \(Self.assetsRoot.path)")
        let page = try await Self.render("Energy $E = mc^2$ here.\n\n$$\n\\int_0^1 x\\,dx\n$$\n\n```math\n\\frac{a}{b}\n```\n\n`$not$ math` and $5 and $10.\n")
        #expect(page.html.contains("class=\"katex\""))
        #expect(page.html.contains("katex-display"))
        #expect(page.html.contains("cmarks-math-block"))
        #expect(page.html.contains("$not$ math"), "코드 안의 $는 수식이 아니다")
        #expect(page.html.contains("@font-face"), "KaTeX CSS 인라인")
        #expect(page.html.contains("data:font/woff2;base64,"))
    }

    @Test func skipsKaTeXCSSWithoutMath() async throws {
        try #require(Self.hasAssets, "App/Resources/web 번들이 없다: \(Self.assetsRoot.path)")
        let page = try await Self.render("# Plain\n\nJust text.\n")
        #expect(!page.html.contains("@font-face"))
        #expect(page.html.contains(".markdown-body"))
        #expect(page.html.contains("prefers-color-scheme: dark"))
    }

    @Test func replacesEmojiShortcodesOutsideCode() async throws {
        try #require(Self.hasAssets, "App/Resources/web 번들이 없다: \(Self.assetsRoot.path)")
        let page = try await Self.render("Hi :smile: and `:smile:` and :unknown_code:\n")
        #expect(page.html.contains("Hi 😄 and"))
        #expect(page.html.contains("<code>:smile:</code>"))
        #expect(page.html.contains(":unknown_code:"))
    }

    @Test func embedsLocalImagesAsAttachments() async throws {
        try #require(Self.hasAssets, "App/Resources/web 번들이 없다: \(Self.assetsRoot.path)")
        var requested: [URL] = []
        let page = try await Self.render("![a](images/a.png) ![b](https://example.com/b.png) ![c](missing.png)\n") { url in
            requested.append(url)
            return url.lastPathComponent == "a.png" ? StaticAttachment(data: Data([1, 2, 3]), typeIdentifier: "public.png") : nil
        }
        #expect(page.attachments.count == 1)
        #expect(page.html.contains("src=\"cid:img1\""))
        #expect(page.html.contains("src=\"https://example.com/b.png\""))
        #expect(page.html.contains("src=\"missing.png\""))
        #expect(requested.map(\.path).contains("/tmp/static-preview/images/a.png"))
    }

    @Test func mermaidStaysAsCodeWithNote() async throws {
        try #require(Self.hasAssets, "App/Resources/web 번들이 없다: \(Self.assetsRoot.path)")
        var settings = RenderSettings.github
        settings.language = "en"
        let page = try await Self.render("```mermaid\ngraph LR; A-->B\n```\n", settings: settings)
        #expect(page.html.contains("language-mermaid"))
        #expect(page.html.contains("Mermaid diagram"))
    }

    @Test func unescapesEntities() {
        #expect(StaticPreviewBuilder.unescapeEntities("a &lt; b &amp;&amp; c &quot;d&quot; &#39;e&#39; &#x41;&#66;") == "a < b && c \"d\" 'e' AB")
    }
}

/// CMARKS_DUMP_STATIC=<출력 경로>로 실행하면 fixtures/kitchen-sink.md의 정적 페이지를 파일로 남긴다(Quick Look 엔진에서 눈으로 확인용).
struct StaticPreviewDump {
    @Test func dumpKitchenSink() async throws {
        guard let out = ProcessInfo.processInfo.environment["CMARKS_DUMP_STATIC"] else { return }
        let root = StaticPreviewTests.assetsRoot.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = root.appending(path: "fixtures/kitchen-sink.md")
        let pipeline = RenderPipeline(assetsBaseURL: URL(string: "cmarks-local://assets/")!)
        let document = try await pipeline.render(fileURL: fixture, settings: .github) { url in
            RenderPipeline.Input(url: url, data: try Data(contentsOf: url), modificationDate: nil)
        }
        let builder = StaticPreviewBuilder(assetsRoot: StaticPreviewTests.assetsRoot)
        let page = builder.page(bodyHTML: document.bodyHTML, title: document.title, documentURL: fixture, settings: .github) { url in
            (try? Data(contentsOf: url)).map { StaticAttachment(data: $0, typeIdentifier: "public.png") }
        }
        try Data(page.html.utf8).write(to: URL(fileURLWithPath: out))
        print("dumped \(page.html.utf8.count) bytes, attachments \(page.attachments.count)")
    }
}
