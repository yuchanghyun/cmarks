import Foundation
import Testing
@testable import MarkdownCore

/// Fixtures/snapshots/*.md → GFMRenderer 출력이 *.html 과 같은지 비교한다.
/// 기대값 갱신: CMARKS_RECORD_SNAPSHOTS=1 swift test (소스 트리의 Fixtures에 기록)
struct SnapshotTests {
    static let sourceFixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/snapshots")

    static func markdownFixtures() throws -> [URL] {
        let dir = try #require(Bundle.module.url(forResource: "snapshots", withExtension: nil, subdirectory: "Fixtures"))
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @Test func snapshotsMatch() throws {
        let record = ProcessInfo.processInfo.environment["CMARKS_RECORD_SNAPSHOTS"] == "1"
        let renderer = GFMRenderer()
        for md in try Self.markdownFixtures() {
            let name = md.deletingPathExtension().lastPathComponent
            let markdown = try String(contentsOf: md, encoding: .utf8)
            let html = renderer.renderHTML(markdown)
            let expectedURL = md.deletingPathExtension().appendingPathExtension("html")
            if record {
                try html.write(to: Self.sourceFixtures.appending(path: "\(name).html"), atomically: true, encoding: .utf8)
                continue
            }
            let expected = try String(contentsOf: expectedURL, encoding: .utf8)
            #expect(html == expected, "snapshot \(name) differs")
        }
    }
}
