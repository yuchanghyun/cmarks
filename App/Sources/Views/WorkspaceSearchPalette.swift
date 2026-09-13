import LayoutKit
import SwiftUI

/// ⌘⇧F 워크스페이스에서 찾기. 파일 내용을 줄 단위로 찾아 보여 주고, 고르면 그 파일을 열어 찾기 바를 그 위치로 맞춘다.
struct WorkspaceSearchPalette: View {
    @Environment(AppModel.self) private var model
    @Bindable var search: WorkspaceSearchModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "text.magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("검색어 (2자 이상)", text: $search.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { model.openSearchSelection() }
                    .onExitCommand { search.dismiss() }
                    .onKeyPress(.upArrow) { search.moveSelection(-1); return .handled }
                    .onKeyPress(.downArrow) { search.moveSelection(1); return .handled }
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        model.openSearchSelection(split: press.modifiers.contains(.shift) ? .down : .right)
                        return .handled
                    }
                if search.isSearching {
                    ProgressView().controlSize(.small)
                } else if search.summary.hits > 0 {
                    Text(String(localized: "\(search.summary.files)개 파일에서 \(search.summary.hits)개 일치"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            if search.results.isEmpty {
                Group {
                    if search.query.trimmingCharacters(in: .whitespaces).count < WorkspaceSearchModel.minimumQueryLength {
                        Text("워크스페이스의 마크다운 파일 내용을 찾습니다.")
                    } else if search.isSearching {
                        Text("검색 중…")
                    } else {
                        Text("일치하는 내용이 없습니다.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(search.results.enumerated()), id: \.element.id) { index, hit in
                                row(hit, selected: index == search.selectedIndex)
                                    .id(hit.id)
                                    .onTapGesture {
                                        search.selectedIndex = index
                                        model.openSearchSelection()
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 420)
                    .onChange(of: search.selectedIndex) { _, index in
                        if let hit = search.results.indices.contains(index) ? search.results[index] : nil {
                            proxy.scrollTo(hit.id, anchor: .center)
                        }
                    }
                }
            }
            Divider()
            Text("↑↓ 이동 · ⏎ 열기 · ⌘⏎ 오른쪽 분할 · ⌘⇧⏎ 아래 분할 · Esc 닫기")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .frame(width: 680)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onAppear { focused = true }
    }

    private func row(_ hit: WorkspaceSearchModel.Hit, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").foregroundStyle(.secondary).font(.caption)
                Text(hit.relativePath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text(":\(hit.line)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
            snippetText(hit)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
    }

    private func snippetText(_ hit: WorkspaceSearchModel.Hit) -> Text {
        let before = String(hit.snippet[..<hit.matchRange.lowerBound])
        let match = String(hit.snippet[hit.matchRange])
        let after = String(hit.snippet[hit.matchRange.upperBound...])
        return Text(verbatim: before) + Text(verbatim: match).bold().foregroundStyle(Color.accentColor) + Text(verbatim: after)
    }
}
