import AppKit
import Foundation

/// 보기 ▸ Finder 선택 따라가기. Finder가 맨 앞에 있을 때 0.4초마다 선택 항목을 읽어,
/// 마크다운 파일 하나가 선택되면 미리보기 탭으로 연다. "사라지지 않는 Quick Look"의 역할.
/// Finder 제어(Apple Events)에는 자동화 권한이 필요하며, 처음 켤 때 시스템이 묻는다.
@MainActor
@Observable
final class FinderFollower {
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled { start() } else { stop() }
        }
    }
    /// 선택된 마크다운 파일을 열 때 불린다(미리보기 탭).
    @ObservationIgnored var onSelect: ((URL) -> Void)?
    @ObservationIgnored var isMarkdown: (URL) -> Bool = { _ in false }
    @ObservationIgnored var interval: Duration = .milliseconds(400)

    private var task: Task<Void, Never>?
    private var lastPath: String?
    private var script: NSAppleScript?
    private var didWarn = false

    nonisolated static let source = """
    tell application "Finder"
        set sel to selection
        if (count of sel) is not 1 then return ""
        return POSIX path of (item 1 of sel as alias)
    end tell
    """

    /// 선택 경로가 새로 열 파일이면 URL. 같은 파일이 계속 선택되어 있거나 마크다운이 아니면 nil.
    nonisolated static func target(selection path: String, last: String?, isMarkdown: (URL) -> Bool) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != last, !trimmed.hasSuffix("/") else { return nil }
        let url = URL(fileURLWithPath: trimmed)
        return isMarkdown(url) ? url : nil
    }

    private func start() {
        lastPath = nil
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: self?.interval ?? .milliseconds(400))
            }
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
    }

    private func poll() {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
        if script == nil { script = NSAppleScript(source: Self.source) }
        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error) else {
            let code = (error?[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1743: 자동화 권한 거부. 그 밖의 오류(선택 항목이 파일이 아닐 때 등)는 무시한다.
            if code == -1743 { warnPermissionDenied() }
            return
        }
        let path = result.stringValue ?? ""
        let previous = lastPath
        if !path.isEmpty { lastPath = path }
        guard let url = Self.target(selection: path, last: previous, isMarkdown: isMarkdown) else { return }
        onSelect?(url)
    }

    private func warnPermissionDenied() {
        isEnabled = false
        guard !didWarn else { return }
        didWarn = true
        let alert = NSAlert()
        alert.messageText = String(localized: "Finder 선택 따라가기")
        alert.informativeText = String(localized: "cmarks가 Finder의 선택 항목을 읽을 권한이 없습니다. 시스템 설정 ▸ 개인정보 보호 및 보안 ▸ 자동화에서 cmarks 아래의 Finder를 켠 뒤 다시 시도해 주세요.")
        alert.addButton(withTitle: String(localized: "확인"))
        alert.runModal()
    }
}
