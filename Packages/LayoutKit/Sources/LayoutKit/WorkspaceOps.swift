import CoreGraphics
import Foundation

/// 패인·탭 연산. 트리(layout)와 패인 목록(panes), 포커스를 함께 일관되게 바꾼다.
public extension Workspace {
    // MARK: 패인

    /// 포커스 패인 옆에 새 패인을 만든다. 기본으로 활성 탭을 복제해 시작한다. 새 패인이 포커스를 받는다.
    @discardableResult
    mutating func splitFocusedPane(direction: SplitDirection, duplicateActiveTab: Bool = true) -> PaneID {
        let source = focusedPane
        var tabs: [Tab] = []
        if duplicateActiveTab, let active = source?.activeTab {
            var copy = Tab(document: active.document, isPinned: false, zoom: active.zoom)
            copy.history = active.history
            copy.historyIndex = active.historyIndex
            copy.scrollY = active.scrollY
            tabs = [copy]
        }
        let pane = Pane(tabs: tabs)
        panes.append(pane)
        layout = layout.inserting(pane.id, relativeTo: focusedPaneID, direction: direction)
        setFocus(pane.id)
        if zoomedPaneID != nil { zoomedPaneID = nil }
        return pane.id
    }

    /// 패인을 닫는다. 마지막 패인이면 지우지 않고 빈 패인으로 남긴다.
    /// 포커스는 가장 최근에 쓰던 패인 → 방향 이웃 → 첫 패인 순으로 옮긴다. 닫힌 패인의 탭은 최근 닫은 탭에 남는다.
    mutating func closePane(_ id: PaneID, viewport: CGRect = CGRect(x: 0, y: 0, width: 1000, height: 1000)) {
        guard let closing = pane(id) else { return }
        rememberClosed(closing.tabs)
        if panes.count == 1 {
            var pane = panes[0]
            pane.tabs.removeAll()
            pane.activeTabID = nil
            panes[0] = pane
            return
        }
        let neighbor = layout.neighbor(of: id, direction: .left, in: viewport)
            ?? layout.neighbor(of: id, direction: .right, in: viewport)
            ?? layout.neighbor(of: id, direction: .up, in: viewport)
            ?? layout.neighbor(of: id, direction: .down, in: viewport)
        guard let remaining = layout.removing(id) else { return }
        layout = remaining
        panes.removeAll { $0.id == id }
        focusHistory?.removeAll { $0 == id }
        if zoomedPaneID == id { zoomedPaneID = nil }
        if focusedPaneID == id {
            let recent = focusHistory?.first { candidate in pane(candidate) != nil }
            setFocus(recent ?? neighbor.flatMap { pane($0) != nil ? $0 : nil } ?? panes[0].id)
        }
    }

    mutating func focus(_ id: PaneID) {
        guard pane(id) != nil else { return }
        setFocus(id)
    }

    /// 방향 이웃으로 포커스 이동. 이동했으면 true.
    @discardableResult
    mutating func focusNeighbor(_ direction: FocusDirection, viewport: CGRect) -> Bool {
        guard let next = layout.neighbor(of: focusedPaneID, direction: direction, in: viewport) else { return false }
        setFocus(next)
        return true
    }

    /// 포커스 패인 크기 조정(⌃⌥⌘ 화살표).
    mutating func resizeFocusedPane(_ direction: FocusDirection, by pixels: CGFloat, viewport: CGRect, minimumSize: CGFloat = 120) {
        layout = layout.resizingLeaf(focusedPaneID, direction: direction, by: pixels, in: viewport, minimumSize: minimumSize)
    }

    mutating func toggleZoom(_ id: PaneID? = nil) {
        let target = id ?? focusedPaneID
        zoomedPaneID = zoomedPaneID == target ? nil : target
    }

    // MARK: 탭

