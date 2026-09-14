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

        // 창 2에서 a를 고르면(이미 기본 창에 있음) 창 2는 그대로, a를 보여 주는 기본 창이 앞으로 와 키가 된다
        model.activateWorkspace(a)
        #expect(model.workspaceID(inWindow: w2) == b)
        #expect(model.keyWindowID == AppModel.primaryWindowID)
        #expect(model.activeWorkspaceID == a)

        // 다시 창 2로 돌아와, 아직 어디에도 없는 c를 고르면 창 2가 c를 보여 주고 b는 숨는다(뷰어 정리)
        model.windowDidBecomeKey(w2)
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

@MainActor
@Suite(.serialized)
struct MultiWindowTargetingTests {
    @Test func actionsTargetTheWindowTheyCameFromNotTheKeyWindow() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rootA = try MultiWindowTests.makeWorkspaceRoot("a"), rootB = try MultiWindowTests.makeWorkspaceRoot("b")
        defer { try? FileManager.default.removeItem(at: rootA); try? FileManager.default.removeItem(at: rootB) }
        try "# extra\n".write(to: rootB.appending(path: "extra.md"), atomically: true, encoding: .utf8)
        let a = model.addWorkspace(root: rootA, ephemeral: false)
        let b = model.addWorkspace(root: rootB, ephemeral: false, activate: false)
        let w2 = model.openNewWindow(showing: b)
        _ = model.consumeWindowOpenRequest(w2)
        model.ensureWindowSlot(w2)
        // 키 윈도우는 기본 창(a)인데, 창 2의 사이드바에서 파일을 클릭한 것처럼 창을 지정해 연다
        model.open(rootB.appending(path: "extra.md"), window: w2)
        #expect(model.workspace(id: b)?.focusedPane?.activeTab?.document.url.lastPathComponent == "extra.md")
        #expect(model.workspace(id: a)?.focusedPane?.tabs.contains { $0.document.url.lastPathComponent == "extra.md" } == false)
        #expect(model.activeWorkspaceID == a, "키 윈도우가 바뀌지 않았으니 활성은 그대로")

