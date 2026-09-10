import Foundation
import Testing
@testable import FileKit

/// 감시 이벤트를 모아 두고 개수가 찰 때까지 기다린다.
actor EventRecorder {
    private(set) var events: [FileWatcher.Event] = []

    func record(_ event: FileWatcher.Event) {
        events.append(event)
    }

    func wait(forCount count: Int, timeout: Duration = .seconds(4)) async -> [FileWatcher.Event] {
        let deadline = ContinuousClock.now + timeout
        while events.count < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return events
    }
}

struct FileWatcherTests {
    func makeFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cmarks-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("doc.md")
        try Data("# one\n".utf8).write(to: file)
        return file
    }

    func appendInPlace(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    @Test func detectsInPlaceWrite() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let recorder = EventRecorder()
        let watcher = FileWatcher(url: file, debounce: .milliseconds(50)) { event in Task { await recorder.record(event) } }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(100))

        try appendInPlace("more\n", to: file)
        let events = await recorder.wait(forCount: 1)
        #expect(events == [.changed])
    }

    @Test func survivesAtomicReplaceAndKeepsWatching() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let recorder = EventRecorder()
        let watcher = FileWatcher(url: file, debounce: .milliseconds(50)) { event in Task { await recorder.record(event) } }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(100))

        // 임시 파일에 쓰고 rename으로 덮어쓰는 원자적 저장(TextEdit, Xcode 등)
        try "# two\n".write(to: file, atomically: true, encoding: .utf8)
        var events = await recorder.wait(forCount: 1)
        #expect(events == [.changed])

        // 새 vnode에 대해서도 감시가 이어져야 한다
        try await Task.sleep(for: .milliseconds(100))
        try appendInPlace("three\n", to: file)
        events = await recorder.wait(forCount: 2)
        #expect(events == [.changed, .changed])
    }

    @Test func reportsDisappearanceThenRecovery() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let recorder = EventRecorder()
        let watcher = FileWatcher(url: file, debounce: .milliseconds(50)) { event in Task { await recorder.record(event) } }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(100))

        try FileManager.default.removeItem(at: file)
        var events = await recorder.wait(forCount: 1)
        #expect(events == [.disappeared])

        try Data("# back\n".utf8).write(to: file)
        events = await recorder.wait(forCount: 2)
        #expect(events == [.disappeared, .changed])
    }

    @Test func asyncStreamStopsOnTermination() async throws {
        let file = try makeFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let stream = FileWatcher.events(for: file, debounce: .milliseconds(50))
        let task = Task { () -> FileWatcher.Event? in
            for await event in stream { return event }
            return nil
        }
        try await Task.sleep(for: .milliseconds(100))
        try appendInPlace("x\n", to: file)
        let first = await task.value
        #expect(first == .changed)
    }
}
