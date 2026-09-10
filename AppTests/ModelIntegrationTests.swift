import AppKit
import Foundation
import LayoutKit
import MarkdownCore
import Testing
@testable import cmarks

/// AppModel 수준의 동작. 임시 세션 저장소와 별도 UserDefaults를 써서 사용자 상태를 건드리지 않는다.
@MainActor
@Suite(.serialized)
struct ModelIntegrationTests {
    /// R-18: 분할로 열린 탭을 닫으면 원래 패인이 정확히 이전 폭으로 돌아온다.
    @Test func closingSplitTabRestoresOriginalWidth() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixtures = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: fixtures) }
        model.viewportSize = CGSize(width: 1200, height: 800)
        model.open(fixtures.appending(path: "kitchen-sink.md"))
        model.split(.right) // 두 패인: 왼쪽에 포커스가 아니라 새 오른쪽 패인에 포커스
        model.focusNeighbor(.left)
        let before = model.layoutFrames(in: CGRect(origin: .zero, size: model.viewportSize))
        let leftPane = model.focusedPaneID
        let leftWidthBefore = before.rect(of: leftPane)!.width

        // ⌥클릭에 해당: 왼쪽 패인에서 오른쪽 분할로 열기
        model.navigate(DocumentRef(url: fixtures.appending(path: "sub/linked.md")), intent: .newSplit(.right), from: leftPane)
        #expect(model.workspace.panes.count == 3)
        let during = model.layoutFrames(in: CGRect(origin: .zero, size: model.viewportSize))
        #expect(during.rect(of: leftPane)!.width < leftWidthBefore)

        model.closeActiveTabOrPane(keyWindow: nil) // 새 패인의 유일한 탭 → 패인 닫힘
        #expect(model.workspace.panes.count == 2)
        let after = model.layoutFrames(in: CGRect(origin: .zero, size: model.viewportSize))
        #expect(after.rect(of: leftPane)!.width == leftWidthBefore)
        #expect(model.focusedPaneID == leftPane) // 최근 사용 패인으로 복귀
    }

    /// R-19: 빠른 열기에서 ⌘⇧⏎는 아래 분할로 연다.
    @Test func quickOpenSplitDownOpensBelowFocusedPane() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixtures = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: fixtures) }
        model.addWorkspace(root: fixtures, ephemeral: false)
        model.open(fixtures.appending(path: "kitchen-sink.md"))
        let original = model.focusedPaneID

        model.presentQuickOpen()
        model.quickOpen.query = "linked"
        #expect(await waitUntil { model.quickOpen.results.contains { $0.url.lastPathComponent == "linked.md" } })
        model.quickOpen.selectedIndex = model.quickOpen.results.firstIndex { $0.url.lastPathComponent == "linked.md" }!
        model.openQuickOpenSelection(split: .down)

        #expect(!model.quickOpen.isPresented)
        #expect(model.workspace.panes.count == 2)
        guard case .split(let split) = model.workspace.layout else { Issue.record("expected split"); return }
        #expect(split.axis == .vertical)
        #expect(model.focusedPaneID != original)
        #expect(model.focusedTab?.document.url.lastPathComponent == "linked.md")
        let frames = model.layoutFrames(in: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(frames.rect(of: model.focusedPaneID)!.minY > frames.rect(of: original)!.minY)
    }

    /// R-21: 다른 창이 키 윈도우면 ⌘W는 그 창을 닫고 탭은 그대로다.
    @Test func closeCommandClosesForeignKeyWindowInsteadOfTab() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixtures = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: fixtures) }
        model.open(fixtures.appending(path: "kitchen-sink.md"))
        #expect(model.focusedTab != nil)

        let documentWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        settingsWindow.isReleasedWhenClosed = false
        documentWindow.isReleasedWhenClosed = false
        settingsWindow.orderFront(nil)
        model.documentWindow = documentWindow

        model.closeActiveTabOrPane(keyWindow: settingsWindow)
        #expect(model.focusedTab != nil)
        #expect(!settingsWindow.isVisible)

        model.closeActiveTabOrPane(keyWindow: documentWindow)
        #expect(model.focusedTab == nil)
    }

    /// ⌘⇧T: 닫은 탭이 히스토리와 함께 돌아온다.
    @Test func reopenClosedTabRestoresTab() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixtures = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: fixtures) }
        model.open(fixtures.appending(path: "kitchen-sink.md"))
        model.open(fixtures.appending(path: "sub/linked.md"))
        #expect(model.workspace.focusedPane?.tabs.count == 2)
        #expect(!model.canReopenClosedTab)
        model.closeActiveTabOrPane(keyWindow: nil)
        #expect(model.workspace.focusedPane?.tabs.count == 1)
        #expect(model.canReopenClosedTab)
        model.reopenLastClosedTab()
        #expect(model.workspace.focusedPane?.tabs.count == 2)
        #expect(model.focusedTab?.document.url.lastPathComponent == "linked.md")
    }

    /// R-24: 디바이더 자리는 웹뷰(패인)와 겹치지 않는 7pt 전용 영역이다.
    @Test func dividersDoNotOverlapPanes() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        model.split(.right)
        model.split(.down)
        let frames = model.layoutFrames(in: CGRect(x: 0, y: 0, width: 1200, height: 800))
        #expect(frames.dividers.count == 2)
        for divider in frames.dividers {
            let thickness = divider.axis == .horizontal ? divider.rect.width : divider.rect.height
            #expect(thickness == 7)
            for pane in frames.panes {
                #expect(!pane.rect.intersects(divider.rect), "pane \(pane.rect) overlaps divider \(divider.rect)")
            }
        }
    }

    /// 임시 워크스페이스: 밖의 파일을 열면 생기고, 마지막 탭을 닫으면 사라진다.
    @Test func ephemeralWorkspaceLifecycle() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixtures = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: fixtures) }
        model.addWorkspace(root: fixtures.appending(path: "sub"), ephemeral: false)
        #expect(model.workspaces.count == 1)

        model.openFromOutside([fixtures.appending(path: "kitchen-sink.md")])
        #expect(model.workspaces.count == 2)
        #expect(model.workspace.isEphemeral)
        #expect(model.workspace.rootURL?.standardizedFileURL == fixtures.standardizedFileURL)

        model.closeActiveTabOrPane(keyWindow: nil)
        #expect(model.workspaces.count == 1)
        #expect(!model.workspace.isEphemeral)

        // 포함하는 워크스페이스가 있으면 그 안에서 연다
        model.openFromOutside([fixtures.appending(path: "sub/linked.md")])
        #expect(model.workspaces.count == 1)
        #expect(model.focusedTab?.document.url.lastPathComponent == "linked.md")
    }

    /// 설정 변경이 렌더 설정과 파일 필터에 반영된다.
    @Test func settingsChangesPropagate() async throws {
        let (model, dir) = try makeTestModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        model.settings.math = false
        #expect(model.documents.settings.math == false)
        model.settings.markdownExtensions = "md txt"
        #expect(DocumentService.isMarkdown(URL(fileURLWithPath: "/tmp/a.txt")))
        model.settings.markdownExtensions = AppSettings.defaultExtensions
        #expect(!DocumentService.isMarkdown(URL(fileURLWithPath: "/tmp/a.txt")))
        model.settings.useGitHubWidth = false
        #expect(model.documents.settings.contentMaxWidth == nil)
    }
}
