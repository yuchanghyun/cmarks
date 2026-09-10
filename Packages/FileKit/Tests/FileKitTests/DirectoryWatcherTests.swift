import Foundation
import Testing
@testable import FileKit

struct DirectoryWatcherTests {
    @Test func reportsChangedPathsUnderRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cmarks-dirwatch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let recorder = PathRecorder()
        let watcher = try #require(DirectoryWatcher(url: root, latency: 0.1) { paths in Task { await recorder.record(paths) } })
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))

        try Data("# new\n".utf8).write(to: root.appendingPathComponent("sub/new.md"))
        let paths = await recorder.wait(timeout: .seconds(5))
        #expect(paths.contains { $0.hasSuffix("/sub/new.md") || $0.hasSuffix("/sub") })
    }
}

actor PathRecorder {
    private(set) var paths: [String] = []

    func record(_ new: [String]) {
        paths.append(contentsOf: new)
    }

    func wait(timeout: Duration) async -> [String] {
        let deadline = ContinuousClock.now + timeout
        while paths.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return paths
    }
}
