import LayoutKit
import SwiftUI

/// ⌘P 빠른 열기. 워크스페이스의 마크다운 파일을 fuzzy로 찾아 연다. ↑↓ 이동, ⏎ 열기, ⌘⏎ 오른쪽 분할, Esc 닫기.
struct QuickOpenPalette: View {
    @Environment(AppModel.self) private var model
    @Bindable var quickOpen: QuickOpenModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(model.workspace.rootURL == nil ? LocalizedStringKey("최근 파일") : LocalizedStringKey("파일 이름이나 경로 일부"), text: $quickOpen.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { model.openQuickOpenSelection() }
                    .onExitCommand { quickOpen.dismiss() }
                    .onKeyPress(.upArrow) { quickOpen.moveSelection(-1); return .handled }
                    .onKeyPress(.downArrow) { quickOpen.moveSelection(1); return .handled }
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        model.openQuickOpenSelection(split: press.modifiers.contains(.shift) ? .down : .right)
                        return .handled
                    }
                if quickOpen.isIndexing {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            if quickOpen.results.isEmpty {
                Group {
                    if quickOpen.query.isEmpty {
                        Text("최근에 연 파일이 없습니다.")
                    } else if quickOpen.isIndexing {
                        Text("색인 중…")
                    } else {
                        Text("일치하는 파일이 없습니다.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(quickOpen.results.enumerated()), id: \.element.id) { index, result in
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(result.url.lastPathComponent)
                                    .font(.body)
                                    .lineLimit(1)
                                Text(parentPath(result.relativePath))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(index == quickOpen.selectedIndex ? Color.accentColor.opacity(0.18) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            quickOpen.selectedIndex = index
                            model.openQuickOpenSelection()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            Text("↑↓ 이동 · ⏎ 열기 · ⌘⏎ 오른쪽 분할 · ⌘⇧⏎ 아래 분할 · Esc 닫기")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .frame(width: 600)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onAppear { focused = true }
    }

    private func parentPath(_ relative: String) -> String {
        let parent = (relative as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }
}
