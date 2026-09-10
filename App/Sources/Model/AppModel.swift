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
    static let shared = AppModel()

    private(set) var workspaces: [Workspace]
    private(set) var activeWorkspaceID: UUID
    private(set) var viewers: [PaneID: PaneViewer] = [:]
    private(set) var fileTree: FileTreeModel?
    let quickOpen = QuickOpenModel()
    let settings: AppSettings
    let documents: DocumentService
    var isShortcutHelpPresented = false
    private var appliedRenderSettings = RenderSettings.github

    /// WorkspaceView가 보고하는 실제 크기. 이웃 패인 계산에 쓴다.
    var viewportSize = CGSize(width: 1200, height: 800)
    /// 사이드바에서 이름을 편집 중인 워크스페이스.
    var renamingWorkspaceID: UUID?
    /// 문서 창. 설정 창 등 다른 창이 키 윈도우일 때 ⌘W가 탭을 닫지 않게 구분한다.
    weak var documentWindow: NSWindow?

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
            fileTree?.filter = fileFilter
            quickOpen.filter = fileFilter
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
        quickOpen.recents = recentFiles
        rebuildFileTree()
        syncViewers()
        settings.onChange = { [weak self] in self?.applySettings() }
    }

    /// 설정이 바뀌면 렌더 설정·파일 필터를 갱신한다. 본문 폭만 바뀌면 페이지 스타일만 바꾸고, 렌더 결과가 달라지는 설정이면 스크롤을 유지한 채 다시 렌더한다.
    private func applySettings() {
        DocumentService.setMarkdownExtensions(settings.extensionSet)
        let next = settings.renderSettings
        documents.settings = next
        fileTree?.filter = fileFilter
        quickOpen.filter = fileFilter
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

    private var viewport: CGRect { CGRect(origin: .zero, size: viewportSize) }

    /// 화면 배치. 확대된 패인이 있으면 그 패인만 전체를 차지한다.
    func layoutFrames(in rect: CGRect) -> LayoutFrames {
        if let zoomed = workspace.zoomedPaneID, workspace.pane(zoomed) != nil {
            return LayoutFrames(panes: [PaneFrame(paneID: zoomed, rect: rect)], dividers: [])
        }
        // 디바이더 7pt는 웹뷰가 덮지 않는 빈 자리다. 겹치면 웹뷰(AppKit)가 마우스 이벤트를 먼저 가져간다.
        return workspace.layout.layout(in: rect, dividerThickness: 7)
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
            } else if workspace.rootURL == nil, workspace.isEmpty {
                // 비어 있는 시작 워크스페이스는 임시 워크스페이스로 바꿔 쓴다.
                let folder = url.deletingLastPathComponent()
                mutate { ws in
                    ws.rootURL = folder
                    ws.name = folder.lastPathComponent
                    ws.isEphemeral = true
                }
                rebuildFileTree()
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
        mutate { ws in
            ws.openTab(ref, in: pane, preview: preview, zoom: zoom)
            if let pane { ws.focus(pane) }
        }
        noteRecent(url)
    }

    /// 링크 클릭. 같은 탭이면 히스토리에 쌓고, ⌘클릭은 새 탭, ⌥클릭은 오른쪽 분할.
    func navigate(_ ref: DocumentRef, intent: NavigationIntent, from pane: PaneID) {
        let intent: NavigationIntent = (intent == .sameTab && settings.openLinksInNewTab) ? .newTab : intent
        let zoom = settings.defaultZoom
        mutate { ws in
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

    func activateWorkspace(_ id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        guard id != activeWorkspaceID else { return }
        captureViewerState()
        for viewer in viewers.values { viewer.close() }
        viewers = [:]
        activeWorkspaceID = id
        workspace.lastActiveAt = .now
        rebuildFileTree()
        syncViewers()
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
        let wasActive = id == activeWorkspaceID
        if wasActive {
            captureViewerState()
            for viewer in viewers.values { viewer.close() }
            viewers = [:]
        }
        workspaces.remove(at: index)
        if workspaces.isEmpty {
            let fresh = Workspace.single(name: String(localized: "시작"))
            workspaces = [fresh]
        }
        if wasActive {
            activeWorkspaceID = workspaces[min(index, workspaces.count - 1)].id
            rebuildFileTree()
            syncViewers()
        }
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
        mutate { $0.activateTab(tabID, in: pane) }
    }

    func closeTab(_ tabID: LayoutKit.Tab.ID, in pane: PaneID) {
        mutate { $0.closeTab(tabID, in: pane, viewport: viewport) }
    }

    /// ⌘W: 설정 창 같은 보조 창이 키 윈도우면 그 창을 닫고, 아니면 활성 탭 → (탭이 없으면) 패인 → (패인이 하나면) 창.
    func closeActiveTabOrPane(keyWindow: NSWindow? = NSApp.keyWindow) {
        if let key = keyWindow, let document = documentWindow, key != document {
            key.performClose(nil)
            return
        }
        if let tab = focusedTab {
            closeTab(tab.id, in: focusedPaneID)
        } else if workspace.panes.count > 1 {
            mutate { $0.closePane(focusedPaneID, viewport: viewport) }
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    func closeOtherTabs(keeping tabID: LayoutKit.Tab.ID, in pane: PaneID) {
        mutate { $0.closeOtherTabs(keeping: tabID, in: pane) }
    }

    func cycleTab(offset: Int) {
        mutate { $0.cycleTab(in: focusedPaneID, offset: offset) }
    }

    func activateTab(at index: Int) {
        mutate { $0.activateTab(at: index, in: focusedPaneID) }
    }

    func togglePin(_ tabID: LayoutKit.Tab.ID, in pane: PaneID) {
        mutate { $0.togglePin(tabID, in: pane) }
    }

    /// 탭 드래그 이동. `before`가 있으면 그 탭 앞에, 없으면 목적지 패인의 끝에.
    func moveTab(_ tabID: LayoutKit.Tab.ID, from source: PaneID, to destination: PaneID, before: LayoutKit.Tab.ID? = nil) {
        mutate { ws in
            let index = before.flatMap { target in ws.pane(destination)?.tabs.firstIndex { $0.id == target } }
            ws.moveTab(tabID, from: source, to: destination, index: index, viewport: viewport)
        }
    }

    // MARK: - 패인

    func split(_ direction: SplitDirection) {
        mutate { $0.splitFocusedPane(direction: direction) }
    }

    func focus(_ pane: PaneID) {
        guard workspace.focusedPaneID != pane, workspace.pane(pane) != nil else { return }
        mutate { $0.focus(pane) }
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
        mutate { $0.layout = $0.layout.equalizing(splitID) }
    }

    func resize(_ splitID: UUID, dividerIndex: Int, startFractions: [Double], delta: Double, minimumFraction: Double) {
        mutate { ws in
            ws.layout = ws.layout.resizing(splitID, dividerIndex: dividerIndex, from: startFractions, by: delta, minimumFraction: minimumFraction)
        }
    }

    func split(withID id: UUID) -> SplitNode? {
        workspace.layout.split(withID: id)
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
        do {
            try sessionStore.save(Session(workspaces: persistent, activeWorkspaceID: active))
        } catch {
            logger.error("session save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 내부

    private func mutate(_ body: (inout Workspace) -> Void) {
        captureViewerState()
        body(&workspace)
        workspace.lastActiveAt = .now
        syncViewers()
        fileTree?.highlightedURL = currentDocumentURL
        if let url = currentDocumentURL { fileTree?.reveal(url) }
        scheduleSave()
        cleanupEphemeralIfEmpty()
    }

    /// 임시 워크스페이스의 마지막 탭이 닫히면 워크스페이스도 사라진다.
    private func cleanupEphemeralIfEmpty() {
        guard settings.cleanupEphemeral, workspace.isEphemeral, workspace.isEmpty else { return }
        closeWorkspace(activeWorkspaceID)
    }

    private func captureViewerState() {
        for viewer in viewers.values {
            guard let tabID = viewer.currentTabID, viewer.currentURL != nil else { continue }
            let scroll = viewer.currentScrollY
            let zoom = Double(viewer.zoom)
            workspace.updateTab(tabID, in: viewer.paneID) { tab in
                tab.scrollY = scroll
                tab.zoom = zoom
            }
        }
    }

    private func syncViewers() {
        let paneIDs = Set(workspace.panes.map(\.id))
        for id in viewers.keys where !paneIDs.contains(id) {
            viewers[id]?.close()
            viewers[id] = nil
        }
        for pane in workspace.panes {
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

    private func makeViewer(for pane: PaneID) -> PaneViewer {
        let viewer = PaneViewer(paneID: pane, documents: documents)
        viewer.isLiveReloadEnabled = settings.liveReload
        viewer.onNavigate = { [weak self] ref, intent in self?.navigate(ref, intent: intent, from: pane) }
        viewer.onFocus = { [weak self] in self?.focus(pane) }
        viewer.onDropURLs = { [weak self] urls in self?.open(urls, in: pane) }
        viewer.onOpenInEditor = { [weak self] in self?.openInDefaultEditor(from: pane) }
        viewers[pane] = viewer
        return viewer
    }

    private func rebuildFileTree() {
        guard let root = workspace.rootURL else {
            fileTree = nil
            return
        }
        let tree = FileTreeModel(root: root, filter: fileFilter, expanded: workspace.sidebar?.expandedDirectories ?? [""])
        let workspaceID = activeWorkspaceID
        tree.onExpandedChange = { [weak self] expanded in
            self?.updateWorkspace(workspaceID) { $0.sidebar = SidebarState(expandedDirectories: expanded) }
        }
        tree.highlightedURL = currentDocumentURL
        if let url = currentDocumentURL { tree.reveal(url) }
        fileTree = tree
        quickOpen.invalidateIndex()
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
