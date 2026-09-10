import Testing
@testable import MarkdownCore

struct FrontMatterTests {
    @Test func splitsYAML() {
        let (front, body) = FrontMatterParser.split("---\ntitle: x\ntags: [a]\n---\n# Body\n")
        #expect(front == FrontMatter(format: .yaml, raw: "title: x\ntags: [a]"))
        #expect(body == "# Body\n")
    }

    @Test func splitsTOMLAndYAMLDotsClose() {
        #expect(FrontMatterParser.split("+++\na = 1\n+++\nbody").frontMatter?.format == .toml)
        #expect(FrontMatterParser.split("---\na: 1\n...\nbody").body == "body")
    }

    @Test func noClosingFenceIsNotFrontMatter() {
        let text = "---\nnot front matter\n"
        let (front, body) = FrontMatterParser.split(text)
        #expect(front == nil)
        #expect(body == text)
    }

    @Test func fenceMustBeOnFirstLine() {
        let text = "\n---\na: 1\n---\n"
        #expect(FrontMatterParser.split(text).frontMatter == nil)
    }
}
