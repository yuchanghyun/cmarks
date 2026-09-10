import LayoutKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// 탭 드래그 전용. Info.plist의 UTExportedTypeDeclarations와 짝.
    nonisolated static let cmarksTab = UTType(exportedAs: "com.changhyunyoo.cmarks.tab")
}

struct TabDragItem: Codable, Transferable {
    let tabID: UUID
    let paneID: PaneID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .cmarksTab)
    }
}

/// 패인 위의 탭 줄. 클릭 활성화, 드래그로 순서 변경과 다른 패인 이동(놓일 자리에 세로 표시), 컨텍스트 메뉴.
struct TabBarView: View {
    let pane: Pane
    let isPaneFocused: Bool
    @Environment(AppModel.self) private var model
    @State private var endTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(pane.tabs) { tab in
                        TabItemView(tab: tab, isActive: tab.id == pane.activeTabID, isPaneFocused: isPaneFocused, paneID: pane.id)
                            .draggable(TabDragItem(tabID: tab.id, paneID: pane.id)) {
                                Text(tab.document.url.lastPathComponent)
                                    .padding(6)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                            }
                    }
                    DropIndicator(visible: endTargeted)
                }
            }
            // 탭 뒤 빈 자리에 놓으면 맨 끝으로 간다.
            Color.clear
                .frame(minWidth: 24, maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { model.focus(pane.id) }
                .dropDestination(for: TabDragItem.self) { items, _ in
                    guard let item = items.first else { return false }
                    model.moveTab(item.tabID, from: item.paneID, to: pane.id, before: nil)
                    return true
                } isTargeted: { endTargeted = $0 }
            Button {
                model.focus(pane.id)
                model.presentQuickOpen()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("새 탭 (⌘T)")
            .accessibilityLabel("새 탭")
            .padding(.horizontal, 8)
        }
        .frame(height: 30)
        .background(.bar)
    }
}

/// 드롭 위치를 알리는 2pt 세로 막대.
private struct DropIndicator: View {
    let visible: Bool

    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2, height: 22)
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.1), value: visible)
    }
}

private struct TabItemView: View {
    let tab: LayoutKit.Tab
    let isActive: Bool
    let isPaneFocused: Bool
    let paneID: PaneID
    @Environment(AppModel.self) private var model
    @State private var hovering = false
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 4) {
            if tab.isPinned {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
            }
            Text(tab.document.url.lastPathComponent)
                .font(.callout)
                .italic(tab.isPreview)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isActive ? .primary : .secondary)
            Button {
                model.closeTab(tab.id, in: paneID)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .opacity(hovering || isActive ? 1 : 0)
            .help("탭 닫기 (⌘W)")
            .accessibilityLabel("탭 닫기")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 30)
        .frame(minWidth: 90, maxWidth: 220)
        .background(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(isPaneFocused ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
        }
        .overlay(alignment: .leading) {
            // 이 탭 앞에 놓인다는 표시
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: 22)
                .opacity(isDropTarget ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.activateTab(tab.id, in: paneID) }
        .dropDestination(for: TabDragItem.self) { items, _ in
            guard let item = items.first else { return false }
            model.moveTab(item.tabID, from: item.paneID, to: paneID, before: tab.id)
            return true
        } isTargeted: { isDropTarget = $0 }
        .help(tab.document.url.path(percentEncoded: false))
        .contextMenu {
            Button("탭 닫기") { model.closeTab(tab.id, in: paneID) }
            Button("다른 탭 모두 닫기") { model.closeOtherTabs(keeping: tab.id, in: paneID) }
            Divider()
            Button(tab.isPinned ? "고정 해제" : "탭 고정") { model.togglePin(tab.id, in: paneID) }
            Divider()
            Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([tab.document.url]) }
            Button("경로 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tab.document.url.path(percentEncoded: false), forType: .string)
            }
        }
    }
}
