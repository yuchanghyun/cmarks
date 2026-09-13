import Foundation
import Testing
@testable import cmarks

@MainActor
struct ScrollMemoryTests {
    @Test func remembersRecentPositionsAndPersists() async throws {
        let suite = "cmarks-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = ScrollMemory(defaults: defaults, limit: 3)
        let a = URL(fileURLWithPath: "/tmp/a.md"), b = URL(fileURLWithPath: "/tmp/b.md"), c = URL(fileURLWithPath: "/tmp/c.md"), d = URL(fileURLWithPath: "/tmp/d.md")
        memory.remember(120, for: a)
        memory.remember(40, for: b)
        memory.remember(0.5, for: c)     // 거의 맨 위 → 기억하지 않음
        #expect(memory.position(for: a) == 120)
        #expect(memory.position(for: b) == 40)
        #expect(memory.position(for: c) == nil)
        memory.remember(10, for: c)
        memory.remember(99, for: d)      // limit 3 → 가장 오래된 a 제거
        #expect(memory.position(for: a) == nil)
        #expect(memory.position(for: d) == 99)
        memory.remember(200, for: a)     // 다시 기억하면 맨 뒤로
        #expect(memory.position(for: b) == nil)
        memory.forget(d)
        #expect(memory.position(for: d) == nil)
        memory.save()
        let reloaded = ScrollMemory(defaults: defaults, limit: 3)
        #expect(reloaded.position(for: a) == 200)
        #expect(reloaded.position(for: c) == 10)
    }
}

struct FinderFollowerTests {
    static func isMarkdown(_ url: URL) -> Bool { ["md", "markdown"].contains(url.pathExtension.lowercased()) }

    @Test func opensOnlyNewMarkdownSelections() {
        #expect(FinderFollower.target(selection: "/tmp/notes.md", last: nil, isMarkdown: Self.isMarkdown)?.path == "/tmp/notes.md")
        #expect(FinderFollower.target(selection: "/tmp/notes.md\n", last: nil, isMarkdown: Self.isMarkdown)?.path == "/tmp/notes.md")
        #expect(FinderFollower.target(selection: "/tmp/notes.md", last: "/tmp/notes.md", isMarkdown: Self.isMarkdown) == nil, "같은 파일이 계속 선택됨")
        #expect(FinderFollower.target(selection: "/tmp/photo.png", last: nil, isMarkdown: Self.isMarkdown) == nil)
        #expect(FinderFollower.target(selection: "/tmp/folder/", last: nil, isMarkdown: Self.isMarkdown) == nil)
        #expect(FinderFollower.target(selection: "", last: nil, isMarkdown: Self.isMarkdown) == nil)
    }
}
