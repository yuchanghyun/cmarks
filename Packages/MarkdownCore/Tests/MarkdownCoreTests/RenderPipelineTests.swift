import Foundation
import Testing
@testable import MarkdownCore

struct RenderPipelineTests {
    let assets = URL(string: "cmarks-local://assets/")!

    @Test func rendersPageWithCSPAndArticle() async throws {
        let pipeline = RenderPipeline(assetsBaseURL: assets)
        let input = RenderPipeline.Input(url: URL(fileURLWithPath: "/tmp/한글 폴더/doc.md"), data: Data("# Hi\n".utf8), modificationDate: Date(timeIntervalSince1970: 1))
        let doc = await pipeline.render(input, settings: .github)

        #expect(doc.bodyHTML == "<h1>Hi</h1>\n")
        #expect(doc.pageHTML.contains("Content-Security-Policy"))
        #expect(doc.pageHTML.contains("script-src cmarks-local://assets;"))
        #expect(doc.pageHTML.contains("<article class=\"markdown-body\" id=\"doc\" data-document-path=\"/tmp/한글 폴더/doc.md\">"))
        #expect(!doc.pageHTML.contains("cmarks-large"))
        #expect(doc.pageHTML.contains("cmarks-local://assets/vendor/github-markdown.css"))
        #expect(doc.pageHTML.contains("data-config=\"{&quot;contentMaxWidth&quot;:980,&quot;emoji&quot;:true,&quot;highlight&quot;:true,&quot;math&quot;:true,&quot;mermaid&quot;:true}\""))
        #expect(doc.title == "doc.md")
        #expect(!doc.fromCache)
    }

    @Test func cachesByPathDateSizeAndSettings() async throws {
        let pipeline = RenderPipeline(assetsBaseURL: assets)
        let url = URL(fileURLWithPath: "/tmp/a.md")
        let date = Date(timeIntervalSince1970: 100)
        let input = RenderPipeline.Input(url: url, data: Data("# A\n".utf8), modificationDate: date)

        let first = await pipeline.render(input, settings: .github)
        let second = await pipeline.render(input, settings: .github)
        #expect(!first.fromCache)
        #expect(second.fromCache)

        var other = RenderSettings.github
        other.footnotes = false
        let third = await pipeline.render(input, settings: other)
        #expect(!third.fromCache)

        let changed = RenderPipeline.Input(url: url, data: Data("# A\n".utf8), modificationDate: date.addingTimeInterval(1))
        let fourth = await pipeline.render(changed, settings: .github)
        #expect(!fourth.fromCache)

        await pipeline.invalidate(path: url.path)
        let fifth = await pipeline.render(input, settings: .github)
        #expect(!fifth.fromCache)
    }

    @Test func frontMatterIsCollapsedOrHidden() async throws {
        let pipeline = RenderPipeline(assetsBaseURL: assets)
        let input = RenderPipeline.Input(url: URL(fileURLWithPath: "/tmp/f.md"), data: Data("---\ntitle: <x>\n---\n# Body\n".utf8), modificationDate: nil)

        let collapsed = await pipeline.render(input, settings: .github)
        #expect(collapsed.frontMatter?.raw == "title: <x>")
        #expect(collapsed.bodyHTML.hasPrefix("<details class=\"cmarks-frontmatter\">"))
        #expect(collapsed.bodyHTML.contains("title: &lt;x&gt;"))
        #expect(collapsed.bodyHTML.hasSuffix("<h1>Body</h1>\n"))

        var hidden = RenderSettings.github
        hidden.frontMatter = .hidden
        let hiddenDoc = await pipeline.render(input, settings: hidden)
        #expect(hiddenDoc.bodyHTML == "<h1>Body</h1>\n")
    }

    @Test func emojiTableOnlyWhenShortcodesPresent() async throws {
        let pipeline = RenderPipeline(assetsBaseURL: assets)
        let plain = await pipeline.render(RenderPipeline.Input(url: URL(fileURLWithPath: "/tmp/p.md"), data: Data("no emoji here 10:30\n".utf8), modificationDate: nil), settings: .github)
        #expect(!plain.pageHTML.contains("vendor/emoji.js"))
        let withEmoji = await pipeline.render(RenderPipeline.Input(url: URL(fileURLWithPath: "/tmp/e.md"), data: Data("hi :rocket:\n".utf8), modificationDate: nil), settings: .github)
        #expect(withEmoji.pageHTML.contains("vendor/emoji.js"))
        var off = RenderSettings.github
        off.emoji = false
        let disabled = await pipeline.render(RenderPipeline.Input(url: URL(fileURLWithPath: "/tmp/e.md"), data: Data("hi :rocket:\n".utf8), modificationDate: nil), settings: off)
        #expect(!disabled.pageHTML.contains("vendor/emoji.js"))
    }

