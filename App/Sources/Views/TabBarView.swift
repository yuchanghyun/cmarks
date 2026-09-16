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
    @Environment(\.cmarksWindowID) private var windowID
    let isPaneFocused: Bool
    @Environment(AppModel.self) private var model
    @State private var endTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            // 스크롤 영역이 + 버튼 왼쪽까지 전부 차지한다. (빈 자리를 HStack의 형제로 두면 둘이 폭을 절반씩 나눠
            // 탭 목록이 절반에서 스크롤되는 문제가 있었다.) 내용 폭을 뷰포트 폭 이상으로 두어, 탭이 적을 때는 빈 자리가
            // 남은 폭을 채우고 탭이 넘칠 때는 최소 폭만 남긴다.
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(pane.tabs) { tab in
                            TabItemView(tab: tab, isActive: tab.id == pane.activeTabID, isPaneFocused: isPaneFocused, paneID: pane.id)
                                // 탭은 이름 폭(90~220pt)을 그대로 갖는다. 고정 크기가 아니면 HStack이 남는 폭을 탭에도 나눠 주거나
                                // (탭이 늘어남) 빈 자리에 몰아주며 탭을 최소 폭으로 누른다(이름이 "AP….md"로 잘림).
                                .fixedSize(horizontal: true, vertical: false)
                                .draggable(TabDragItem(tabID: tab.id, paneID: pane.id)) {
                                    Text(tab.document.url.lastPathComponent)
                                        .padding(6)
                                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                                }
                        }
                        DropIndicator(visible: endTargeted)
                        // 탭 뒤 빈 자리: 클릭하면 패인 포커스, 탭을 놓으면 맨 끝으로 간다. 탭이 적을 때 남은 폭을 모두 차지한다.
                        Color.clear
                            .frame(minWidth: 24, maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { model.focus(pane.id) }
                            .dropDestination(for: TabDragItem.self) { items, _ in
                                guard let item = items.first else { return false }
                                model.moveTab(item.tabID, from: item.paneID, to: pane.id, before: nil)
                                return true
                            } isTargeted: { endTargeted = $0 }
                    }
                    .frame(minWidth: geometry.size.width, alignment: .leading)
                }
            }
            Button {
                model.focus(pane.id)
                model.presentQuickOpen(inWindow: windowID)
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
            if tab.isPinned {
                Button("고정 해제") { model.togglePin(tab.id, in: paneID) }
            } else {
                Button("탭 고정") { model.togglePin(tab.id, in: paneID) }
            }
            Divider()
            Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([tab.document.url]) }
            Button("경로 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tab.document.url.path(percentEncoded: false), forType: .string)
            }
        }
    }
}
