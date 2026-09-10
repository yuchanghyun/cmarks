import Foundation
import Testing
@testable import cmarks

struct DocumentWebViewTests {
    @Test func acceptsMarkdownTextAndFolders() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let md = dir.appendingPathComponent("a.md")
        let txt = dir.appendingPathComponent("b.txt")
        let png = dir.appendingPathComponent("c.png")
        for url in [md, txt, png] { try Data().write(to: url) }

        let accepted = DocumentWebView.accepted([md, txt, png, dir, dir.appendingPathComponent("missing.pdf")])
        #expect(accepted == [md, txt, dir])
    }
}
