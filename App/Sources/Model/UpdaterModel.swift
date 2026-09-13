import Foundation
import Sparkle

/// Sparkle 자동 업데이트(App Store 밖 배포용). 피드 주소와 EdDSA 공개 키는 Info.plist(SUFeedURL, SUPublicEDKey).
/// 하루 한 번 appcast를 읽고 새 버전이 있으면 Sparkle 표준 창으로 안내한다.
/// 테스트 호스트와 `-CmarksDisableUpdater YES`로 실행하면 네트워크에 나가지 않는다.
@MainActor
@Observable
final class UpdaterModel {
    static let shared = UpdaterModel()

    /// 지금 검사를 시작할 수 있는지(검사 중이거나 업데이터가 꺼져 있으면 false). 메뉴 활성화에 쓴다.
    private(set) var canCheckForUpdates = false

    /// 하루 한 번 자동 검사. 설정 ▸ 동작 ▸ 업데이트.
    var automaticallyChecksForUpdates: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    var isAvailable: Bool { controller != nil }

    private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init() {
        let disabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || UserDefaults.standard.bool(forKey: "CmarksDisableUpdater")
        guard !disabled else {
            controller = nil
            automaticallyChecksForUpdates = false
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        canCheckForUpdates = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, change in
            let value = change.newValue ?? updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
