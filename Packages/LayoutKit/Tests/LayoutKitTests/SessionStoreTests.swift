import Foundation
import Testing
@testable import LayoutKit

struct SessionStoreTests {
    @Test func saveAndLoadRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SessionStore(directory: dir)
        #expect(try store.load() == nil)

        var ws = Workspace.single(name: "proj", rootURL: URL(fileURLWithPath: "/tmp/proj"), document: DocumentRef(url: URL(fileURLWithPath: "/tmp/proj/a.md")))
        ws.lastActiveAt = Date(timeIntervalSince1970: 1_700_000_000.25) // 밀리초 정밀도로 저장되므로 그 안에서 고른다
        ws.sidebar = SidebarState(expandedDirectories: ["", "docs"])
        ws.splitFocusedPane(direction: .down)
        ws.updateActiveTab { $0.scrollY = 321.5; $0.zoom = 1.2 }
        let session = Session(workspaces: [ws], activeWorkspaceID: ws.id, savedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(session)

        let loaded = try #require(try store.load())
        #expect(loaded == session)
        #expect(loaded.workspaces[0].focusedPane?.activeTab?.scrollY == 321.5)
    }

    @Test func rejectsUnknownSchema() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SessionStore(directory: dir)
        try Data(#"{"schemaVersion": 99, "workspaces": []}"#.utf8).write(to: store.fileURL)
        #expect(throws: SessionStore.LoadError.unsupportedSchema(99)) { try store.load() }
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(throws: (any Error).self) { try store.load() }
    }
}

// MARK: - rootBookmark (샌드박스 폴더 접근)

@Suite struct WorkspaceBookmarkTests {
    @Test func bookmarkRoundTripsAndOldSessionsDecodeWithoutIt() throws {
        var ws = Workspace.single(name: "docs", rootURL: URL(fileURLWithPath: "/tmp/docs"))
        ws.rootBookmark = Data([1, 2, 3])
        let data = try JSONEncoder().encode(ws)
        let back = try JSONDecoder().decode(Workspace.self, from: data)
        #expect(back.rootBookmark == Data([1, 2, 3]))

        // 이전 세션 파일에는 필드가 없다 → nil
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "rootBookmark")
        let old = try JSONDecoder().decode(Workspace.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.rootBookmark == nil)
        #expect(old.rootURL == ws.rootURL)
    }
}