    @Test func largeDocumentsSkipEnhancementsAndHugeOnesAreTruncated() async throws {
        let pipeline = RenderPipeline(assetsBaseURL: assets)
        var settings = RenderSettings.github
        settings.largeDocumentBytes = 100
        settings.hugeDocumentBytes = 400
        settings.truncatedCharacterCount = 120

        let medium = String(repeating: "medium line\n", count: 20) // 240B
        let mediumDoc = await pipeline.render(RenderPipeline.Input(url: URL(fileURLWithPath: "/tmp/m.md"), data: Data(medium.utf8), modificationDate: nil), settings: settings)
        #expect(mediumDoc.isLarge && !mediumDoc.isTruncated)
        #expect(mediumDoc.pageHTML.contains("&quot;highlight&quot;:false"))
        #expect(mediumDoc.pageHTML.contains("&quot;math&quot;:false"))
        #expect(mediumDoc.bodyHTML.hasPrefix("<div class=\"cmarks-banner\""))
        #expect(mediumDoc.pageHTML.contains("class=\"markdown-body cmarks-large\""))
        #expect(!mediumDoc.bodyHTML.contains("cmarks-load-full"))

        let huge = String(repeating: "0123456789\n", count: 60) // 660B
        let hugeDoc = await pipeline.render(RenderPipeline.Input(url: URL(fileURLWithPath: "/tmp/h.md"), data: Data(huge.utf8), modificationDate: nil), settings: settings)
        #expect(hugeDoc.isTruncated)
        #expect(hugeDoc.bodyHTML.contains("cmarks-load-full"))
        // 120자 → 11자 줄 10개(110자)에서 줄 끝으로 잘림
        #expect(hugeDoc.bodyHTML.components(separatedBy: "0123456789").count - 1 == 10)

        let small = await pipeline.render(RenderPipeline.Input(url: URL(fileURLWithPath: "/tmp/s.md"), data: Data("small\n".utf8), modificationDate: nil), settings: settings)
        #expect(!small.isLarge)
        #expect(small.pageHTML.contains("&quot;highlight&quot;:true"))
    }

    @Test func bannerFollowsLanguage() async throws {
        let pipeline = RenderPipeline(assetsBaseURL: assets)
        var settings = RenderSettings.github
        settings.largeDocumentBytes = 10
        settings.language = "en"
        let doc = await pipeline.render(RenderPipeline.Input(url: URL(fileURLWithPath: "/tmp/l.md"), data: Data(String(repeating: "x", count: 50).utf8), modificationDate: nil), settings: settings)
        #expect(doc.bodyHTML.contains("code highlighting, math and diagrams are skipped"))
        #expect(doc.pageHTML.contains("<html lang=\"en\""))
        settings.hugeDocumentBytes = 20
        let huge = await pipeline.render(RenderPipeline.Input(url: URL(fileURLWithPath: "/tmp/l2.md"), data: Data(String(repeating: "y", count: 50).utf8), modificationDate: nil), settings: settings)
        #expect(huge.bodyHTML.contains(">Show All<"))
    }

    @Test func readerRunsInsidePipeline() async throws {
        let pipeline = RenderPipeline(assetsBaseURL: assets)
        let doc = try await pipeline.render(fileURL: URL(fileURLWithPath: "/tmp/r.md"), settings: .github) { url in
            RenderPipeline.Input(url: url, data: Data("*x*\n".utf8), modificationDate: nil)
        }
        #expect(doc.bodyHTML == "<p><em>x</em></p>\n")
    }

    @Test func cacheEvictsByBytes() {
        var cache = RenderCache(maxBytes: 40)
        func doc(_ html: String) -> RenderedDocument {
            RenderedDocument(url: URL(fileURLWithPath: "/x"), pageHTML: html, bodyHTML: "", title: "", frontMatter: nil, encoding: .utf8, byteCount: 0, renderDuration: .zero, fromCache: false)
        }
        let k1 = RenderCacheKey(path: "/1", modificationDate: nil, size: 0, settings: .github)
        let k2 = RenderCacheKey(path: "/2", modificationDate: nil, size: 0, settings: .github)
        let k3 = RenderCacheKey(path: "/3", modificationDate: nil, size: 0, settings: .github)
        cache.insert(doc(String(repeating: "a", count: 20)), for: k1)
        cache.insert(doc(String(repeating: "b", count: 20)), for: k2)
        _ = cache.value(for: k1) // k1을 최근 사용으로
        cache.insert(doc(String(repeating: "c", count: 20)), for: k3)
        #expect(cache.value(for: k2) == nil)
        #expect(cache.value(for: k1) != nil)
        #expect(cache.value(for: k3) != nil)
    }
}
