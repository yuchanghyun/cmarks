import AppKit
import Foundation
import LayoutKit
import Testing
@testable import cmarks

/// 공유 모델 다중 창: 창마다 다른 워크스페이스를 보여 주고, 워크스페이스 목록·뷰어·세션은 하나로 관리한다.
@MainActor
@Suite(.serialized)
struct MultiWindowTests {
    static func makeWorkspaceRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "cmarks-mw-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "# \(name)\n".write(to: root.appending(path: "README.md"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func newWindowShowsItsOwnWorkspaceAndKeepsBothAlive() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rootA = try Self.makeWorkspaceRoot("a"), rootB = try Self.makeWorkspaceRoot("b")
        defer { try? FileManager.default.removeItem(at: rootA); try? FileManager.default.removeItem(at: rootB) }
        let a = model.addWorkspace(root: rootA, ephemeral: false)
        model.open(rootA.appending(path: "README.md"))
        let b = model.addWorkspace(root: rootB, ephemeral: false, activate: false)
        #expect(model.windowSlots.map(\.workspaceID) == [a])

        // 새 창에 b를 표시
        let w2 = model.openNewWindow(showing: b)
        #expect(model.windowOpenRequests == [w2])
        #expect(model.consumeWindowOpenRequest(w2))
        #expect(!model.consumeWindowOpenRequest(w2), "두 번 처리되지 않는다")
        model.ensureWindowSlot(w2)
        #expect(model.workspaceID(inWindow: w2) == b)
        #expect(model.workspaceID(inWindow: AppModel.primaryWindowID) == a)
        #expect(model.activeWorkspaceID == a, "키 윈도우가 바뀌기 전에는 활성 워크스페이스가 그대로")
        // 두 워크스페이스의 패인 모두 뷰어가 살아 있다
        let paneA = try #require(model.workspace(id: a)?.focusedPaneID)
        let paneB = try #require(model.workspace(id: b)?.focusedPaneID)
        #expect(model.viewer(for: paneA) != nil)
        #expect(model.viewer(for: paneB) != nil)
        #expect(model.fileTree(inWindow: w2)?.root.standardizedFileURL == rootB.standardizedFileURL)

        // 창 2가 키 윈도우가 되면 메뉴 대상(활성)이 b
        model.windowDidBecomeKey(w2)
        #expect(model.activeWorkspaceID == b)
        #expect(model.workspace.rootURL?.standardizedFileURL == rootB.standardizedFileURL)

        // 창 2에서 a를 고르면(이미 기본 창에 있음) 창 2는 그대로
        model.activateWorkspace(a)
        #expect(model.workspaceID(inWindow: w2) == b)
        #expect(model.activeWorkspaceID == b)

        // 아직 어디에도 없는 c를 고르면 창 2가 c를 보여 주고 b는 숨는다(뷰어 정리)
        let rootC = try Self.makeWorkspaceRoot("c")
        defer { try? FileManager.default.removeItem(at: rootC) }
        let c = model.addWorkspace(root: rootC, ephemeral: false)
        #expect(model.workspaceID(inWindow: w2) == c)
        #expect(model.activeWorkspaceID == c)
        #expect(model.viewer(for: paneB) == nil)
        #expect(model.viewer(for: paneA) != nil)
        #expect(model.fileTree(inWindow: w2)?.root.standardizedFileURL == rootC.standardizedFileURL)

        // 창 2를 닫으면 슬롯이 사라지고 기본 창이 키 윈도우
        model.windowWillClose(w2)
        #expect(model.windowSlots.map(\.id) == [AppModel.primaryWindowID])
        #expect(model.keyWindowID == AppModel.primaryWindowID)
        #expect(model.activeWorkspaceID == a)
        #expect(model.workspaces.count == 3, "닫힌 창의 워크스페이스는 목록에 남는다")
    }

    @Test func closingWorkspaceShownInAWindowGivesThatWindowAnotherOne() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rootA = try Self.makeWorkspaceRoot("a"), rootB = try Self.makeWorkspaceRoot("b")
        defer { try? FileManager.default.removeItem(at: rootA); try? FileManager.default.removeItem(at: rootB) }
        let a = model.addWorkspace(root: rootA, ephemeral: false)
        let b = model.addWorkspace(root: rootB, ephemeral: false, activate: false)
        let w2 = model.openNewWindow(showing: b)
        _ = model.consumeWindowOpenRequest(w2)
        model.ensureWindowSlot(w2)
        model.windowDidBecomeKey(w2)
        model.closeWorkspace(b)
        #expect(!model.workspaces.contains { $0.id == b })
        let replacement = try #require(model.workspaceID(inWindow: w2))
        #expect(replacement != a, "기본 창이 보여 주는 a는 두 창에 동시에 뜰 수 없다")
        #expect(model.workspace(id: replacement)?.isEphemeral == true)
        #expect(model.activeWorkspaceID == replacement)
        #expect(model.windowSlots.count == 2)
    }

    @Test func emptyNewWindowGetsFreshTemporaryWorkspaceThatVanishesOnClose() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let before = model.workspaces.count
        let w2 = model.openNewWindow()
        _ = model.consumeWindowOpenRequest(w2)
        model.ensureWindowSlot(w2)
        let fresh = try #require(model.workspaceID(inWindow: w2))
        #expect(model.workspaces.count == before + 1)
        #expect(model.workspace(id: fresh)?.isEphemeral == true)
        model.windowWillClose(w2)
        #expect(model.workspaces.count == before, "비어 있는 임시 워크스페이스는 창과 함께 사라진다")
    }

    @Test func sessionRemembersExtraWindows() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rootA = try Self.makeWorkspaceRoot("a"), rootB = try Self.makeWorkspaceRoot("b")
        defer { try? FileManager.default.removeItem(at: rootA); try? FileManager.default.removeItem(at: rootB) }
        let a = model.addWorkspace(root: rootA, ephemeral: false)
        let b = model.addWorkspace(root: rootB, ephemeral: false, activate: false)
        let w2 = model.openNewWindow(showing: b)
        _ = model.consumeWindowOpenRequest(w2)
        model.ensureWindowSlot(w2)
        model.saveNow()
        let session = try #require(try SessionStore(directory: dir).load())
        #expect(session.windows?.map(\.workspaceID) == [a, b])

        // 같은 저장소로 새 모델: 기본 창은 a, b를 위한 창 열기 요청이 대기한다
        let restored = AppModel(sessionStore: SessionStore(directory: dir), defaults: UserDefaults(suiteName: "cmarks.tests.\(UUID().uuidString)")!)
        #expect(restored.activeWorkspaceID == a)
        #expect(restored.windowOpenRequests.count == 1)
        let request = try #require(restored.windowOpenRequests.first)
        #expect(restored.consumeWindowOpenRequest(request))
        restored.ensureWindowSlot(request)
        #expect(restored.workspaceID(inWindow: request) == b)
    }

    @Test func closeCommandOnlyClosesUnregisteredWindows() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        let document = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        document.isReleasedWhenClosed = false
        model.registerWindow(document, id: AppModel.primaryWindowID)
        #expect(model.documentWindow === document)
        model.closeActiveTabOrPane(keyWindow: other)   // 등록되지 않은 창 → 그 창을 닫는다
        #expect(!other.isVisible)
        #expect(model.workspace.panes.count == 1)
    }
}
