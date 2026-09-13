import LayoutKit
import SwiftUI

/// 창 내용: 사이드바 + 패인 트리. 빠른 열기 팔레트는 문서 영역 위에 뜬다.
struct ContentView: View {
    @Environment(OpenRequestQueue.self) private var openRequests
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 480)
        } detail: {
            WorkspaceView()
                .overlay {
                    if model.quickOpen.isPresented {
                        ZStack(alignment: .top) {
                            Color.black.opacity(0.001)
                                .onTapGesture { model.quickOpen.dismiss() }
                            QuickOpenPalette(quickOpen: model.quickOpen)
                                .padding(.top, 48)
                        }
                    } else if model.search.isPresented {
                        ZStack(alignment: .top) {
                            Color.black.opacity(0.001)
                                .onTapGesture { model.search.dismiss() }
                            WorkspaceSearchPalette(search: model.search)
                                .padding(.top, 48)
                        }
                    }
                }
                .navigationTitle(model.currentDocumentURL?.lastPathComponent ?? "cmarks")
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
        .background(WindowAccessor { window in model.documentWindow = window })
        .sheet(isPresented: $model.isShortcutHelpPresented) { ShortcutHelpView() }
        .onAppear { model.consume(openRequests) }
        .onChange(of: openRequests.pending) { _, _ in model.consume(openRequests) }
    }

    private var subtitle: String {
        guard let url = model.currentDocumentURL else { return model.workspace.name }
        if let relative = model.workspace.relativePath(of: url) {
            let parent = (relative as NSString).deletingLastPathComponent
            return parent.isEmpty ? model.workspace.name : "\(model.workspace.name) › \(parent)"
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
