import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let servicesProvider = ServicesProvider()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 서비스 메뉴("cmarks로 열기")의 수신자. Info.plist의 NSServices와 짝이다.
        NSApp.servicesProvider = servicesProvider
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // scripts/install.sh 가 설치 직후 호출한다: 자기 자신을 .md 기본 앱으로 등록하고 종료.
        if CommandLine.arguments.contains("--set-default-handler") {
            DefaultAppRegistrar.register { error in
                if let error { NSLog("default handler registration failed: \(error.localizedDescription)") }
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
    }

    /// Finder "다음으로 열기", Dock 드롭, `open -b`, cmarks:// 딥링크가 모두 여기로 들어온다.
    /// 창이 아직 없을 수 있으므로 큐에 넣고 UI가 소비한다.
    func application(_ application: NSApplication, open urls: [URL]) {
        OpenRequestQueue.shared.enqueue(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.saveNow()
    }
}

/// NSServices 진입점. 셀렉터 `openInCmarks:userData:error:`는 Info.plist의 NSMessage(openInCmarks)와 일치해야 한다.
@MainActor
final class ServicesProvider: NSObject {
    @objc func openInCmarks(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        OpenRequestQueue.shared.enqueue(urls)
    }
}
