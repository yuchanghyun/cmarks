import Testing
@testable import MarkdownCore

struct GFMRendererTests {
    let renderer = GFMRenderer()

    @Test func rendersHeading() {
        #expect(renderer.renderHTML("# Hello") == "<h1>Hello</h1>\n")
    }

    @Test func rendersGFMTable() {
        let html = renderer.renderHTML("| a | b |\n|---|---|\n| 1 | 2 |\n")
        #expect(html.contains("<table>"))
        #expect(html.contains("<td>2</td>"))
    }

    @Test func rendersTaskListAndStrikethrough() {
        let html = renderer.renderHTML("- [x] done\n- [ ] todo\n\n~~gone~~\n")
        #expect(html.contains("type=\"checkbox\""))
        #expect(html.contains("checked"))
        #expect(html.contains("<del>gone</del>"))
    }

    @Test func tagfilterEscapesScriptButKeepsRawHTML() {
        let html = renderer.renderHTML("<details><summary>x</summary></details>\n\n<script>alert(1)</script>\n")
        #expect(html.contains("<details>"))
        #expect(html.contains("&lt;script>"))
    }

    @Test func rendersFootnotes() {
        let html = renderer.renderHTML("text[^1]\n\n[^1]: note\n")
        #expect(html.contains("footnote"))
    }
}