    /// 문서를 패인에 연다. 같은 문서의 탭이 있으면 그 탭을 활성화한다.
    /// `preview`면 기존 미리보기 탭을 재사용하고, 아니면 활성 탭 바로 뒤에 새 탭을 만든다.
    @discardableResult
    mutating func openTab(_ ref: DocumentRef, in paneID: PaneID? = nil, preview: Bool = false, activate: Bool = true, zoom: Double = 1.0) -> Tab.ID? {
        let targetID = paneID ?? focusedPaneID
        guard var pane = pane(targetID) else { return nil }

        if let existing = pane.tabs.firstIndex(where: { $0.document.url == ref.url }) {
            pane.tabs[existing].document = ref
            if !preview { pane.tabs[existing].isPreview = false }
            if activate { pane.activeTabID = pane.tabs[existing].id }
            update(pane)
            return pane.tabs[existing].id
        }

        if preview, let previewIndex = pane.tabs.firstIndex(where: { $0.isPreview }) {
            var tab = pane.tabs[previewIndex]
            tab.navigate(to: ref)
            tab.scrollY = 0
            pane.tabs[previewIndex] = tab
            if activate { pane.activeTabID = tab.id }
            update(pane)
            return tab.id
        }

        let tab = Tab(document: ref, isPreview: preview, zoom: zoom)
        let insertAt = pane.tabs.firstIndex(where: { $0.id == pane.activeTabID }).map { $0 + 1 } ?? pane.tabs.count
        pane.tabs.insert(tab, at: insertAt)
        if activate || pane.activeTabID == nil { pane.activeTabID = tab.id }
        update(pane)
        return tab.id
    }

    /// 탭을 닫는다. 마지막 탭이면 패인도 닫힌다(단일 패인은 빈 패인으로 남음). 닫힌 탭이 활성이었다면 오른쪽 → 왼쪽 탭이 활성.
    mutating func closeTab(_ tabID: Tab.ID, in paneID: PaneID, viewport: CGRect = CGRect(x: 0, y: 0, width: 1000, height: 1000)) {
        guard var pane = pane(paneID), let index = pane.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let removed = pane.tabs.remove(at: index)
        rememberClosed([removed])
        if pane.tabs.isEmpty {
            update(pane)
            closePane(paneID, viewport: viewport)
            return
        }
        if pane.activeTabID == tabID {
            pane.activeTabID = pane.tabs[min(index, pane.tabs.count - 1)].id
        }
        update(pane)
    }

    /// 다른 탭을 모두 닫는다(고정 탭 제외).
    mutating func closeOtherTabs(keeping tabID: Tab.ID, in paneID: PaneID) {
        guard var target = pane(paneID) else { return }
        let closing = target.tabs.filter { $0.id != tabID && !$0.isPinned }
        rememberClosed(closing)
        target.tabs.removeAll { $0.id != tabID && !$0.isPinned }
        target.activeTabID = target.tabs.contains(where: { $0.id == tabID }) ? tabID : target.tabs.first?.id
        update(target)
    }

    /// 가장 최근에 닫은 탭을 포커스 패인에 되살린다(히스토리·스크롤 유지). 같은 문서가 이미 있으면 그 탭을 활성화한다.
    @discardableResult
    mutating func reopenLastClosedTab() -> Tab.ID? {
        guard var closed = recentlyClosedTabs, !closed.isEmpty, var pane = focusedPane else { return nil }
        var tab = closed.removeFirst()
        recentlyClosedTabs = closed
        tab.isPreview = false
        if let existing = pane.tabs.firstIndex(where: { $0.document.url == tab.document.url }) {
            pane.activeTabID = pane.tabs[existing].id
            update(pane)
            return pane.tabs[existing].id
        }
        let insertAt = pane.tabs.firstIndex(where: { $0.id == pane.activeTabID }).map { $0 + 1 } ?? pane.tabs.count
        pane.tabs.insert(tab, at: insertAt)
        pane.activeTabID = tab.id
        update(pane)
        return tab.id
    }

    mutating func activateTab(_ tabID: Tab.ID, in paneID: PaneID) {
        guard var pane = pane(paneID), pane.tabs.contains(where: { $0.id == tabID }) else { return }
        pane.activeTabID = tabID
        update(pane)
        setFocus(paneID)
    }

    /// 활성 탭에서 offset(+1 다음, -1 이전)만큼 순환 이동.
    mutating func cycleTab(in paneID: PaneID, offset: Int) {
        guard var pane = pane(paneID), pane.tabs.count > 1,
              let current = pane.tabs.firstIndex(where: { $0.id == pane.activeTabID }) else { return }
        let next = (current + offset + pane.tabs.count) % pane.tabs.count
        pane.activeTabID = pane.tabs[next].id
        update(pane)
    }