        // 창 2의 사이드바에서 a를 고르면(이미 기본 창에 있음) 창 2는 b를 유지
        model.activateWorkspace(a, fromWindow: w2)
        #expect(model.workspaceID(inWindow: w2) == b)
        // 새 워크스페이스 c를 창 2에서 고르면 창 2가 c를 보여 주고, 활성(키 윈도우 기본 창)은 a 그대로
        let rootC = try MultiWindowTests.makeWorkspaceRoot("c")
        defer { try? FileManager.default.removeItem(at: rootC) }
        let c = model.addWorkspace(root: rootC, ephemeral: false, activate: false)
        model.activateWorkspace(c, fromWindow: w2)
        #expect(model.workspaceID(inWindow: w2) == c)
        #expect(model.workspaceID(inWindow: AppModel.primaryWindowID) == a)
        #expect(model.activeWorkspaceID == a)
    }

    @Test func finderOpenGoesToTheWindowShowingThatWorkspace() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rootA = try MultiWindowTests.makeWorkspaceRoot("a"), rootB = try MultiWindowTests.makeWorkspaceRoot("b")
        let outside = try MultiWindowTests.makeWorkspaceRoot("outside")
        defer { for r in [rootA, rootB, outside] { try? FileManager.default.removeItem(at: r) } }
        try "# deep\n".write(to: rootB.appending(path: "deep.md"), atomically: true, encoding: .utf8)
        let a = model.addWorkspace(root: rootA, ephemeral: false)
        model.open(rootA.appending(path: "README.md"))   // 워크스페이스 추가는 문서를 열지 않으므로 직접 연다
        let b = model.addWorkspace(root: rootB, ephemeral: false, activate: false)
        let w2 = model.openNewWindow(showing: b)
        _ = model.consumeWindowOpenRequest(w2)
        model.ensureWindowSlot(w2)
        #expect(model.keyWindowID == AppModel.primaryWindowID)

        // Finder에서 b 안의 파일 → b를 보여 주는 창 2에 열리고 그 창이 앞으로 온다. 기본 창(a)은 그대로
        model.openFromOutside([rootB.appending(path: "deep.md")])
        #expect(model.workspace(id: b)?.focusedPane?.activeTab?.document.url.lastPathComponent == "deep.md")
        #expect(model.workspace(id: a)?.focusedPane?.activeTab?.document.url.lastPathComponent == "README.md")
        #expect(model.windowSlots.count == 2, "창이 늘지 않는다")
        #expect(model.keyWindowID == w2, "b를 보여 주는 창이 키가 된다")

        // 사용자가 기본 창으로 돌아온 뒤, 어느 워크스페이스에도 없는 파일 → 키 윈도우(기본 창)에 임시 워크스페이스로. 창 수 유지, b 창은 그대로
        model.windowDidBecomeKey(AppModel.primaryWindowID)
        model.openFromOutside([outside.appending(path: "README.md")])
        let primaryWS = try #require(model.workspace(inWindow: AppModel.primaryWindowID))
        #expect(primaryWS.isEphemeral)
        #expect(primaryWS.rootURL?.standardizedFileURL == outside.standardizedFileURL)
        #expect(primaryWS.focusedPane?.activeTab?.document.url.lastPathComponent == "README.md")
        #expect(model.workspaceID(inWindow: w2) == b)
        #expect(model.windowSlots.count == 2)
        #expect(model.workspaces.contains { $0.id == a }, "숨겨진 a는 목록에 남는다")
    }

    @Test func duplicateSceneValueGetsAFreshWindowID() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        first.isReleasedWhenClosed = false
        first.orderFront(nil)
        model.registerWindow(first, id: AppModel.primaryWindowID)
        #expect(model.resolveWindowID(preferred: AppModel.primaryWindowID, window: first) == AppModel.primaryWindowID, "같은 창은 같은 ID")
        let second = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        second.isReleasedWhenClosed = false
        second.orderFront(nil)
        let resolved = model.resolveWindowID(preferred: AppModel.primaryWindowID, window: second)
        #expect(resolved != AppModel.primaryWindowID, "다른 창이 같은 값으로 오면 새 ID")
        model.registerWindow(second, id: resolved)
        #expect(model.windowSlots.count == 2)
        #expect(Set(model.windowSlots.map(\.workspaceID)).count == 2, "두 창이 같은 워크스페이스를 그리지 않는다")
        #expect(first.isRestorable == false && second.isRestorable == false, "AppKit 창 복원은 끈다")
        first.close(); second.close()
    }

    @Test func paletteOpensInTheWindowItWasPresentedIn() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rootA = try MultiWindowTests.makeWorkspaceRoot("a"), rootB = try MultiWindowTests.makeWorkspaceRoot("b")
        defer { try? FileManager.default.removeItem(at: rootA); try? FileManager.default.removeItem(at: rootB) }
        try "# two\n".write(to: rootB.appending(path: "two.md"), atomically: true, encoding: .utf8)
        _ = model.addWorkspace(root: rootA, ephemeral: false)
        model.open(rootA.appending(path: "README.md"))
        let b = model.addWorkspace(root: rootB, ephemeral: false, activate: false)
        let w2 = model.openNewWindow(showing: b)
        _ = model.consumeWindowOpenRequest(w2)
        model.ensureWindowSlot(w2)
        model.presentQuickOpen(inWindow: w2)
        #expect(model.paletteWindowID == w2)
        for _ in 0..<60 where model.quickOpen.isIndexing { try await Task.sleep(for: .milliseconds(50)) }
        model.quickOpen.query = "two"
        // 검색은 디바운스되고 그 전까지는 최근 파일 목록이 남아 있으므로 결과가 바뀔 때까지 기다린다
        for _ in 0..<60 where model.quickOpen.selected?.url.lastPathComponent != "two.md" { try await Task.sleep(for: .milliseconds(50)) }
        #expect(model.quickOpen.selected?.url.lastPathComponent == "two.md")
        model.openQuickOpenSelection()
        #expect(model.workspace(id: b)?.focusedPane?.activeTab?.document.url.lastPathComponent == "two.md")
        #expect(model.workspace(inWindow: AppModel.primaryWindowID)?.focusedPane?.activeTab?.document.url.lastPathComponent == "README.md")
    }
}

/// 창 수명 주기: 닫힌 창은 되살아나지 않고, 세션은 다음 실행에서 창을 그대로 재현한다.
@MainActor
@Suite(.serialized)
struct MultiWindowLifecycleTests {
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    /// SwiftUI는 닫힌 창의 뷰를 한동안 다시 그리므로 WindowAccessor가 같은 창을 재등록하려 든다. 슬롯이 되살아나면 안 된다.
    @Test func closedWindowDoesNotComeBackWhenItsViewReRegisters() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rootA = try MultiWindowTests.makeWorkspaceRoot("a"), rootB = try MultiWindowTests.makeWorkspaceRoot("b")
        defer { try? FileManager.default.removeItem(at: rootA); try? FileManager.default.removeItem(at: rootB) }
        let a = model.addWorkspace(root: rootA, ephemeral: false)
        let b = model.addWorkspace(root: rootB, ephemeral: false, activate: false)
        let primary = makeWindow(); primary.orderFront(nil)
        model.registerWindow(primary, id: AppModel.primaryWindowID)
        let w2 = model.openNewWindow(showing: b)
        _ = model.consumeWindowOpenRequest(w2)
        let second = makeWindow(); second.orderFront(nil)
        model.registerWindow(second, id: w2)
        #expect(model.windowSlots.map(\.workspaceID) == [a, b])

