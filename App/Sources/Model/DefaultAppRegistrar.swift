import AppKit
import UniformTypeIdentifiers

/// cmarks를 마크다운 기본 앱으로 등록한다(CHECKPOINTS D-6). 설치 스크립트는 `--set-default-handler` 플래그로 부른다.
enum DefaultAppRegistrar {
    static let markdownType = UTType("net.daringfireball.markdown")

    static var isDefault: Bool {
        guard let type = markdownType, let current = NSWorkspace.shared.urlForApplication(toOpen: type) else { return false }
        return current.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    static func register(completion: @escaping @Sendable (Error?) -> Void) {
        guard let type = markdownType else {
            completion(nil)
            return
        }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in
            completion(error)
        }
    }
}
