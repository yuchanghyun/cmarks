import Foundation
import Testing
@testable import MarkdownCore

struct HTMLTemplateTests {
    @Test func injectsEscapedCustomCSSAfterWidthStyle() {
        var settings = RenderSettings.github
        settings.customCSS = ".markdown-body { font-size: 18px } </style><script>alert(1)</script>"
        let page = HTMLTemplate(assetsBaseURL: URL(string: "cmarks-local://assets/")!).page(bodyHTML: "<p>x</p>", documentPath: "/tmp/x.md", title: "x", settings: settings)
        #expect(page.contains("<style id=\"cmarks-user-css\">.markdown-body { font-size: 18px } <\\/style><script>alert(1)<\\/script></style>"))
        #expect(!page.contains("</style><script>alert(1)</script>"))
        let width = page.range(of: "max-width:980px")!.lowerBound
        let user = page.range(of: "cmarks-user-css")!.lowerBound
        #expect(width < user, "사용자 CSS가 폭 스타일 뒤에 와야 덮어쓸 수 있다")
    }

    @Test func omitsUserStyleWhenEmpty() {
        let page = HTMLTemplate(assetsBaseURL: URL(string: "cmarks-local://assets/")!).page(bodyHTML: "", documentPath: "/tmp/x.md", title: "x", settings: .github)
        #expect(!page.contains("cmarks-user-css"))
    }

    @Test func customCSSChangesCacheIdentity() {
        var a = RenderSettings.github
        var b = RenderSettings.github
        b.customCSS = "p{}"
        #expect(a != b)
        a.customCSS = "p{}"
        #expect(a == b)
    }
}