    mutating func activateTab(at index: Int, in paneID: PaneID) {
        guard var pane = pane(paneID), pane.tabs.indices.contains(index) else { return }
        pane.activeTabID = pane.tabs[index].id
        update(pane)
    }

    /// 탭을 다른 위치(같은 패인 재정렬 또는 다른 패인)로 옮긴다. `index`는 목적지 패인에서의 위치(nil이면 끝).
    mutating func moveTab(_ tabID: Tab.ID, from sourceID: PaneID, to destinationID: PaneID, index: Int? = nil, viewport: CGRect = CGRect(x: 0, y: 0, width: 1000, height: 1000)) {
        guard var source = pane(sourceID), let sourceIndex = source.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let tab = source.tabs.remove(at: sourceIndex)

        if sourceID == destinationID {
            // 명시한 index는 제거 전 목록 기준이라 원래 자리보다 뒤면 하나 당긴다. nil은 맨 끝.
            var target = index.map { $0 > sourceIndex ? $0 - 1 : $0 } ?? source.tabs.count
            target = min(max(0, target), source.tabs.count)
            source.tabs.insert(tab, at: target)
            update(source)
            return
        }

        guard var destination = pane(destinationID) else { return }
        if source.activeTabID == tabID {
            source.activeTabID = source.tabs.isEmpty ? nil : source.tabs[min(sourceIndex, source.tabs.count - 1)].id
        }
        let target = min(max(0, index ?? destination.tabs.count), destination.tabs.count)
        destination.tabs.insert(tab, at: target)
        destination.activeTabID = tab.id
        update(destination)
        update(source)
        setFocus(destinationID)
        if source.tabs.isEmpty {
            closePane(sourceID, viewport: viewport)
        }
    }

    mutating func togglePin(_ tabID: Tab.ID, in paneID: PaneID) {
        updateTab(tabID, in: paneID) { $0.isPinned.toggle(); if $0.isPinned { $0.isPreview = false } }
    }

    mutating func updateTab(_ tabID: Tab.ID, in paneID: PaneID, _ mutate: (inout Tab) -> Void) {
        guard var pane = pane(paneID), let index = pane.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        mutate(&pane.tabs[index])
        update(pane)
    }

    mutating func updateActiveTab(in paneID: PaneID? = nil, _ mutate: (inout Tab) -> Void) {
        let target = paneID ?? focusedPaneID
        guard let tabID = pane(target)?.activeTabID else { return }
        updateTab(tabID, in: target, mutate)
    }

    // MARK: 내부

    /// 포커스를 옮기고 MRU 기록을 갱신한다.
    private mutating func setFocus(_ id: PaneID) {
        focusedPaneID = id
        var history = focusHistory ?? []
        history.removeAll { $0 == id }
        history.insert(id, at: 0)
        focusHistory = history
    }

    private mutating func rememberClosed(_ tabs: [Tab]) {
        guard !tabs.isEmpty else { return }
        var closed = recentlyClosedTabs ?? []
        closed.insert(contentsOf: tabs.reversed(), at: 0)
        if closed.count > 20 { closed.removeLast(closed.count - 20) }
        recentlyClosedTabs = closed
    }

    // MARK: 불변식

    func validate() -> [String] {
        var problems = layout.validate()
        let treeIDs = Set(layout.paneIDs)
        let listIDs = Set(panes.map(\.id))
        if treeIDs != listIDs { problems.append("layout panes \(treeIDs.count) != pane list \(listIDs.count)") }
        if !listIDs.contains(focusedPaneID) { problems.append("focused pane missing") }
        if let zoomed = zoomedPaneID, !listIDs.contains(zoomed) { problems.append("zoomed pane missing") }
        for pane in panes {
            if let active = pane.activeTabID, !pane.tabs.contains(where: { $0.id == active }) { problems.append("pane \(pane.id.raw) active tab missing") }
            if pane.activeTabID == nil, !pane.tabs.isEmpty { problems.append("pane \(pane.id.raw) has tabs but no active tab") }
            let ids = pane.tabs.map(\.id)
            if Set(ids).count != ids.count { problems.append("pane \(pane.id.raw) duplicate tab ids") }
        }
        return problems
    }
}
