import CoreGraphics
import Foundation
import Testing
@testable import LayoutKit

struct WorkspaceOpsTests {
    let docA = DocumentRef(url: URL(fileURLWithPath: "/tmp/a.md"))
    let docB = DocumentRef(url: URL(fileURLWithPath: "/tmp/b.md"))
    let docC = DocumentRef(url: URL(fileURLWithPath: "/tmp/c.md"))

    @Test func splitDuplicatesActiveTabAndFocusesNewPane() {
        var ws = Workspace.single(document: docA)
        let original = ws.focusedPaneID
        let created = ws.splitFocusedPane(direction: .right)
        #expect(ws.panes.count == 2)
        #expect(ws.focusedPaneID == created)
        #expect(ws.pane(created)?.activeTab?.document == docA)
        #expect(ws.pane(created)?.activeTab?.id != ws.pane(original)?.activeTab?.id)
        #expect(ws.layout.paneIDs == [original, created])
        #expect(ws.validate().isEmpty)
    }

    @Test func openTabReusesExistingDocumentAndInsertsAfterActive() {
        var ws = Workspace.single(document: docA)
        let pane = ws.focusedPaneID
        let b = ws.openTab(docB)
        #expect(ws.pane(pane)?.tabs.map(\.document) == [docA, docB])
        #expect(ws.pane(pane)?.activeTabID == b)

        ws.activateTab(at: 0, in: pane)
        let again = ws.openTab(docB)
        #expect(again == b)
        #expect(ws.pane(pane)?.tabs.count == 2)
        #expect(ws.pane(pane)?.activeTabID == b)

        ws.activateTab(at: 0, in: pane)
        ws.openTab(docC)
        #expect(ws.pane(pane)?.tabs.map(\.document) == [docA, docC, docB])
    }

    @Test func previewTabIsReplacedByNextPreview() {
        var ws = Workspace.single()
        let pane = ws.focusedPaneID
        let first = ws.openTab(docA, preview: true)
        let second = ws.openTab(docB, preview: true)
        #expect(first == second)
        #expect(ws.pane(pane)?.tabs.count == 1)
        #expect(ws.pane(pane)?.activeTab?.document == docB)
        #expect(ws.pane(pane)?.activeTab?.history == [docA, docB])

        ws.openTab(docB) // 고정 열기 → 미리보기 해제
        #expect(ws.pane(pane)?.activeTab?.isPreview == false)
        ws.openTab(docC, preview: true)
        #expect(ws.pane(pane)?.tabs.count == 2)
    }

    @Test func closingLastTabClosesPaneExceptWhenOnlyPane() {
        var ws = Workspace.single(document: docA)
        let first = ws.focusedPaneID
        let second = ws.splitFocusedPane(direction: .right)
        let tab = ws.pane(second)!.activeTabID!
        ws.closeTab(tab, in: second)
        #expect(ws.panes.count == 1)
        #expect(ws.focusedPaneID == first)
        #expect(ws.layout == .leaf(first))

        ws.closeTab(ws.pane(first)!.activeTabID!, in: first)
        #expect(ws.panes.count == 1)
        #expect(ws.pane(first)?.tabs.isEmpty == true)
        #expect(ws.pane(first)?.activeTabID == nil)
        #expect(ws.validate().isEmpty)
    }

    @Test func closingActiveTabActivatesRightThenLeftNeighbor() {
        var ws = Workspace.single(document: docA)
        let pane = ws.focusedPaneID
        let b = ws.openTab(docB)!
        let c = ws.openTab(docC)!
        ws.activateTab(b, in: pane)
        ws.closeTab(b, in: pane)
        #expect(ws.pane(pane)?.activeTabID == c)
        ws.closeTab(c, in: pane)
        #expect(ws.pane(pane)?.activeTab?.document == docA)
    }

