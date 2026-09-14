import AppKit
import LayoutKit
import OSLog
import WebKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let servicesProvider = ServicesProvider()
    private static let dumpLogger = Logger(subsystem: "com.changhyunyoo.cmarks", category: "dump")

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
            return
        }
        // Sparkle 업데이터 기동(하루 한 번 검사 예약).
        _ = UpdaterModel.shared
        // 강제 종료·크래시 뒤에는 AppKit이 "복원할 상태가 있다"고 보고 SwiftUI가 기본 창을 만들지 않는 경우가 있다
        // (로그: hasPersistentStateToRestore=1). 잠시 뒤에도 창이 없으면 재열기 이벤트로 기본 창을 띄운다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { AppModel.shared.ensureVisibleWindow() }
        // 개발용: `-CmarksDumpWindows YES`로 실행하면 5초 뒤 창·웹뷰 계층을 로그로 남긴다(다중 창 진단).
        if CommandLine.arguments.contains("-CmarksDumpWindows") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { Self.dumpWindows() }
        }
        // 개발·검증용: `-CmarksScript <파일>`로 시나리오를 실행한다(ScriptRunner).
        if let index = CommandLine.arguments.firstIndex(of: "-CmarksScript"), CommandLine.arguments.indices.contains(index + 1) {
            ScriptRunner.start(path: CommandLine.arguments[index + 1])
        }
    }

    private static func dumpWindows() {
        let model = AppModel.shared
        dumpLogger.notice("dump start: \(NSApp.windows.count) windows")
        for window in NSApp.windows {
            dumpLogger.notice("window '\(window.title, privacy: .public)' visible=\(window.isVisible) key=\(window.isKeyWindow) occluded=\(!window.occlusionState.contains(.visible)) frame=\(NSStringFromRect(window.frame), privacy: .public) class=\(NSStringFromClass(type(of: window)), privacy: .public)")
            guard let content = window.contentView else { continue }
            func walk(_ view: NSView) {
                if let web = view as? DocumentWebView {
                    dumpLogger.notice("  webview frame=\(NSStringFromRect(web.frame), privacy: .public) hidden=\(web.isHidden) alpha=\(web.alphaValue) superview=\(NSStringFromClass(type(of: web.superview ?? content)), privacy: .public)")
                }
                for sub in view.subviews { walk(sub) }
            }
            walk(content)
        }
        for (pane, viewer) in model.viewers {
            dumpLogger.notice("viewer pane=\(pane.raw.uuidString.prefix(8), privacy: .public) state=\(String(describing: viewer.state).prefix(40), privacy: .public) url=\(viewer.currentURL?.lastPathComponent ?? "-", privacy: .public) webWindow=\(viewer.webView.window?.title ?? "nil", privacy: .public) webFrame=\(NSStringFromRect(viewer.webView.frame), privacy: .public)")
        }
        let slots = model.windowSlots.map { "\($0.id.uuidString.prefix(8))→\(model.workspace(id: $0.workspaceID)?.name ?? "?")" }.joined(separator: ", ")
        dumpLogger.notice("slots=\(slots, privacy: .public)")
        // 웹뷰 자체 스냅샷: 화면 캡처와 무관하게 웹 콘텐츠가 그려졌는지 본다
        let directory = UserDefaults.standard.string(forKey: "CmarksSessionDirectory") ?? NSTemporaryDirectory()
        for (pane, viewer) in model.viewers {
            let name = String(pane.raw.uuidString.prefix(8))
            viewer.webView.takeSnapshot(with: nil) { image, error in
                MainActor.assumeIsolated {
                    if let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                        let url = URL(fileURLWithPath: directory).appending(path: "snap-\(name).png")
                        try? png.write(to: url)
                        dumpLogger.notice("snapshot \(name, privacy: .public) \(Int(image.size.width))x\(Int(image.size.height)) → \(url.path, privacy: .public)")
                    } else {
                        dumpLogger.error("snapshot \(name, privacy: .public) failed: \(error?.localizedDescription ?? "?", privacy: .public)")
                    }
                }
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
