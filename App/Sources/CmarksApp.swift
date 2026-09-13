import LayoutKit
import SwiftUI

@main
struct CmarksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 창 하나. 패인의 웹뷰는 한 곳에만 붙을 수 있으므로 WindowGroup 대신 단일 Window를 쓴다(다중 창은 백로그).
        Window("cmarks", id: "main") {
            ContentView()
                .environment(OpenRequestQueue.shared)
                .environment(AppModel.shared)
        }
        .defaultSize(width: 1100, height: 760)
        .commands { AppCommands() }

        Settings {
            SettingsView()
        }
    }
}

/// 메뉴. 단축키는 설정 ▸ 단축키의 값을 따른다(기본값은 설계 문서 §5.2, cmux 호환).
struct AppCommands: Commands {
    @Bindable private var model = AppModel.shared
    private var updater = UpdaterModel.shared

    private var settings: AppSettings { model.settings }
    private func key(_ action: ShortcutAction) -> KeyboardShortcut? { settings.keyboardShortcut(for: action) }

    var body: some Commands {
        // CommandsBuilder는 최상위 항목이 10개까지라 앞의 두 그룹을 Group으로 묶는다.
        Group {
            CommandGroup(after: .appInfo) {
                Button("업데이트 확인…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .newItem) {
                Button("새 워크스페이스…") { model.presentNewWorkspacePanel() }
                    .keyboardShortcut(key(.newWorkspace))
                Button("새 탭…") { model.presentQuickOpen() }
                    .keyboardShortcut("t")
                Button("빠른 열기…") { model.presentQuickOpen() }
                    .keyboardShortcut(key(.quickOpen))
                Button("열기…") { model.presentOpenPanel() }
                    .keyboardShortcut(key(.openFile))
                Button("닫은 탭 다시 열기") { model.reopenLastClosedTab() }
                    .keyboardShortcut(key(.reopenClosedTab))
                    .disabled(!model.canReopenClosedTab)
            }
        }
        CommandGroup(replacing: .saveItem) {
            Button("탭 닫기") { model.closeActiveTabOrPane() }
                .keyboardShortcut(key(.closeTab))
            Button("창 닫기") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .option])
        }
        CommandGroup(after: .saveItem) {
            Divider()
            Button("Finder에서 보기") { model.revealInFinder() }
                .keyboardShortcut(key(.revealInFinder))
                .disabled(!model.hasDocument)
            Button("외부 편집기로 열기") { model.openInDefaultEditor() }
                .keyboardShortcut(key(.openInEditor))
                .disabled(!model.hasDocument)
        }
        CommandGroup(replacing: .printItem) {
            Button("인쇄…") { model.focusedViewer?.printDocument() }
                .keyboardShortcut(key(.print))
                .disabled(!model.hasDocument)
            Button("PDF로 내보내기…") { model.focusedViewer?.exportPDF() }
                .keyboardShortcut(key(.exportPDF))
                .disabled(!model.hasDocument)
        }
        CommandGroup(after: .textEditing) {
            Divider()
            Button("찾기…") { model.focusedViewer?.showFindBar() }
                .keyboardShortcut(key(.find))
                .disabled(!model.hasDocument)
            Button("다음 찾기") { Task { await model.focusedViewer?.findNext() } }
                .keyboardShortcut(key(.findNext))
                .disabled(!model.hasDocument)
            Button("이전 찾기") { Task { await model.focusedViewer?.findPrevious() } }
                .keyboardShortcut(key(.findPrevious))
                .disabled(!model.hasDocument)
        }
        CommandGroup(after: .sidebar) {
            if model.columnVisibility == .detailOnly {
                Button("사이드바 보기") { model.toggleSidebar() }
                    .keyboardShortcut(key(.toggleSidebar))
            } else {
                Button("사이드바 숨기기") { model.toggleSidebar() }
                    .keyboardShortcut(key(.toggleSidebar))
            }
            Toggle("아웃라인", isOn: $model.isOutlineVisible)
                .keyboardShortcut(key(.toggleOutline))
            Toggle("숨김 파일 표시", isOn: $model.showHiddenFiles)
        }
        CommandGroup(after: .toolbar) {
            Button("뒤로") { model.goBack() }
                .keyboardShortcut(key(.back))
                .disabled(!model.canGoBack)
            Button("앞으로") { model.goForward() }
                .keyboardShortcut(key(.forward))
                .disabled(!model.canGoForward)
            Button("다시 렌더링") { model.reload() }
                .keyboardShortcut(key(.reload))
                .disabled(!model.hasDocument)
            Divider()
            Button("확대") { model.zoom(by: 0.1) }.keyboardShortcut(key(.zoomIn))
            Button("축소") { model.zoom(by: -0.1) }.keyboardShortcut(key(.zoomOut))
            Button("실제 크기") { model.resetZoom() }.keyboardShortcut(key(.zoomReset))
            Divider()
            Picker("테마", selection: $model.appearance) {
                ForEach(AppearanceSetting.allCases) { setting in
                    Text(setting.title).tag(setting)
                }
            }
            Button("테마 순환") { model.cycleAppearance() }
                .keyboardShortcut(key(.cycleAppearance))
            Toggle("렌더 통계 표시", isOn: $model.showRenderStats)
        }
        CommandGroup(replacing: .help) {
            Button("단축키 보기") { model.isShortcutHelpPresented = true }
                .keyboardShortcut(key(.shortcutHelp))
            Divider()
            Button("문제 신고…") { ProblemReporter.report(settings: model.settings) }
            Button("GitHub에서 cmarks 보기") { NSWorkspace.shared.open(URL(string: "https://github.com/yuchanghyun/cmarks")!) }
        }
        CommandMenu("워크스페이스") {
            Button("워크스페이스 닫기") { model.closeActiveWorkspace() }
                .keyboardShortcut(key(.closeWorkspace))
            Button("이름 변경…") { model.beginRenamingActiveWorkspace() }
                .keyboardShortcut(key(.renameWorkspace))
            if model.workspace.isEphemeral {
                Button("워크스페이스 고정") { model.togglePinWorkspace(model.activeWorkspaceID) }
                    .disabled(model.workspace.rootURL == nil)
            } else {
                Button("임시 워크스페이스로 전환") { model.togglePinWorkspace(model.activeWorkspaceID) }
                    .disabled(model.workspace.rootURL == nil)
            }
            Divider()
            Button("다음 워크스페이스") { model.cycleWorkspace(offset: 1) }
                .keyboardShortcut(key(.nextWorkspace))
            Button("이전 워크스페이스") { model.cycleWorkspace(offset: -1) }
                .keyboardShortcut(key(.previousWorkspace))
            Divider()
            ForEach(Array(model.workspaces.prefix(8).enumerated()), id: \.element.id) { index, workspace in
                Button(workspace.name) { model.activateWorkspace(workspace.id) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Button("마지막 워크스페이스") { model.activateLastWorkspace() }
                .keyboardShortcut(key(.lastWorkspace))
        }
        CommandMenu("레이아웃") {
            Button("오른쪽으로 분할") { model.split(.right) }
                .keyboardShortcut(key(.splitRight))
            Button("아래로 분할") { model.split(.down) }
                .keyboardShortcut(key(.splitDown))
            // 빠른 열기 팔레트가 떠 있을 때는 ⌘⇧↩(아래 분할로 열기)를 팔레트가 받아야 한다.
            Button("패인 확대 토글") { model.toggleZoom() }
                .keyboardShortcut(key(.toggleZoomPane))
                .disabled(model.workspace.panes.count < 2 || model.quickOpen.isPresented)
            Divider()
            Button("왼쪽 패인") { model.focusNeighbor(.left) }
                .keyboardShortcut(key(.focusLeft))
            Button("오른쪽 패인") { model.focusNeighbor(.right) }
                .keyboardShortcut(key(.focusRight))
            Button("위 패인") { model.focusNeighbor(.up) }
                .keyboardShortcut(key(.focusUp))
            Button("아래 패인") { model.focusNeighbor(.down) }
                .keyboardShortcut(key(.focusDown))
            Divider()
            Button("패인 넓히기") { model.resizeFocusedPane(.right) }
                .keyboardShortcut(key(.resizeRight))
            Button("패인 좁히기") { model.resizeFocusedPane(.left) }
                .keyboardShortcut(key(.resizeLeft))
            Button("패인 높이기") { model.resizeFocusedPane(.down) }
                .keyboardShortcut(key(.resizeDown))
            Button("패인 낮추기") { model.resizeFocusedPane(.up) }
                .keyboardShortcut(key(.resizeUp))
            Divider()
            Button("다음 탭") { model.cycleTab(offset: 1) }
                .keyboardShortcut(key(.nextTab))
            Button("이전 탭") { model.cycleTab(offset: -1) }
                .keyboardShortcut(key(.previousTab))
            Button("다음 탭 (⌃Tab)") { model.cycleTab(offset: 1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("이전 탭 (⌃⇧Tab)") { model.cycleTab(offset: -1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Divider()
            ForEach(1...8, id: \.self) { index in
                Button("탭 \(index)") { model.activateTab(at: index - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .control)
            }
        }
    }
}
