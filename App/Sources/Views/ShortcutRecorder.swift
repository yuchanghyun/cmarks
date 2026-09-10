import AppKit
import SwiftUI

/// 단축키 녹화. 클릭하면 다음 키 조합을 받는다. 로컬 이벤트 모니터가 메뉴보다 먼저 키를 가로채므로
/// ⌘D처럼 이미 메뉴에 있는 조합도 녹화할 수 있다. Esc 취소, ⌫ 기본값 복원.
struct ShortcutRecorderButton: View {
    let action: ShortcutAction
    @Bindable var settings: AppSettings
    @State private var recorder = KeyRecorder()

    var body: some View {
        let combo = settings.combo(for: action)
        let conflicts = settings.conflicts(for: action)
        HStack(spacing: 6) {
            if !conflicts.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("같은 조합을 쓰는 동작: \(conflicts.map(\.title).joined(separator: ", "))")
            }
            if combo != action.defaultCombo, !recorder.isRecording {
                Button {
                    settings.resetShortcut(for: action)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("기본값으로 (\(action.defaultCombo.display))")
            }
            Button {
                recorder.begin { result in
                    switch result {
                    case .combo(let combo): settings.setCombo(combo, for: action)
                    case .reset: settings.resetShortcut(for: action)
                    case .cancel: break
                    }
                }
            } label: {
                (recorder.isRecording ? Text("키를 누르세요…") : Text(combo.display))
                    .font(.body.monospaced())
                    .frame(minWidth: 110)
            }
            .buttonStyle(.bordered)
            .tint(recorder.isRecording ? Color.accentColor : nil)
            .help("클릭한 뒤 새 조합을 누르세요. Esc 취소, ⌫ 기본값")
        }
        .onDisappear { recorder.cancel() }
    }
}

@MainActor
@Observable
final class KeyRecorder {
    enum Result: Equatable {
        case combo(KeyCombo)
        case reset
        case cancel
    }

    private(set) var isRecording = false
    private var monitor: Any?
    private var completion: ((Result) -> Void)?

    func begin(_ completion: @escaping (Result) -> Void) {
        cancel()
        self.completion = completion
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 녹화 중에는 모든 keyDown을 여기서 소비해 메뉴·텍스트 필드에 전달되지 않게 한다.
            let handled: Bool = MainActor.assumeIsolated {
                guard let self else { return false }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if event.keyCode == 53, flags.isEmpty {
                    self.finish(.cancel)
                } else if event.keyCode == 51, flags.isEmpty {
                    self.finish(.reset)
                } else if let combo = KeyCombo(event: event) {
                    self.finish(.combo(combo))
                } else {
                    NSSound.beep()
                }
                return true
            }
            return handled ? nil : event
        }
    }

    func cancel() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        completion = nil
    }

    private func finish(_ result: Result) {
        let completion = self.completion
        cancel()
        completion?(result)
    }
}