    @Test func moveTabBetweenPanesClosesEmptySource() {
        var ws = Workspace.single(document: docA)
        let left = ws.focusedPaneID
        let right = ws.splitFocusedPane(direction: .right, duplicateActiveTab: false)
        let tab = ws.pane(left)!.activeTabID!
        ws.moveTab(tab, from: left, to: right)
        #expect(ws.panes.count == 1)
        #expect(ws.panes[0].id == right)
        #expect(ws.pane(right)?.activeTabID == tab)
        #expect(ws.focusedPaneID == right)
        #expect(ws.validate().isEmpty)
    }

    @Test func reorderWithinPane() {
        var ws = Workspace.single(document: docA)
        let pane = ws.focusedPaneID
        let b = ws.openTab(docB)!
        ws.openTab(docC)
        ws.moveTab(b, from: pane, to: pane, index: 0)
        #expect(ws.pane(pane)?.tabs.map(\.document) == [docB, docA, docC])
        ws.moveTab(b, from: pane, to: pane, index: nil)
        #expect(ws.pane(pane)?.tabs.map(\.document) == [docA, docC, docB])
    }

    @Test func closingFocusedPaneFocusesMostRecentlyUsedPane() {
        var ws = Workspace.single(document: docA)
        let first = ws.focusedPaneID
        let second = ws.splitFocusedPane(direction: .right)   // 포커스: second
        let third = ws.splitFocusedPane(direction: .down)     // 포커스: third (second 아래)
        ws.focus(first)                                       // MRU: first, third, second
        ws.focus(third)                                       // MRU: third, first, second
        ws.closePane(third)
        #expect(ws.focusedPaneID == first)                    // 기하 이웃 규칙이었다면 second
        ws.closePane(first)
        #expect(ws.focusedPaneID == second)
        #expect(ws.validate().isEmpty)
    }

    @Test func reopenLastClosedTabRestoresDocumentHistoryAndScroll() {
        var ws = Workspace.single(document: docA)
        let pane = ws.focusedPaneID
        let b = ws.openTab(docB)!
        ws.updateTab(b, in: pane) { $0.navigate(to: docC); $0.scrollY = 250 }
        ws.closeTab(b, in: pane)
        #expect(ws.pane(pane)?.tabs.count == 1)
        #expect(ws.recentlyClosedTabs?.count == 1)

        let reopened = ws.reopenLastClosedTab()
        #expect(reopened != nil)
        let tab = ws.pane(pane)?.activeTab
        #expect(tab?.document == docC)
        #expect(tab?.history == [docB, docC])
        #expect(tab?.scrollY == 250)
        #expect(ws.recentlyClosedTabs?.isEmpty == true)
        #expect(ws.reopenLastClosedTab() == nil)

        let right = ws.splitFocusedPane(direction: .right, duplicateActiveTab: false)
        ws.openTab(docA, in: right)
        ws.closePane(right)
        #expect(ws.recentlyClosedTabs?.first?.document == docA)

        ws.openTab(docB)
        ws.closeOtherTabs(keeping: ws.pane(ws.focusedPaneID)!.activeTabID!, in: ws.focusedPaneID)
        #expect(ws.pane(ws.focusedPaneID)?.tabs.count == 1)
        #expect((ws.recentlyClosedTabs?.count ?? 0) >= 2)
    }

    @Test func focusNeighborAndZoom() {
        var ws = Workspace.single(document: docA)
        let left = ws.focusedPaneID
        let right = ws.splitFocusedPane(direction: .right)
        let viewport = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let movedLeft = ws.focusNeighbor(.left, viewport: viewport)
        #expect(movedLeft)
        #expect(ws.focusedPaneID == left)
        let movedAgain = ws.focusNeighbor(.left, viewport: viewport)
        #expect(!movedAgain)
        ws.toggleZoom()
        #expect(ws.zoomedPaneID == left)
        ws.toggleZoom()
        #expect(ws.zoomedPaneID == nil)
        ws.toggleZoom(right)
        ws.closePane(right)
        #expect(ws.zoomedPaneID == nil)
        #expect(ws.focusedPaneID == left)
    }
}
