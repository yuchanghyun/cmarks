import LayoutKit
import SwiftUI

/// 포커스 패인 문서의 헤딩 목록. 클릭하면 그 헤딩으로 스크롤하고, 스크롤 위치의 헤딩이 강조된다.
struct OutlineView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.cmarksWindowID) private var windowID

    var body: some View {
        let viewer = model.focusedViewer(inWindow: windowID)
        let items = viewer?.outline ?? []
        VStack(spacing: 0) {
            HStack {
                Text("아웃라인")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.toggleOutline()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("아웃라인 닫기 (⌘⇧O)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            if items.isEmpty {
                Group {
                    if viewer?.currentURL == nil {
                        Text("열린 문서가 없습니다.")
                    } else {
                        Text("헤딩이 없습니다.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(items) { item in
                        Text(item.text)
                            .font(item.level <= 2 ? .callout.weight(.medium) : .callout)
                            .lineLimit(1)
                            .padding(.leading, CGFloat(max(0, item.level - 1)) * 12)
                            .foregroundStyle(viewer?.activeHeadingID == item.id ? Color.accentColor : .primary)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                            .contentShape(Rectangle())
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(viewer?.activeHeadingID == item.id ? Color.accentColor.opacity(0.12) : nil)
                            .onTapGesture { let id = item.id; Task { @MainActor in viewer?.scrollToHeading(id) } }
                            .id(item.id)
                    }
                    .listStyle(.sidebar)
                    .onChange(of: viewer?.activeHeadingID) { _, id in
                        if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
        }
    }
}
