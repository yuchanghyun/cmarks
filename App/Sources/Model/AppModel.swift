import AppKit
import FileKit
import LayoutKit
import MarkdownCore
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// 앱 전역 상태. 워크스페이스 목록과 활성 워크스페이스, 패인마다 하나인 PaneViewer, 사이드바 모델을 관리한다.
/// 활성 워크스페이스의 모델 변경은 `mutate`를 거치며, 변경 뒤에는 뷰어 동기화·임시 워크스페이스 정리·세션 저장 예약이 따라온다.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel(sessionStore: launchSessionStore())

    /// `-CmarksSessionDirectory <경로>`로 실행하면 사용자 세션 대신 그 폴더의 session.json을 쓴다(스크린샷·시험용).
    private static func launchSessionStore() -> SessionStore {
        if let directory = UserDefaults.standard.string(forKey: "CmarksSessionDirectory"), !directory.isEmpty {
            return SessionStore(directory: URL(fileURLWithPath: directory, isDirectory: true))
        }
        return .standard(appName: "cmarks")
    }

    private(set) var workspaces: [Workspace]
    private(set) var activeWorkspaceID: UUID
    private(set) var viewers: [PaneID: PaneViewer] = [:]
    /// 표시 중인 워크스페이스마다 하나. 창이 닫히거나 워크스페이스가 숨겨지면 정리된다.
    private(set) var fileTrees: [UUID: FileTreeModel] = [:]
    /// 활성(키 윈도우) 워크스페이스의 파일 트리.
    var fileTree: FileTreeModel? { fileTrees[activeWorkspaceID] }
    let quickOpen = QuickOpenModel()
    let search = WorkspaceSearchModel()
    let finderFollower = FinderFollower()
    let scrollMemory: ScrollMemory
    let settings: AppSettings
    let documents: DocumentService
    var isShortcutHelpPresented = false
    private var appliedRenderSettings = RenderSettings.github

    /// WorkspaceView가 보고하는 실제 크기(워크스페이스별). 이웃 패인 계산에 쓴다.
    private var viewportSizes: [UUID: CGSize] = [:]
    var viewportSize: CGSize {
        get { viewportSizes[activeWorkspaceID] ?? CGSize(width: 1200, height: 800) }
        set { viewportSizes[activeWorkspaceID] = newValue }
    }
    /// 사이드바에서 이름을 편집 중인 워크스페이스.
    var renamingWorkspaceID: UUID?
    /// 창 하나가 표시하는 워크스페이스. 워크스페이스 목록은 모든 창이 공유하고, 한 워크스페이스는 한 창에만 보인다.
    struct WindowSlot: Identifiable, Equatable {
        let id: UUID
        var workspaceID: UUID
    }
    nonisolated static let primaryWindowID = UUID(uuidString: "C0DE0000-0000-4000-8000-000000000001")!
    private(set) var windowSlots: [WindowSlot] = []
    /// 키 윈도우. 메뉴·단축키는 이 창의 워크스페이스에 적용된다.
    private(set) var keyWindowID: UUID = AppModel.primaryWindowID
    /// ContentView가 SwiftUI openWindow로 열어야 할 창 ID.
    private(set) var windowOpenRequests: [UUID] = []
    private var pendingWindowWorkspaces: [UUID: UUID] = [:]
    private var restoredExtraWindows: [UUID] = []
    private var windowRefs: [UUID: WeakWindow] = [:]
    private var windowObservers: [UUID: [NSObjectProtocol]] = [:]
    /// 키 윈도우의 NSWindow. 설정 창 등 등록되지 않은 창이 키 윈도우일 때 ⌘W가 탭을 닫지 않게 구분한다.
    var documentWindow: NSWindow? {
        get { windowRefs[keyWindowID]?.window }
        set { registerWindow(newValue, id: Self.primaryWindowID) }
    }

    var columnVisibility: NavigationSplitViewVisibility {
        didSet { defaults.set(columnVisibility != .detailOnly, forKey: "sidebarVisible") }
    }
    var isOutlineVisible: Bool {
        didSet { defaults.set(isOutlineVisible, forKey: "outlineVisible") }
    }
    var showRenderStats: Bool {
        didSet { defaults.set(showRenderStats, forKey: "showRenderStats") }
    }
    var appearance: AppearanceSetting {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            NSApp.appearance = appearance.nsAppearance
        }
    }
    var showHiddenFiles: Bool {
        didSet {
            defaults.set(showHiddenFiles, forKey: "showHiddenFiles")
            for tree in fileTrees.values { tree.filter = fileFilter }
            quickOpen.filter = fileFilter
        search.filter = fileFilter
            search.filter = fileFilter
            quickOpen.invalidateIndex()
        }
    }
    private(set) var recentFiles: [URL]

    private let sessionStore: SessionStore
    private let defaults: UserDefaults
    private var saveTask: Task<Void, Never>?
    private var indexInvalidateTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.changhyunyoo.cmarks", category: "app")

    /// 테스트는 임시 세션 저장소와 별도 UserDefaults를 넘겨 사용자 상태를 건드리지 않는다.
    init(sessionStore: SessionStore = .standard(appName: "cmarks"), defaults: UserDefaults = .standard) {
        self.sessionStore = sessionStore
        self.defaults = defaults
        scrollMemory = ScrollMemory(defaults: defaults)
        settings = AppSettings(defaults: defaults)
        documents = DocumentService()
        showRenderStats = defaults.bool(forKey: "showRenderStats")
        appearance = AppearanceSetting(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        columnVisibility = (defaults.object(forKey: "sidebarVisible") as? Bool ?? true) ? .all : .detailOnly
        isOutlineVisible = defaults.object(forKey: "outlineVisible") as? Bool ?? true
        showHiddenFiles = defaults.bool(forKey: "showHiddenFiles")
        recentFiles = (defaults.stringArray(forKey: "recentFiles") ?? []).map { URL(fileURLWithPath: $0) }
        let initial = Workspace.single(name: String(localized: "시작"))
        workspaces = [initial]
        activeWorkspaceID = initial.id
        NSApp.appearance = appearance.nsAppearance
        DocumentService.setMarkdownExtensions(settings.extensionSet)
        documents.settings = settings.renderSettings
        appliedRenderSettings = settings.renderSettings
        if settings.restoreSession { restoreSession() }
        quickOpen.filter = fileFilter
        search.filter = fileFilter
        quickOpen.recents = recentFiles
        windowSlots = [WindowSlot(id: Self.primaryWindowID, workspaceID: activeWorkspaceID)]
        syncDisplayed()
        for workspaceID in restoredExtraWindows { openNewWindow(showing: workspaceID) }
        settings.onChange = { [weak self] in self?.applySettings() }
        finderFollower.isMarkdown = { DocumentService.isMarkdown($0) }
        finderFollower.onSelect = { [weak self] url in self?.open(url, preview: true) }
    }

    /// 설정이 바뀌면 렌더 설정·파일 필터를 갱신한다. 본문 폭만 바뀌면 페이지 스타일만 바꾸고, 렌더 결과가 달라지는 설정이면 스크롤을 유지한 채 다시 렌더한다.
    private func applySettings() {
        DocumentService.setMarkdownExtensions(settings.extensionSet)
        let next = settings.renderSettings
        documents.settings = next
        for tree in fileTrees.values { tree.filter = fileFilter }
        quickOpen.filter = fileFilter
        search.filter = fileFilter
        quickOpen.invalidateIndex()

        var previousBody = appliedRenderSettings
        previousBody.contentMaxWidth = nil
        var nextBody = next
        nextBody.contentMaxWidth = nil
        let needsRerender = previousBody != nextBody
        let config = next.webConfig(isLarge: false)
        for viewer in viewers.values {
            viewer.isLiveReloadEnabled = settings.liveReload
            if needsRerender {
                viewer.reloadPreservingScroll()
            } else {
                viewer.applyConfig(config)
            }
        }
        appliedRenderSettings = next
    }

    // MARK: - 읽기

    var fileFilter: FileFilter { settings.fileFilter(showHidden: showHiddenFiles) }

    var workspace: Workspace {
        get { workspaces.first { $0.id == activeWorkspaceID } ?? workspaces[0] }
        set {
            if let index = workspaces.firstIndex(where: { $0.id == newValue.id }) {
                workspaces[index] = newValue
            }
        }
    }

    var activeWorkspaceIndex: Int { workspaces.firstIndex { $0.id == activeWorkspaceID } ?? 0 }
    var focusedPaneID: PaneID { workspace.focusedPaneID }
    var focusedViewer: PaneViewer? { viewers[workspace.focusedPaneID] }
    var focusedTab: LayoutKit.Tab? { workspace.focusedPane?.activeTab }
    var currentDocumentURL: URL? { focusedTab?.document.url }
    var canGoBack: Bool { focusedTab?.canGoBack ?? false }
    var canGoForward: Bool { focusedTab?.canGoForward ?? false }
    var hasDocument: Bool { focusedTab != nil }
    var canReopenClosedTab: Bool { !(workspace.recentlyClosedTabs ?? []).isEmpty }

    func viewer(for pane: PaneID) -> PaneViewer? { viewers[pane] }

    // MARK: 창별 읽기

    func workspace(id: UUID) -> Workspace? { workspaces.first { $0.id == id } }
    func workspaceID(inWindow id: UUID) -> UUID? { windowSlots.first { $0.id == id }?.workspaceID }
    func workspace(inWindow id: UUID) -> Workspace? { workspaceID(inWindow: id).flatMap(workspace(id:)) }
    func windowID(showing workspaceID: UUID) -> UUID? { windowSlots.first { $0.workspaceID == workspaceID }?.id }
    var displayedWorkspaceIDs: Set<UUID> { Set(windowSlots.map(\.workspaceID)) }
    func fileTree(inWindow id: UUID) -> FileTreeModel? { workspaceID(inWindow: id).flatMap { fileTrees[$0] } }
    func focusedViewer(inWindow id: UUID) -> PaneViewer? { workspace(inWindow: id).flatMap { viewers[$0.focusedPaneID] } }
    func currentDocumentURL(inWindow id: UUID) -> URL? { workspace(inWindow: id)?.focusedPane?.activeTab?.document.url }
    func setViewportSize(_ size: CGSize, workspaceID: UUID) { viewportSizes[workspaceID] = size }

    private var viewport: CGRect { viewport(for: activeWorkspaceID) }
    private func viewport(for workspaceID: UUID) -> CGRect {
        CGRect(origin: .zero, size: viewportSizes[workspaceID] ?? CGSize(width: 1200, height: 800))
    }
    private func workspaceID(containingPane pane: PaneID) -> UUID? { workspaces.first { $0.pane(pane) != nil }?.id }
    private func workspaceID(containingSplit id: UUID) -> UUID? { workspaces.first { $0.layout.split(withID: id) != nil }?.id }

    /// 화면 배치. 확대된 패인이 있으면 그 패인만 전체를 차지한다.
    func layoutFrames(in rect: CGRect) -> LayoutFrames { layoutFrames(in: rect, workspaceID: activeWorkspaceID) }

    func layoutFrames(in rect: CGRect, workspaceID: UUID) -> LayoutFrames {
        guard let ws = workspace(id: workspaceID) else { return LayoutFrames(panes: [], dividers: []) }
        if let zoomed = ws.zoomedPaneID, ws.pane(zoomed) != nil {
            return LayoutFrames(panes: [PaneFrame(paneID: zoomed, rect: rect)], dividers: [])
        }
        // 디바이더 7pt는 웹뷰가 덮지 않는 빈 자리다. 겹치면 웹뷰(AppKit)가 마우스 이벤트를 먼저 가져간다.
        return ws.layout.layout(in: rect, dividerThickness: 7)
    }

    // MARK: - 창

    /// ContentView가 나타날 때. 창이 표시할 워크스페이스를 정한다(열기 요청에 담긴 것 → 기본 창이면 활성 → 다른 창에 없는 것 → 새 임시).
    func ensureWindowSlot(_ windowID: UUID) {
        guard !windowSlots.contains(where: { $0.id == windowID }) else { return }
        var target = pendingWindowWorkspaces.removeValue(forKey: windowID)
        if target == nil, windowID == Self.primaryWindowID, !displayedWorkspaceIDs.contains(activeWorkspaceID) { target = activeWorkspaceID }
        if let candidate = target, displayedWorkspaceIDs.contains(candidate) || workspace(id: candidate) == nil { target = nil }
        if target == nil { target = workspaces.first { !displayedWorkspaceIDs.contains($0.id) }?.id }
        let workspaceID = target ?? makeFreshWorkspace()
        windowSlots.append(WindowSlot(id: windowID, workspaceID: workspaceID))
        if windowSlots.count == 1 || keyWindowID == windowID {
            keyWindowID = windowID
            activeWorkspaceID = workspaceID
        }
        syncDisplayed()
        scheduleSave()
    }

    /// WindowAccessor가 NSWindow를 알려 줄 때. 키 윈도우 전환과 닫힘을 관찰한다.
    func registerWindow(_ window: NSWindow?, id: UUID) {
        guard let window else { return }
        if windowRefs[id]?.window === window { return }
        unregisterWindow(id)
        windowRefs[id] = WeakWindow(window)
        let center = NotificationCenter.default
        let key = center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowDidBecomeKey(id) }
        }
        let close = center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowWillClose(id) }
        }
        windowObservers[id] = [key, close]
        ensureWindowSlot(id)
        if window.isKeyWindow { windowDidBecomeKey(id) }
    }

    private func unregisterWindow(_ id: UUID) {
        for token in windowObservers[id] ?? [] { NotificationCenter.default.removeObserver(token) }
        windowObservers[id] = nil
        windowRefs[id] = nil
    }

    func windowDidBecomeKey(_ id: UUID) {
        guard windowSlots.contains(where: { $0.id == id }) else { return }
        if keyWindowID != id {
            quickOpen.dismiss()
            search.dismiss()
            keyWindowID = id   // 같은 값을 다시 쓰면 관찰자가 깨어나므로 바뀔 때만
        }
        guard let target = workspaceID(inWindow: id), target != activeWorkspaceID else { return }
        captureViewerState()
        activeWorkspaceID = target
        workspace.lastActiveAt = .now
        quickOpen.invalidateIndex()
        scheduleSave()
    }

    func windowWillClose(_ id: UUID) {
        unregisterWindow(id)
        guard let index = windowSlots.firstIndex(where: { $0.id == id }) else { return }
        let closed = windowSlots.remove(at: index)
        captureViewerState()
        // 비어 있는 임시 워크스페이스는 창과 함께 사라진다
        if let ws = workspace(id: closed.workspaceID), ws.isEphemeral, ws.isEmpty, workspaces.count > 1 {
            workspaces.removeAll { $0.id == ws.id }
        }
        if keyWindowID == id {
            keyWindowID = windowSlots.first?.id ?? Self.primaryWindowID
            if let ws = windowSlots.first?.workspaceID { activeWorkspaceID = ws }
        }
        syncDisplayed()
        scheduleSave()
    }

    /// 새 창. 워크스페이스를 주면 그것을(다른 창에 없을 때), 없으면 새 임시 워크스페이스를 보여 준다.
    @discardableResult
    func openNewWindow(showing workspaceID: UUID? = nil) -> UUID {
        let windowID = UUID()
        let target = workspaceID.flatMap { workspace(id: $0) != nil && !displayedWorkspaceIDs.contains($0) ? $0 : nil } ?? makeFreshWorkspace()
        pendingWindowWorkspaces[windowID] = target
        windowOpenRequests.append(windowID)
        return windowID
    }

    /// ContentView가 openWindow를 부르기 전에. 이미 처리된 요청이면 false.
    func consumeWindowOpenRequest(_ id: UUID) -> Bool {
        guard let index = windowOpenRequests.firstIndex(of: id) else { return false }
        windowOpenRequests.remove(at: index)
        return true
    }

    /// 사이드바 컨텍스트 메뉴. 이미 어느 창에 있으면 그 창을 앞으로.
    func openInNewWindow(_ workspaceID: UUID) {
        if let existing = windowID(showing: workspaceID) {
            focusWindow(existing)
            return
        }
        openNewWindow(showing: workspaceID)
    }

    private func focusWindow(_ id: UUID) {
        windowRefs[id]?.window?.makeKeyAndOrderFront(nil)
    }

    private func makeFreshWorkspace() -> UUID {
        var fresh = Workspace.single(name: String(localized: "시작"))
        fresh.isEphemeral = true
        workspaces.append(fresh)
        return fresh.id
    }

    /// 표시 중인 워크스페이스의 파일 트리와 뷰어를 맞춘다(숨겨진 것은 정리).
    private func syncDisplayed() {
        let displayed = displayedWorkspaceIDs
        for id in fileTrees.keys where !displayed.contains(id) { fileTrees[id] = nil }
        for id in displayed where fileTrees[id] == nil { rebuildFileTree(for: id) }
        syncViewers()
    }

    // MARK: - 열기

    /// 앱 밖(Finder, CLI, 딥링크, Dock 드롭)에서 온 요청(설계 문서 §4.8).
    /// 폴더는 워크스페이스로 추가. 파일은 포함하는 워크스페이스가 있으면 거기서, 없으면 부모 폴더의 임시 워크스페이스에서 연다.
    func openFromOutside(_ urls: [URL]) {
        for raw in urls {
            let url = raw.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                addWorkspace(root: url, ephemeral: false)
                continue
            }
            if let containing = workspaces.first(where: { $0.contains(url) }) {
                activateWorkspace(containing.id)
                open(url, in: containing.focusedPaneID)
                continue
            } else if workspace.rootURL == nil, workspace.isEmpty {
                // 비어 있는 시작 워크스페이스는 임시 워크스페이스로 바꿔 쓴다.
                let folder = url.deletingLastPathComponent()
                mutate { ws in
                    ws.rootURL = folder
                    ws.name = folder.lastPathComponent
                    ws.isEphemeral = true
                }
                rebuildFileTree(for: activeWorkspaceID)
            } else {
                addWorkspace(root: url.deletingLastPathComponent(), ephemeral: true)
            }
            open(url)
        }
    }

    /// 여러 파일은 모두 탭으로 열고 마지막 것을 활성으로(CHECKPOINTS D-2). 폴더는 README 또는 첫 마크다운 파일.
    func open(_ urls: [URL], in pane: PaneID? = nil) {
        for url in urls { open(url, in: pane) }
    }

    func open(_ url: URL, fragment: String? = nil, in pane: PaneID? = nil, preview: Bool = false) {
        let url = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) else {
            viewers[pane ?? focusedPaneID]?.showFailure(url, message: String(localized: "파일을 찾을 수 없습니다."))
            return
        }
        if isDirectory.boolValue {
            guard let first = Self.firstMarkdownFile(in: url) else {
                viewers[pane ?? focusedPaneID]?.showFailure(url, message: String(localized: "폴더에 Markdown 파일이 없습니다."))
                return
            }
            open(first, in: pane, preview: preview)
            return
        }
        let ref = DocumentRef(url: url, fragment: fragment)
        let zoom = settings.defaultZoom
        mutate(owning: pane) { ws in
            ws.openTab(ref, in: pane, preview: preview, zoom: zoom)
            if let pane { ws.focus(pane) }
        }
        noteRecent(url)
    }

    /// 링크 클릭. 같은 탭이면 히스토리에 쌓고, ⌘클릭은 새 탭, ⌥클릭은 오른쪽 분할.
    func navigate(_ ref: DocumentRef, intent: NavigationIntent, from pane: PaneID) {
        let intent: NavigationIntent = (intent == .sameTab && settings.openLinksInNewTab) ? .newTab : intent
        let zoom = settings.defaultZoom
        mutate(owning: pane) { ws in
            ws.focus(pane)
            switch intent {
            case .sameTab:
                ws.updateActiveTab(in: pane) { tab in
                    if tab.document != ref { tab.navigate(to: ref) }
                }
            case .newTab:
                ws.openTab(ref, in: pane, zoom: zoom)
            case .newSplit(let direction):
                let created = ws.splitFocusedPane(direction: direction, duplicateActiveTab: false)
                ws.openTab(ref, in: created, zoom: zoom)
            }
        }
        noteRecent(ref.url)
    }

    func consume(_ queue: OpenRequestQueue) {
        let urls = queue.drain()
        guard !urls.isEmpty else { return }
        openFromOutside(urls)
    }

    func presentOpenPanel(in pane: PaneID? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType("net.daringfireball.markdown"), .plainText, .folder].compactMap { $0 }
        panel.message = String(localized: "Markdown 파일이나 폴더를 선택하세요")
        guard panel.runModal() == .OK else { return }
        open(panel.urls, in: pane)
    }

    /// ⌘P / ⌘T: 빠른 열기 팔레트.
    func presentQuickOpen() {
        quickOpen.recents = recentFiles
        quickOpen.present(root: workspace.rootURL)
    }

    /// 빠른 열기에서 고른 파일. ⏎ 새 탭, ⌘⏎ 오른쪽 분할, ⌘⇧⏎ 아래 분할.
    var isFollowingFinder: Bool {
        get { finderFollower.isEnabled }
        set { finderFollower.isEnabled = newValue }
    }

    func clearRecentFiles() {
        recentFiles = []
        defaults.removeObject(forKey: "recentFiles")
        quickOpen.recents = []
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    func presentWorkspaceSearch() {
        quickOpen.dismiss()
        search.present(root: workspace.rootURL)
    }

    /// 검색 결과를 열고, 페이지가 준비되면 찾기 바를 그 검색어와 일치 위치로 맞춘다.
    func openSearchSelection(split: SplitDirection? = nil) {
        guard let hit = search.selected else { return }
        let query = search.query.trimmingCharacters(in: .whitespaces)
        search.dismiss()
        if let split {
            navigate(DocumentRef(url: hit.url), intent: .newSplit(split), from: focusedPaneID)
        } else {
            open(hit.url)
        }
        Task { await revealSearchHit(hit, query: query) }
    }

    private func revealSearchHit(_ hit: WorkspaceSearchModel.Hit, query: String) async {
        let target = hit.url.standardizedFileURL
        for _ in 0..<80 {
            if let viewer = focusedViewer, viewer.currentURL == target, viewer.isPageReady {
                viewer.findCaseSensitive = false
                viewer.findQuery = query
                viewer.showFindBar()
                await viewer.performFind()
                await viewer.findGoTo(hit.matchIndex)
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    func openQuickOpenSelection(split: SplitDirection? = nil) {
        guard let result = quickOpen.selected else { return }
        quickOpen.dismiss()
        if let split {
            navigate(DocumentRef(url: result.url), intent: .newSplit(split), from: focusedPaneID)
        } else {
            open(result.url)
        }
    }

    /// ⌘⇧T. 가장 최근에 닫은 탭을 포커스 패인에 되살린다.
    func reopenLastClosedTab() {
        mutate { $0.reopenLastClosedTab() }
    }

    // MARK: - 워크스페이스

    /// 같은 루트의 워크스페이스가 있으면 그것을 활성화한다.
    @discardableResult
    func addWorkspace(root: URL, ephemeral: Bool, activate: Bool = true) -> UUID {
        let root = root.standardizedFileURL
        if let existing = workspaces.first(where: { $0.rootURL?.standardizedFileURL == root }) {
            if !ephemeral, existing.isEphemeral {
                updateWorkspace(existing.id) { $0.isEphemeral = false }
            }
            if activate { activateWorkspace(existing.id) }
            return existing.id
        }
        var created = Workspace.single(name: root.lastPathComponent, rootURL: root)
        created.isEphemeral = ephemeral
        // 시작용 빈 워크스페이스(루트 없음, 탭 없음)는 대체한다.
        if workspaces.count == 1, workspaces[0].rootURL == nil, workspaces[0].isEmpty {
            workspaces = [created]
        } else {
            workspaces.insert(created, at: activeWorkspaceIndex + 1)
        }
        if activate { activateWorkspace(created.id) } else { scheduleSave() }
        return created.id
    }

    func presentNewWorkspacePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "워크스페이스로 열 폴더를 선택하세요")
        panel.prompt = String(localized: "워크스페이스 추가")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addWorkspace(root: url, ephemeral: false)
    }

    /// 키 윈도우에 워크스페이스를 표시한다. 이미 다른 창에 있으면 그 창을 앞으로 가져온다.
    func activateWorkspace(_ id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        if let other = windowID(showing: id), other != keyWindowID {
            focusWindow(other)
            return
        }
        guard id != activeWorkspaceID else { return }
        captureViewerState()
        if let index = windowSlots.firstIndex(where: { $0.id == keyWindowID }) {
            windowSlots[index].workspaceID = id
        } else {
            windowSlots.append(WindowSlot(id: keyWindowID, workspaceID: id))
        }
        activeWorkspaceID = id
        workspace.lastActiveAt = .now
        syncDisplayed()
        quickOpen.invalidateIndex()
        scheduleSave()
    }

    func activateWorkspace(at index: Int) {
        guard workspaces.indices.contains(index) else { return }
        activateWorkspace(workspaces[index].id)
    }

    func activateLastWorkspace() {
        if let last = workspaces.last { activateWorkspace(last.id) }
    }

    func cycleWorkspace(offset: Int) {
        guard workspaces.count > 1 else { return }
        let next = (activeWorkspaceIndex + offset + workspaces.count) % workspaces.count
        activateWorkspace(workspaces[next].id)
    }

    func closeWorkspace(_ id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        captureViewerState()
        workspaces.remove(at: index)
        if workspaces.isEmpty {
            workspaces = [Workspace.single(name: String(localized: "시작"))]
        }
        // 그 워크스페이스를 보여 주던 창은 다른 창에 없는 다음 워크스페이스로(없으면 새 임시)
        for slot in windowSlots.indices where windowSlots[slot].workspaceID == id {
            let elsewhere = Set(windowSlots.enumerated().filter { $0.offset != slot }.map { $0.element.workspaceID })
            let start = min(index, workspaces.count - 1)
            let order = Array(workspaces[start...]) + Array(workspaces[..<start])
            windowSlots[slot].workspaceID = order.first { !elsewhere.contains($0.id) }?.id ?? makeFreshWorkspace()
        }
        if let ws = workspaceID(inWindow: keyWindowID) {
            activeWorkspaceID = ws
        } else if !workspaces.contains(where: { $0.id == activeWorkspaceID }) {
            activeWorkspaceID = workspaces[0].id
        }
        syncDisplayed()
        scheduleSave()
    }

    func closeActiveWorkspace() {
        closeWorkspace(activeWorkspaceID)
    }

    func renameWorkspace(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        updateWorkspace(id) { $0.name = trimmed }
    }

    func beginRenamingActiveWorkspace() {
        renamingWorkspaceID = activeWorkspaceID
    }

    func togglePinWorkspace(_ id: UUID) {
        updateWorkspace(id) { $0.isEphemeral.toggle() }
    }

    func moveWorkspaces(from source: IndexSet, to destination: Int) {
        workspaces.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    private func updateWorkspace(_ id: UUID, _ body: (inout Workspace) -> Void) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        body(&workspaces[index])
        scheduleSave()
    }

    // MARK: - 탭

    func activateTab(_ tabID: LayoutKit.Tab.ID, in pane: PaneID) {
        mutate(owning: pane) { $0.activateTab(tabID, in: pane) }
    }

    func closeTab(_ tabID: LayoutKit.Tab.ID, in pane: PaneID) {
        let viewport = viewport(for: workspaceID(containingPane: pane) ?? activeWorkspaceID)
        mutate(owning: pane) { $0.closeTab(tabID, in: pane, viewport: viewport) }
    }

    /// ⌘W: 설정 창 같은 보조 창이 키 윈도우면 그 창을 닫고, 아니면 활성 탭 → (탭이 없으면) 패인 → (패인이 하나면) 창.
    func closeActiveTabOrPane(keyWindow: NSWindow? = NSApp.keyWindow) {
        if let key = keyWindow, !windowRefs.values.contains(where: { $0.window === key }) {
            key.performClose(nil)
            return
        }
        if let tab = focusedTab {
            closeTab(tab.id, in: focusedPaneID)
        } else if workspace.panes.count > 1 {
            mutate { $0.closePane(focusedPaneID, viewport: viewport) }
        } else {
            (keyWindow ?? NSApp.keyWindow)?.performClose(nil)
        }
    }

    func closeOtherTabs(keeping tabID: LayoutKit.Tab.ID, in pane: PaneID) {
        mutate(owning: pane) { $0.closeOtherTabs(keeping: tabID, in: pane) }
    }

    func cycleTab(offset: Int) {
        mutate { $0.cycleTab(in: focusedPaneID, offset: offset) }
    }

    func activateTab(at index: Int) {
        mutate { $0.activateTab(at: index, in: focusedPaneID) }
    }

    func togglePin(_ tabID: LayoutKit.Tab.ID, in pane: PaneID) {
        mutate(owning: pane) { $0.togglePin(tabID, in: pane) }
    }

    /// 탭 드래그 이동. `before`가 있으면 그 탭 앞에, 없으면 목적지 패인의 끝에. 창 사이 이동은 아직 지원하지 않는다(같은 워크스페이스 안에서만).
    func moveTab(_ tabID: LayoutKit.Tab.ID, from source: PaneID, to destination: PaneID, before: LayoutKit.Tab.ID? = nil) {
        guard let owner = workspaceID(containingPane: destination), workspaceID(containingPane: source) == owner else { return }
        let viewport = viewport(for: owner)
        mutate(owning: destination) { ws in
            let index = before.flatMap { target in ws.pane(destination)?.tabs.firstIndex { $0.id == target } }
            ws.moveTab(tabID, from: source, to: destination, index: index, viewport: viewport)
        }
    }

    // MARK: - 패인

    func split(_ direction: SplitDirection) {
        mutate { $0.splitFocusedPane(direction: direction) }
    }

    func focus(_ pane: PaneID) {
        guard let owner = workspaceID(containingPane: pane), let ws = workspace(id: owner), ws.focusedPaneID != pane else { return }
        mutate(owning: pane) { $0.focus(pane) }
    }

    func focusNeighbor(_ direction: FocusDirection) {
        mutate { $0.focusNeighbor(direction, viewport: viewport) }
    }

    /// ⌃⌥⌘ 화살표. 오른쪽/아래는 키우고 왼쪽/위는 줄인다.
    func resizeFocusedPane(_ direction: FocusDirection) {
        mutate { $0.resizeFocusedPane(direction, by: 40, viewport: viewport) }
    }

    func toggleZoom() {
        mutate { $0.toggleZoom() }
    }

    func equalize(_ splitID: UUID) {
        mutate(in: workspaceID(containingSplit: splitID)) { $0.layout = $0.layout.equalizing(splitID) }
    }

    func resize(_ splitID: UUID, dividerIndex: Int, startFractions: [Double], delta: Double, minimumFraction: Double) {
        mutate(in: workspaceID(containingSplit: splitID)) { ws in
            ws.layout = ws.layout.resizing(splitID, dividerIndex: dividerIndex, from: startFractions, by: delta, minimumFraction: minimumFraction)
        }
    }

    func split(withID id: UUID) -> SplitNode? {
        workspaceID(containingSplit: id).flatMap { workspace(id: $0)?.layout.split(withID: id) }
    }

    // MARK: - 포커스 패인 명령

    func goBack() { mutate { $0.updateActiveTab { $0.goBack() } } }
    func goForward() { mutate { $0.updateActiveTab { $0.goForward() } } }
    func reload() { focusedViewer?.reload() }

    func revealInFinder() {
        guard let url = currentDocumentURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 외부 편집기로 열기. .md 기본 앱이 cmarks 자신이면 다른 앱(없으면 TextEdit)을 고른다.
    func openInDefaultEditor(from pane: PaneID? = nil) {
        guard let url = pane.flatMap({ workspace.pane($0)?.activeTab?.document.url }) ?? currentDocumentURL else { return }
        let me = Bundle.main.bundleURL.standardizedFileURL
        let candidates = NSWorkspace.shared.urlsForApplications(toOpen: url).filter { $0.standardizedFileURL != me }
        let preferred = NSWorkspace.shared.urlForApplication(toOpen: url).flatMap { $0.standardizedFileURL == me ? nil : $0 }
        let target = preferred ?? candidates.first ?? URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([url], withApplicationAt: target, configuration: NSWorkspace.OpenConfiguration())
    }

    func zoom(by delta: CGFloat) {
        setZoom(min(3.0, max(0.5, (focusedViewer?.zoom ?? 1) + delta)))
    }

    func resetZoom() { setZoom(1.0) }

    private func setZoom(_ value: CGFloat) {
        focusedViewer?.zoom = value
        mutate { $0.updateActiveTab { $0.zoom = Double(value) } }
    }

    func cycleAppearance() { appearance = appearance.next }

    func toggleSidebar() {
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    }

    func toggleOutline() { isOutlineVisible.toggle() }

    // MARK: - 세션

    private func restoreSession() {
        do {
            guard let session = try sessionStore.load() else { return }
            let valid = session.workspaces.filter { $0.validate().isEmpty }
            guard !valid.isEmpty else { return }
            workspaces = valid
            activeWorkspaceID = valid.first { $0.id == session.activeWorkspaceID }?.id ?? valid[0].id
            // 기본 창 외의 창들. 활성 워크스페이스와 겹치거나 없는 것은 빼고, 중복도 뺀다.
            var seen: Set<UUID> = [activeWorkspaceID]
            restoredExtraWindows = (session.windows ?? []).map(\.workspaceID).filter { id in
                guard valid.contains(where: { $0.id == id }), !seen.contains(id) else { return false }
                seen.insert(id)
                return true
            }
            logger.notice("session restored: \(valid.count) workspaces, \(valid.reduce(0) { $0 + $1.panes.count }) panes, \(valid.reduce(0) { $0 + $1.panes.reduce(0) { $0 + $1.tabs.count } }) tabs")
        } catch {
            logger.error("session load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// 종료 직전과 디바운스된 변경 뒤에 부른다. 임시 워크스페이스는 저장하지 않는다(CHECKPOINTS D-3).
    func saveNow() {
        captureViewerState()
        let persistent = workspaces.filter { !$0.isEphemeral }
        let active = persistent.contains { $0.id == activeWorkspaceID } ? activeWorkspaceID : persistent.first?.id
        // 창 목록: 키 윈도우(활성)를 앞에, 임시 워크스페이스만 보여 주는 창은 뺀다
        let ordered = windowSlots.sorted { a, _ in a.id == keyWindowID }
        let windows = ordered.compactMap { slot -> SessionWindow? in
            persistent.contains { $0.id == slot.workspaceID } ? SessionWindow(workspaceID: slot.workspaceID) : nil
        }
        do {
            try sessionStore.save(Session(workspaces: persistent, activeWorkspaceID: active, windows: windows.isEmpty ? nil : windows))
        } catch {
            logger.error("session save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 내부

    /// 활성 워크스페이스(키 윈도우) 변경.
    private func mutate(_ body: (inout Workspace) -> Void) {
        mutate(in: activeWorkspaceID, body)
    }

    /// 패인을 가진 워크스페이스 변경(다른 창의 패인에 드롭하는 경우 등).
    private func mutate(owning pane: PaneID?, _ body: (inout Workspace) -> Void) {
        mutate(in: pane.flatMap(workspaceID(containingPane:)) ?? activeWorkspaceID, body)
    }

    private func mutate(in target: UUID?, _ body: (inout Workspace) -> Void) {
        guard let target, let index = workspaces.firstIndex(where: { $0.id == target }) else { return }
        captureViewerState()
        body(&workspaces[index])
        workspaces[index].lastActiveAt = .now
        syncViewers()
        let url = workspaces[index].focusedPane?.activeTab?.document.url
        fileTrees[target]?.highlightedURL = url
        if let url { fileTrees[target]?.reveal(url) }
        scheduleSave()
        cleanupEphemeralIfEmpty(target)
    }

    /// 임시 워크스페이스의 마지막 탭이 닫히면 워크스페이스도 사라진다.
    private func cleanupEphemeralIfEmpty(_ id: UUID) {
        guard settings.cleanupEphemeral, let ws = workspace(id: id), ws.isEphemeral, ws.isEmpty else { return }
        closeWorkspace(id)
    }

    private func captureViewerState() {
        for viewer in viewers.values {
            guard let tabID = viewer.currentTabID, viewer.currentURL != nil,
                  let index = workspaces.firstIndex(where: { $0.pane(viewer.paneID) != nil }) else { continue }
            let scroll = viewer.currentScrollY
            let zoom = Double(viewer.zoom)
            workspaces[index].updateTab(tabID, in: viewer.paneID) { tab in
                tab.scrollY = scroll
                tab.zoom = zoom
            }
        }
    }

    /// 표시 중인 모든 워크스페이스의 패인에 뷰어를 맞춘다. 숨겨진 워크스페이스의 뷰어는 닫는다.
    private func syncViewers() {
        let displayed = workspaces.filter { displayedWorkspaceIDs.contains($0.id) }
        let paneIDs = Set(displayed.flatMap { $0.panes.map(\.id) })
        for id in viewers.keys where !paneIDs.contains(id) {
            viewers[id]?.close()
            viewers[id] = nil
        }
        for ws in displayed {
            for pane in ws.panes {
                let viewer = viewers[pane.id] ?? makeViewer(for: pane.id)
                guard let tab = pane.activeTab else {
                    if viewer.currentTabID != nil || viewer.state != .empty { viewer.close() }
                    continue
                }
                if viewer.currentTabID != tab.id {
                    viewer.currentTabID = tab.id
                    viewer.zoom = CGFloat(tab.zoom)
                    viewer.open(tab.document, scrollY: tab.scrollY)
                } else if viewer.currentURL != tab.document.url.standardizedFileURL {
                    viewer.open(tab.document, scrollY: nil)
                }
            }
        }
    }

    private func makeViewer(for pane: PaneID) -> PaneViewer {
        let viewer = PaneViewer(paneID: pane, documents: documents)
        viewer.isLiveReloadEnabled = settings.liveReload
        viewer.onNavigate = { [weak self] ref, intent in self?.navigate(ref, intent: intent, from: pane) }
        viewer.onFocus = { [weak self] in self?.focus(pane) }
        viewer.onDropURLs = { [weak self] urls in self?.open(urls, in: pane) }
        viewer.onOpenInEditor = { [weak self] in self?.openInDefaultEditor(from: pane) }
        viewer.scrollMemory = scrollMemory
        viewers[pane] = viewer
        return viewer
    }

    private func rebuildFileTree(for workspaceID: UUID) {
        guard let ws = workspace(id: workspaceID), let root = ws.rootURL else {
            fileTrees[workspaceID] = nil
            return
        }
        let tree = FileTreeModel(root: root, filter: fileFilter, expanded: ws.sidebar?.expandedDirectories ?? [""])
        tree.onExpandedChange = { [weak self] expanded in
            self?.updateWorkspace(workspaceID) { $0.sidebar = SidebarState(expandedDirectories: expanded) }
        }
        let url = ws.focusedPane?.activeTab?.document.url
        tree.highlightedURL = url
        if let url { tree.reveal(url) }
        fileTrees[workspaceID] = tree
        if workspaceID == activeWorkspaceID { quickOpen.invalidateIndex() }
    }

    private func noteRecent(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > 50 { recentFiles.removeLast(recentFiles.count - 50) }
        defaults.set(recentFiles.map { $0.path(percentEncoded: false) }, forKey: "recentFiles")
        quickOpen.recents = recentFiles
    }

    static func firstMarkdownFile(in directory: URL) -> URL? {
        let fm = FileManager.default
        for name in ["README.md", "readme.md", "Readme.md", "index.md"] {
            let candidate = directory.appending(path: name)
            if fm.fileExists(atPath: candidate.path(percentEncoded: false)) { return candidate }
        }
        let items = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return items
            .filter { DocumentService.isMarkdown($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .first
    }
}

/// NSWindow 약한 참조(창 등록용).
@MainActor
final class WeakWindow {
    weak var window: NSWindow?
    init(_ window: NSWindow) { self.window = window }
}
