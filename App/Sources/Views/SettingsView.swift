import SwiftUI

/// 설정 창(⌘,). 항목은 설계 문서 §5.3.
struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettingsTab().tabItem { Label("외형", systemImage: "paintbrush") }
            RenderingSettingsTab().tabItem { Label("렌더링", systemImage: "doc.richtext") }
            FilesSettingsTab().tabItem { Label("파일", systemImage: "folder") }
            BehaviorSettingsTab().tabItem { Label("동작", systemImage: "gearshape") }
            ShortcutSettingsTab().tabItem { Label("단축키", systemImage: "keyboard") }
        }
        .frame(width: 600, height: 520)
        .background {
            // Esc로 설정 창 닫기. ⌘W는 메뉴 명령이 키 윈도우를 보고 처리한다.
            Button("") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

private struct ShortcutSettingsTab: View {
    @Bindable private var settings = AppModel.shared.settings

    var body: some View {
        Form {
            ForEach(ShortcutAction.groups, id: \.self) { group in
                Section(group) {
                    ForEach(ShortcutAction.allCases.filter { $0.group == group }) { action in
                        LabeledContent(action.title) {
                            ShortcutRecorderButton(action: action, settings: settings)
                        }
                    }
                }
            }
            Section {
                Button("모든 단축키를 기본값으로") { settings.resetAllShortcuts() }
                Text("단축키 칸을 클릭하고 새 조합을 누르세요. Esc는 취소, ⌫는 기본값입니다. 다른 앱이나 시스템(Mission Control 등)이 쓰는 조합은 여기서 바꿔 피할 수 있습니다. 탭 1–8(⌃숫자)과 워크스페이스 1–8(⌘숫자)은 고정입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettingsTab: View {
    @Bindable private var model = AppModel.shared
    @Bindable private var settings = AppModel.shared.settings

    var body: some View {
        Form {
            Picker("테마", selection: $model.appearance) {
                ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0) }
            }
            Picker("본문 폭", selection: $settings.useGitHubWidth) {
                Text("GitHub와 같은 980px").tag(true)
                Text("창 폭 전체").tag(false)
            }
            HStack {
                Text("새 탭 기본 배율")
                Slider(value: $settings.defaultZoom, in: 0.5...2.0, step: 0.1)
                Text(settings.defaultZoom.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit().frame(width: 48, alignment: .trailing)
            }
            Toggle("렌더 통계 표시", isOn: $model.showRenderStats)
            Section {
                TextEditor(text: $settings.customCSS)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 110)
            } header: {
                Text("사용자 CSS")
            } footer: {
                Text("모든 문서에 추가로 적용합니다. 예: .markdown-body { font-size: 18px; font-family: serif }")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct RenderingSettingsTab: View {
    @Bindable private var settings = AppModel.shared.settings

    var body: some View {
        Form {
            Section("확장") {
                Toggle("수식 (KaTeX)", isOn: $settings.math)
                Toggle("Mermaid 다이어그램", isOn: $settings.mermaid)
                Toggle("이모지 숏코드 (:smile:)", isOn: $settings.emoji)
                Toggle("각주", isOn: $settings.footnotes)
                Toggle("프런트매터를 접힌 블록으로 표시", isOn: $settings.showFrontMatter)
            }
            Section("파서") {
                Toggle("raw HTML 허용 (위험 태그는 항상 걸러냄)", isOn: $settings.rawHTML)
                Toggle("줄 바꿈을 그대로 반영 (hard breaks)", isOn: $settings.hardBreaks)
                Toggle("스마트 문장부호 (따옴표·대시 변환)", isOn: $settings.smartPunctuation)
            }
            Section("대용량 문서") {
                Stepper("하이라이팅·수식·다이어그램 생략: \(settings.largeDocumentMB) MB 초과", value: $settings.largeDocumentMB, in: 1...100)
                Stepper("앞부분만 표시: \(settings.hugeDocumentMB) MB 초과", value: $settings.hugeDocumentMB, in: 2...500)
            }
        }
        .formStyle(.grouped)
    }
}

private struct FilesSettingsTab: View {
    @Bindable private var model = AppModel.shared
    @Bindable private var settings = AppModel.shared.settings

    var body: some View {
        Form {
            Section {
                TextField("마크다운 확장자", text: $settings.markdownExtensions, axis: .vertical)
                    .lineLimit(2...3)
                Text("공백으로 구분. 파일 트리·빠른 열기·드롭에서 마크다운으로 취급합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                TextField("무시할 폴더 이름", text: $settings.ignoredDirectories, axis: .vertical)
                    .lineLimit(2...3)
                Text("파일 트리와 빠른 열기 색인에서 건너뜁니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("숨김 파일 표시", isOn: $model.showHiddenFiles)
                Toggle("심볼릭 링크 따라가기", isOn: $settings.followSymlinks)
            }
            Section {
                Button("기본값으로 되돌리기") { settings.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct BehaviorSettingsTab: View {
    @Bindable private var settings = AppModel.shared.settings
    @Bindable private var updater = UpdaterModel.shared

    var body: some View {
        Form {
            Section {
                Toggle("파일 트리 단일 클릭은 미리보기 탭으로 열기 (더블클릭은 고정)", isOn: $settings.singleClickPreview)
                Toggle("문서 안 마크다운 링크를 새 탭으로 열기 (기본은 같은 탭)", isOn: $settings.openLinksInNewTab)
            } header: {
                Text("열기")
            } footer: {
                Text("웹 링크(http, https)는 항상 기본 브라우저에서 열립니다. ⌘클릭은 새 탭, ⌥클릭은 오른쪽 분할입니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("기본 앱") {
                DefaultAppRow()
            }
            Section("문서") {
                Toggle("파일이 바뀌면 자동으로 다시 렌더링 (라이브 리로드)", isOn: $settings.liveReload)
            }
            Section("세션") {
                Toggle("시작할 때 워크스페이스와 탭 복원", isOn: $settings.restoreSession)
                Toggle("임시 워크스페이스는 마지막 탭을 닫으면 자동으로 정리", isOn: $settings.cleanupEphemeral)
            }
            Section {
                Toggle("업데이트 자동 확인", isOn: $updater.automaticallyChecksForUpdates)
                    .disabled(!updater.isAvailable)
                Button("업데이트 확인…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            } header: {
                Text("업데이트")
            } footer: {
                Text("하루 한 번 새 버전이 있는지 확인합니다. Homebrew로 설치했다면 brew upgrade --cask cmarks 로도 갱신됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DefaultAppRow: View {
    @State private var isDefault = DefaultAppRegistrar.isDefault
    @State private var message: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if isDefault {
                    Text("cmarks가 .md 파일의 기본 앱입니다.")
                } else {
                    Text("cmarks를 .md 파일의 기본 앱으로 지정")
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(isDefault ? LocalizedStringKey("다시 지정") : LocalizedStringKey("기본 앱으로 지정")) {
                DefaultAppRegistrar.register { error in
                    Task { @MainActor in
                        isDefault = DefaultAppRegistrar.isDefault
                        message = error?.localizedDescription ?? (isDefault ? String(localized: "Finder에서 .md를 열면 cmarks로 열립니다.") : String(localized: "지정되지 않았습니다."))
                    }
                }
            }
        }
    }
}
