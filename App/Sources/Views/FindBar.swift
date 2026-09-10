import SwiftUI

/// 문서 위 오른쪽에 뜨는 찾기 바(⌘F). Enter 다음, ⌘G / ⌘⇧G 다음·이전, Esc 닫기.
struct FindBar: View {
    @Bindable var viewer: PaneViewer
    @FocusState private var focused: Bool
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("찾기", text: $viewer.findQuery)
                .textFieldStyle(.plain)
                .frame(minWidth: 160)
                .focused($focused)
                .onSubmit { Task { await viewer.findNext() } }
                .onExitCommand { viewer.hideFindBar() }
            Text(countLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
            Button { Task { await viewer.findPrevious() } } label: { Image(systemName: "chevron.up") }
                .disabled(viewer.findCount == 0)
                .help("이전 찾기 (⌘⇧G)")
            Button { Task { await viewer.findNext() } } label: { Image(systemName: "chevron.down") }
                .disabled(viewer.findCount == 0)
                .help("다음 찾기 (⌘G)")
            Toggle(isOn: $viewer.findCaseSensitive) { Text("Aa") }
                .toggleStyle(.button)
                .help("대소문자 구분")
            Button { viewer.hideFindBar() } label: { Image(systemName: "xmark") }
                .help("닫기 (Esc)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .onAppear { focused = true }
        .onChange(of: viewer.findFocusRequest) { _, _ in focused = true }
        .onChange(of: viewer.findQuery) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                await viewer.performFind()
            }
        }
    }

    private var countLabel: String {
        if viewer.findQuery.isEmpty { return "" }
        if viewer.findCount == 0 { return String(localized: "없음") }
        return "\(viewer.findIndex + 1) / \(viewer.findCount)"
    }
}
