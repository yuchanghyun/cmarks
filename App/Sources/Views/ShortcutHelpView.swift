import SwiftUI

/// ⌘/ 단축키 표(설계 문서 §5.2).
struct ShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private static let groups: [(String, [(String, String)])] = [
        ("워크스페이스", [
            ("새 워크스페이스", "⌘N"), ("워크스페이스 1–8 / 마지막", "⌘1–8 / ⌘9"), ("다음 / 이전 워크스페이스", "⌃⌘] / ⌃⌘["),
            ("워크스페이스 닫기 / 이름 변경", "⌘⇧W / ⌘⇧R"), ("사이드바 토글", "⌘B"), ("아웃라인 토글", "⌘⇧O"),
        ]),
        ("탭", [
            ("빠른 열기 / 새 탭", "⌘P / ⌘T"), ("파일 열기", "⌘O"), ("탭 닫기 (탭 → 패인 → 창)", "⌘W"),
            ("다음 / 이전 탭", "⌘⇧] / ⌘⇧[ , ⌃Tab / ⌃⇧Tab"), ("탭 1–8", "⌃1–8"),
        ]),
        ("패인", [
            ("오른쪽 / 아래 분할", "⌘D / ⌘⇧D"), ("패인 포커스 이동", "⌥⌘← → ↑ ↓"), ("패인 확대 토글", "⌘⇧↩"),
            ("패인 크기 조정", "⌃⌥⌘← → ↑ ↓"), ("디바이더 균등 분할", "디바이더 더블클릭"),
        ]),
        ("문서", [
            ("뒤로 / 앞으로", "⌘[ / ⌘]"), ("다시 렌더링", "⌘R"), ("찾기 / 다음 / 이전", "⌘F / ⌘G / ⌘⇧G"), ("워크스페이스에서 찾기", "⌘⇧F"),
            ("확대 / 축소 / 실제 크기", "⌘= / ⌘- / ⌘0"), ("Finder에서 보기", "⌥⌘R"), ("외부 편집기로 열기", "⌘⇧E"),
            ("인쇄 / PDF 내보내기", "⌥⌘P / ⌥⌘⇧P"), ("링크 ⌘클릭 / ⌥클릭", "새 탭 / 오른쪽 분할"),
        ]),
        ("기타", [("테마 순환", "⌥⌘T"), ("설정", "⌘,"), ("이 표", "⌘/")]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("단축키").font(.title2.weight(.semibold))
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Self.groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey(group.0)).font(.headline)
                            ForEach(group.1, id: \.0) { row in
                                HStack {
                                    Text(LocalizedStringKey(row.0))
                                    Spacer()
                                    Text(LocalizedStringKey(row.1)).font(.body.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 520, height: 600)
    }
}