        second.close()   // willCloseNotification → 슬롯 제거
        #expect(model.windowSlots.map(\.id) == [AppModel.primaryWindowID])
        #expect(model.workspaces.map(\.id).contains(b), "영구 워크스페이스는 남는다")

        model.registerWindow(second, id: w2)   // 닫힌 창의 뷰가 다시 그려지며 재등록 시도
        #expect(model.windowSlots.map(\.id) == [AppModel.primaryWindowID], "닫힌 창은 슬롯을 되살리지 못한다")
        #expect(model.window(forSlot: w2) == nil)

        // 이제 b를 고르면 숨은 창을 띄우는 대신 현재 창에서 보여 준다
        model.activateWorkspace(b, fromWindow: AppModel.primaryWindowID)
        #expect(model.workspaceID(inWindow: AppModel.primaryWindowID) == b)
        #expect(!second.isVisible, "닫힌 창이 다시 나타나지 않는다")
        primary.close()
    }

    /// 키 창이 임시 워크스페이스(Finder에서 연 파일)만 보여 주고 다른 창이 영구 워크스페이스를 보여 줄 때,
    /// 저장된 활성 워크스페이스는 저장되는 창의 것이어야 다음 실행에서 창이 하나 더 생기지 않는다.
    @Test func sessionActiveWorkspaceFollowsTheSavedWindows() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rootA = try MultiWindowTests.makeWorkspaceRoot("a"), rootB = try MultiWindowTests.makeWorkspaceRoot("b")
        let outside = try MultiWindowTests.makeWorkspaceRoot("outside")
        defer { try? FileManager.default.removeItem(at: rootA); try? FileManager.default.removeItem(at: rootB); try? FileManager.default.removeItem(at: outside) }
        let a = model.addWorkspace(root: rootA, ephemeral: false)
        let b = model.addWorkspace(root: rootB, ephemeral: false, activate: false)
        let w2 = model.openNewWindow(showing: b)
        _ = model.consumeWindowOpenRequest(w2)
        model.ensureWindowSlot(w2)
        // 키 창(기본 창)에서 밖의 파일을 열면 임시 워크스페이스가 그 창을 차지한다
        model.openFromOutside([outside.appending(path: "README.md")])
        let shown = try #require(model.workspace(inWindow: AppModel.primaryWindowID))
        #expect(shown.isEphemeral && shown.id != a)
        model.saveNow()

        let session = try #require(try SessionStore(directory: dir).load())
        #expect(session.windows?.map(\.workspaceID) == [b], "임시 워크스페이스 창은 저장하지 않는다")
        #expect(session.activeWorkspaceID == b, "활성은 저장된 첫 창의 워크스페이스")
        #expect(Set(session.workspaces.map(\.id)) == [a, b])

        let restored = AppModel(sessionStore: SessionStore(directory: dir), defaults: UserDefaults(suiteName: "cmarks.tests.\(UUID().uuidString)")!)
        #expect(restored.activeWorkspaceID == b)
        #expect(restored.windowSlots.map(\.workspaceID) == [b], "기본 창이 b를 맡는다")
        #expect(restored.windowOpenRequests.isEmpty, "창이 하나 더 열리지 않는다")
        #expect(restored.workspaces.map(\.id).contains(a), "a는 목록에 남는다")
    }

    /// 저장된 활성 워크스페이스가 어떤 창에도 없는 오래된 세션 파일도 창 하나로 복원한다.
    @Test func staleSessionWithActiveWorkspaceOutsideWindowsRestoresOneWindow() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rootA = try MultiWindowTests.makeWorkspaceRoot("a"), rootB = try MultiWindowTests.makeWorkspaceRoot("b")
        defer { try? FileManager.default.removeItem(at: rootA); try? FileManager.default.removeItem(at: rootB) }
        let a = model.addWorkspace(root: rootA, ephemeral: false)
        let b = model.addWorkspace(root: rootB, ephemeral: false, activate: false)
        model.saveNow()
        var session = try #require(try SessionStore(directory: dir).load())
        session = Session(workspaces: session.workspaces, activeWorkspaceID: a, windows: [SessionWindow(workspaceID: b, frame: nil)])
        try SessionStore(directory: dir).save(session)

        let restored = AppModel(sessionStore: SessionStore(directory: dir), defaults: UserDefaults(suiteName: "cmarks.tests.\(UUID().uuidString)")!)
        #expect(restored.windowSlots.map(\.workspaceID) == [b])
        #expect(restored.windowOpenRequests.isEmpty)
        #expect(restored.activeWorkspaceID == b)
    }
}
