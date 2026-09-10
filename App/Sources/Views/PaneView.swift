import LayoutKit
import SwiftUI

/// 패인 하나: 탭 줄 + 문서(웹뷰) + 오버레이(파일 사라짐 배너, 찾기 바, 렌더 통계).
struct PaneView: View {
    let paneID: PaneID
    @Environment(AppModel.self) private var model

    var body: some View {
        let pane = model.workspace.pane(paneID)
        let viewer = model.viewer(for: paneID)
        let isFocused = model.workspace.focusedPaneID == paneID
        let showsFocusRing = isFocused && model.workspace.panes.count > 1

        VStack(spacing: 0) {
            if let pane {
                TabBarView(pane: pane, isPaneFocused: isFocused)
                Divider()
            }
            ZStack {
                if let viewer {
                    PaneContent(viewer: viewer, paneID: paneID)
                } else {
                    EmptyPaneView(openAction: { model.presentOpenPanel(in: paneID) })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if showsFocusRing {
                Rectangle()
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .clipped()
    }
}

/// 뷰어 상태에 따른 본문. 빈 상태·실패 상태에서는 웹뷰를 트리에서 빼서 드롭이 SwiftUI로 온다.
private struct PaneContent: View {
    @Bindable var viewer: PaneViewer
    let paneID: PaneID
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch viewer.state {
            case .loading, .loaded:
                WebViewHost(webView: viewer.webView)
            case .empty:
                EmptyPaneView(openAction: { model.presentOpenPanel(in: paneID) })
            case .failed(let url, let message):
                ContentUnavailableView {
                    Label("열 수 없습니다", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(url.path(percentEncoded: false)).font(.caption.monospaced())
                    Text(message)
                } actions: {
                    Button("다시 시도") { viewer.reload() }
                    Button("탭 닫기") { model.closeActiveTabOrPane() }
                }
            }
        }
        .overlay(alignment: .top) {
            if viewer.isFileMissing, let url = viewer.currentURL {
                MissingFileBanner(url: url, closeAction: { model.closeActiveTabOrPane() })
            }
        }
        .overlay(alignment: .topTrailing) {
            if viewer.isFindBarVisible, viewer.state.showsWebView {
                FindBar(viewer: viewer)
                    .padding(12)
                    .padding(.top, viewer.isFileMissing ? 36 : 0)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if model.showRenderStats, let stats = viewer.stats {
                RenderStatsBadge(stats: stats).padding(10)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.focus(paneID) }
        .dropDestination(for: URL.self) { urls, _ in
            // 빈 상태·실패 상태의 드롭. 문서가 떠 있을 때는 DocumentWebView가 받는다.
            let accepted = DocumentWebView.accepted(urls)
            guard !accepted.isEmpty else { return false }
            model.open(accepted, in: paneID)
            return true
        }
    }
}

private struct EmptyPaneView: View {
    let openAction: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("cmarks", systemImage: "doc.richtext")
        } description: {
            Text("Markdown 파일이나 폴더를 열거나 여기로 끌어다 놓으세요.")
        } actions: {
            Button("열기… (⌘O)", action: openAction)
        }
    }
}

/// 감시 중인 파일이 삭제되거나 이동됐을 때. 파일이 돌아오면 배너는 자동으로 사라진다.
private struct MissingFileBanner: View {
    let url: URL
    let closeAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("파일이 삭제되거나 이동되었습니다. 같은 경로에 다시 나타나면 자동으로 갱신됩니다.")
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button("폴더 보기") {
                NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
            }
            Button("탭 닫기", action: closeAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct RenderStatsBadge: View {
    let stats: RenderStats

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("render \(stats.swiftRenderMS, specifier: "%.1f") ms\(stats.fromCache ? " (cache)" : "")")
            if let ready = stats.jsReadyMS {
                Text("js ready \(ready, specifier: "%.1f") ms\(stats.changedBlocks.map { " · \($0) blocks" } ?? "")")
            }
            if let enhanced = stats.jsEnhancedMS { Text("js enhanced \(enhanced, specifier: "%.1f") ms") }
            Text("\(stats.bytes) B · \(stats.encoding) · code \(stats.codeBlocks) · img \(stats.images) · h \(stats.headings)")
        }
        .font(.caption2.monospaced())
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
