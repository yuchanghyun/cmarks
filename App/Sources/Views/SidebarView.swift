import FileKit
import LayoutKit
import SwiftUI

/// 사이드바: 워크스페이스 목록 + 활성 워크스페이스의 파일 트리, 아래에 아웃라인.
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VSplitView {
            List {
                Section("워크스페이스") {
                    ForEach(model.workspaces) { workspace in
                        WorkspaceRow(workspace: workspace, isActive: workspace.id == model.activeWorkspaceID)
                    }
                    .onMove { source, destination in model.moveWorkspaces(from: source, to: destination) }
                }
                Section {
                    if let tree = model.fileTree {
                        FileTreeRows(tree: tree, relative: "", depth: 0)
                    } else {
                        Text("⌘N으로 폴더를 열어 워크스페이스를 만드세요.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text(model.workspace.rootURL?.lastPathComponent ?? "파일")
                        Spacer()
                        if let root = model.workspace.rootURL {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([root])
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .help("Finder에서 보기")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minHeight: 160)

            if model.isOutlineVisible {
                OutlineView()
                    .frame(minHeight: 100, idealHeight: 220)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            // 폴더는 워크스페이스로, 파일은 활성 패인의 탭으로
            var handled = false
            for url in urls {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) else { continue }
                if isDirectory.boolValue {
                    model.addWorkspace(root: url, ephemeral: false)
                    handled = true
                } else if !DocumentWebView.accepted([url]).isEmpty {
                    model.open(url)
                    handled = true
                }
            }
            return handled
        }
    }
}

private struct WorkspaceRow: View {
    let workspace: Workspace
    let isActive: Bool
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: workspace.rootURL == nil ? "square.dashed" : "folder.fill")
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
            if model.renamingWorkspaceID == workspace.id {
                TextField("이름", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($editing)
                    .onSubmit { commitRename() }
                    .onExitCommand { model.renamingWorkspaceID = nil }
                    .onAppear {
                        draft = workspace.name
                        editing = true
                    }
                    .onChange(of: editing) { _, focused in if !focused { commitRename() } }
            } else {
                Text(workspace.name)
                    .fontWeight(isActive ? .semibold : .regular)
                    .italic(workspace.isEphemeral)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if workspace.isEphemeral {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("임시 워크스페이스. 마지막 탭을 닫거나 종료하면 사라집니다.")
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets())
        .listRowBackground(isActive ? Color.accentColor.opacity(0.12) : nil)
        .onTapGesture { let id = workspace.id; Task { @MainActor in model.activateWorkspace(id) } }
        .help(workspace.rootURL?.path(percentEncoded: false).abbreviatingWithTilde ?? "루트 폴더 없음")
        .contextMenu {
            Button("이름 변경") { model.renamingWorkspaceID = workspace.id }
            Button(workspace.isEphemeral ? "고정" : "임시로 전환") { model.togglePinWorkspace(workspace.id) }
            if let root = workspace.rootURL {
                Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([root]) }
            }
            Divider()
            Button("워크스페이스 닫기") { model.closeWorkspace(workspace.id) }
        }
    }

    private func commitRename() {
        guard model.renamingWorkspaceID == workspace.id else { return }
        model.renameWorkspace(workspace.id, to: draft)
        model.renamingWorkspaceID = nil
    }
}

/// 디렉터리 한 단계. 폴더는 DisclosureGroup으로 재귀한다.
struct FileTreeRows: View {
    @Bindable var tree: FileTreeModel
    let relative: String
    let depth: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        if let nodes = tree.nodes(in: relative) {
            if nodes.isEmpty, depth == 0 {
                Text("마크다운 파일이 없습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(nodes) { node in
                if node.isDirectory {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { tree.isExpanded(node) },
                            set: { value in Task { @MainActor in tree.setExpanded(node, value) } }
                        )
                    ) {
                        FileTreeRows(tree: tree, relative: tree.relativePath(of: node), depth: depth + 1)
                    } label: {
                        Label {
                            Text(node.name).lineLimit(1)
                        } icon: {
                            Image(systemName: node.isSymlink ? "folder.badge.questionmark" : "folder")
                        }
                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let expanded = tree.isExpanded(node)
                            Task { @MainActor in
                                tree.selectedPath = tree.relativePath(of: node)
                                tree.setExpanded(node, !expanded)
                            }
                        }
                        .contextMenu {
                            Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                            Button("이 폴더를 워크스페이스로") { model.addWorkspace(root: node.url, ephemeral: false) }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 0))
                    .listRowBackground(tree.selectedPath == tree.relativePath(of: node) ? Color.accentColor.opacity(0.12) : nil)
                } else {
                    FileRow(node: node, isActive: tree.highlightedURL == node.url.standardizedFileURL, isSelected: tree.selectedPath == tree.relativePath(of: node)) {
                        tree.selectedPath = tree.relativePath(of: node)
                    }
                }
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }
}

private struct FileRow: View {
    let node: FileTreeNode
    let isActive: Bool
    let isSelected: Bool
    let select: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        Label {
            Text(node.name)
                .lineLimit(1)
                .fontWeight(isActive ? .semibold : .regular)
        } icon: {
            Image(systemName: "doc.text")
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets())
        .listRowBackground(isActive || isSelected ? Color.accentColor.opacity(isActive ? 0.16 : 0.10) : nil)
        .onTapGesture(count: 2) { let url = node.url; Task { @MainActor in model.open(url, preview: false) } }
        .onTapGesture {
            let url = node.url
            Task { @MainActor in
                select()
                model.open(url, preview: model.settings.singleClickPreview)
            }
        }
        .help(node.url.path(percentEncoded: false).abbreviatingWithTilde)
        .contextMenu {
            Button("새 탭으로 열기") { model.navigate(DocumentRef(url: node.url), intent: .newTab, from: model.focusedPaneID) }
            Button("오른쪽 분할로 열기") { model.navigate(DocumentRef(url: node.url), intent: .newSplit(.right), from: model.focusedPaneID) }
            Button("아래 분할로 열기") { model.navigate(DocumentRef(url: node.url), intent: .newSplit(.down), from: model.focusedPaneID) }
            Divider()
            Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
            Button("경로 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.url.path(percentEncoded: false), forType: .string)
            }
        }
    }
}
