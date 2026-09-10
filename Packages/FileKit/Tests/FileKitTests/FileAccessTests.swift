import Foundation
import Testing
@testable import FileKit

struct FileAccessTests {
    @Test func readsExistingFileAndReportsMissingOne() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("한글 이름.md")
        try Data("# 제목\n".utf8).write(to: file)

        let access = DirectFileAccess()
        #expect(access.exists(file))
        #expect(String(decoding: try access.read(file), as: UTF8.self) == "# 제목\n")
        #expect(!access.exists(dir.appendingPathComponent("missing.md")))
    }
}
