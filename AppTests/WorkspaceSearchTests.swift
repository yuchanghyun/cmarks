import FileKit
import Foundation
import Testing
@testable import cmarks

struct WorkspaceSearchTests {
    static func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "cmarks-search-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "sub"), withIntermediateDirectories: true)
        try "# Title\nHello world, hello again\nnothing\n".write(to: root.appending(path: "a.md"), atomically: true, encoding: .utf8)
        try "say HELLO\n".write(to: root.appending(path: "sub/b.md"), atomically: true, encoding: .utf8)
        try "hello in txt".write(to: root.appending(path: "c.txt"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func scanFindsMatchesWithSnippetsAndIndices() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (hits, summary) = WorkspaceSearchModel.scan(root: root, filter: .default, query: "hello")
        #expect(summary.files == 2)
        #expect(summary.hits == 3)
        #expect(!summary.truncated)
        #expect(hits.map(\.relativePath) == ["a.md", "a.md", "sub/b.md"])
        #expect(hits.map(\.line) == [2, 2, 1])
        #expect(hits.map(\.matchIndex) == [0, 1, 0])
        #expect(String(hits[0].snippet[hits[0].matchRange]) == "Hello")
        #expect(String(hits[1].snippet[hits[1].matchRange]) == "hello")
        #expect(String(hits[2].snippet[hits[2].matchRange]) == "HELLO")
    }

    @Test func snippetIsTrimmedAroundTheMatch() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cmarks-search-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let long = String(repeating: "x", count: 200) + " needle " + String(repeating: "y", count: 200)
        try long.write(to: root.appending(path: "long.md"), atomically: true, encoding: .utf8)
        let (hits, _) = WorkspaceSearchModel.scan(root: root, filter: .default, query: "needle")
        let hit = try #require(hits.first)
        #expect(hit.snippet.hasPrefix("…"))
        #expect(hit.snippet.hasSuffix("…"))
        #expect(String(hit.snippet[hit.matchRange]) == "needle")
        #expect(hit.snippet.count < 150)
    }

    @Test @MainActor func modelSearchesAfterDebounce() async throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = WorkspaceSearchModel()
        model.present(root: root)
        model.query = "h"          // 2자 미만: 검색하지 않음
        #expect(model.results.isEmpty)
        model.query = "hello"
        for _ in 0..<60 where model.isSearching || model.results.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.results.count == 3)
        #expect(model.summary.files == 2)
        model.moveSelection(-1)
        #expect(model.selectedIndex == 2)
        #expect(model.selected?.relativePath == "sub/b.md")
    }
}
