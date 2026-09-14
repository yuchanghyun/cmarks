import LayoutKit
import SwiftUI

/// 창 내용: 사이드바 + 패인 트리. 빠른 열기 팔레트는 문서 영역 위에 뜬다.
struct ContentView: View {
    /// 이 창의 ID. 기본 창은 AppModel.primaryWindowID.
    let windowID: UUID
    @Environment(OpenRequestQueue.self) private var openRequests
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        let isKey = model.keyWindowID == windowID
        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 480)
        } detail: {
            WorkspaceView()
                .overlay {
                    if isKey, model.quickOpen.isPresented {
                        ZStack(alignment: .top) {
                            Color.black.opacity(0.001)
                                .onTapGesture { model.quickOpen.dismiss() }
                            QuickOpenPalette(quickOpen: model.quickOpen)
                                .padding(.top, 48)
                        }
                    } else if isKey, model.search.isPresented {
                        ZStack(alignment: .top) {
                            Color.black.opacity(0.001)
                                .onTapGesture { model.search.dismiss() }
                            WorkspaceSearchPalette(search: model.search)
                                .padding(.top, 48)
                        }
                    }
                }
                .navigationTitle(model.currentDocumentURL(inWindow: windowID)?.lastPathComponent ?? "cmarks")
                .navigationSubtitle(subtitle)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            model.split(.right)
                        } label: {
                            Label("오른쪽으로 분할", systemImage: "rectangle.split.2x1")
                        }
                        .help("오른쪽으로 분할 (⌘D)")
                        Button {
                            model.split(.down)
                        } label: {
                            Label("아래로 분할", systemImage: "rectangle.split.1x2")
                        }
                        .help("아래로 분할 (⌘⇧D)")
                        Toggle(isOn: $model.isOutlineVisible) {
                            Label("아웃라인", systemImage: "list.bullet.indent")
                        }
                        .help("아웃라인 (⌘⇧O)")
                    }
                }
        }
        .frame(minWidth: 760, minHeight: 440)
        .environment(\.cmarksWindowID, windowID)
        .background(WindowAccessor { window in model.registerWindow(window, id: windowID) })
        .sheet(isPresented: Binding(get: { isKey && model.isShortcutHelpPresented }, set: { model.isShortcutHelpPresented = $0 })) { ShortcutHelpView() }
        .onAppear {
            model.ensureWindowSlot(windowID)
            model.consume(openRequests)
        }
        .onChange(of: openRequests.pending) { _, _ in model.consume(openRequests) }
        .onChange(of: model.windowOpenRequests, initial: true) { _, requests in
            // 어느 창의 ContentView든 먼저 본 쪽이 연다
            for id in requests where model.consumeWindowOpenRequest(id) {
                openWindow(id: "document", value: id)
            }
        }
    }

    private var subtitle: String {
        guard let workspace = model.workspace(inWindow: windowID) else { return "" }
        guard let url = workspace.focusedPane?.activeTab?.document.url else { return workspace.name }
        if let relative = workspace.relativePath(of: url) {
            let parent = (relative as NSString).deletingLastPathComponent
            return parent.isEmpty ? workspace.name : "\(workspace.name) › \(parent)"
        }
        return url.deletingLastPathComponent().path(percentEncoded: false).abbreviatingWithTilde
    }
}

/// 이 뷰가 붙은 NSWindow를 알려 준다.
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowObservingView {
        let view = WindowObservingView()
        view.onMove = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowObservingView, context: Context) {
        nsView.onMove = onWindow
        onWindow(nsView.window)
    }
}

final class WindowObservingView: NSView {
    var onMove: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onMove?(window)
    }
}
