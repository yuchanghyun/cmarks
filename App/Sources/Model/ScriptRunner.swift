import AppKit
import Foundation
import LayoutKit
import OSLog

/// 개발·검증용 시나리오 실행기. `-CmarksScript <파일>`로 실행하면 파일의 줄을 차례로 수행하고 상태를 로그(category "script")로 남긴다.
/// 실제 창·키 윈도우·Finder 열기 이벤트를 포함한 다중 창 동작을 사람 손 없이 검증하는 데 쓴다.
///
/// 명령: sleep <ms> · dump <라벨> · key <슬롯 번호> · open <경로>(키 윈도우 사이드바 클릭과 같음) · openOutside <경로>(Finder 열기)
///      · nextTab · prevTab · tab <번호> · splitRight · closePane(메뉴와 같은 모델 호출)
///      · activate <워크스페이스 이름> · newWindow · newWindowFor <이름> · closeWindow <슬롯 번호>(performClose) · closeWindowDirect <슬롯 번호>(close) · quit
/// 워크스페이스 이름 뒤 ! = 루트 폴더를 읽지 못함(샌드박스 권한 없음).
/// 덤프의 win= 표기: v/h(보임/숨김) + K(모델의 키 윈도우) + *(AppKit 키 윈도우). 화면이 잠겨 있으면 *는 붙지 않는다.
@MainActor
enum ScriptRunner {
    private static let logger = Logger(subsystem: "com.changhyunyoo.cmarks", category: "script")

    static func start(path: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            logger.error("script not found: \(path, privacy: .public)")
            return
        }
        // 진단: 창 알림이 실제로 게시되는지 전역으로 본다(메인 큐에서 오므로 메인 액터로 본다)
        for name in [NSWindow.willCloseNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated {
                    let cls = window.map { NSStringFromClass(type(of: $0)) } ?? "?"
                    let slot = window.flatMap { AppModel.shared.slotID(of: $0) }.map { String($0.uuidString.prefix(8)) } ?? "-"
                    logger.notice("notification \(name.rawValue, privacy: .public) class=\(cls, privacy: .public) slot=\(slot, privacy: .public)")
                }
            }
        }
        let lines = text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        Task { await run(lines) }
    }

    private static func run(_ lines: [String]) async {
        let model = AppModel.shared
        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            let command = parts[0]
            let argument = parts.count > 1 ? parts[1] : ""
            logger.notice("> \(line, privacy: .public)")
            switch command {
            case "sleep":
                try? await Task.sleep(for: .milliseconds(Int(argument) ?? 500))
            case "dump":
                dump(argument)
            case "key":
                if let slot = slot(at: argument), let window = model.window(forSlot: slot.id) {
                    NSApp.activate(ignoringOtherApps: true)
                    model.focusWindow(slot.id)
                    try? await Task.sleep(for: .milliseconds(200))
                    if !window.isKeyWindow { logger.notice("key: window did not become key (app inactive / screen locked); model key follows focusWindow") }
                } else {
                    logger.error("key: no window for slot \(argument, privacy: .public)")
                }
            case "open":
                model.open(URL(fileURLWithPath: argument), window: model.keyWindowID)
            case "openOutside":
                OpenRequestQueue.shared.enqueue([URL(fileURLWithPath: argument)])
            case "activate":
                if let ws = model.workspaces.first(where: { $0.name == argument }) {
                    model.activateWorkspace(ws.id, fromWindow: model.keyWindowID)
                } else {
                    logger.error("activate: no workspace named \(argument, privacy: .public)")
                }
            case "nextTab":
                model.cycleTab(offset: 1)
            case "prevTab":
                model.cycleTab(offset: -1)
            case "tab":
                model.activateTab(at: (Int(argument) ?? 1) - 1)
            case "splitRight":
                model.split(.right)
            case "closePane":
                model.closeActiveTabOrPane(keyWindow: nil)
            case "newWindow":
                model.openNewWindow()
            case "newWindowFor":
                if let ws = model.workspaces.first(where: { $0.name == argument }) { model.openInNewWindow(ws.id) }
            case "closeWindow":
                if let slot = slot(at: argument), let window = model.window(forSlot: slot.id) { window.performClose(nil) }
            case "closeWindowDirect":
                if let slot = slot(at: argument), let window = model.window(forSlot: slot.id) { window.close() }
            case "quit":
                logger.notice("script done")
                NSApp.terminate(nil)
            default:
                logger.error("unknown command: \(command, privacy: .public)")
            }
        }
        logger.notice("script done")
    }

    private static func slot(at argument: String) -> AppModel.WindowSlot? {
        guard let index = Int(argument), AppModel.shared.windowSlots.indices.contains(index) else { return nil }
        return AppModel.shared.windowSlots[index]
    }

    /// 상태 한 줄 요약. 시험은 이 줄을 파싱한다.
    static func dump(_ label: String) {
        let model = AppModel.shared
        func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)) }
        let slots = model.windowSlots.map { slot -> String in
            let ws = model.workspace(id: slot.workspaceID)
            let tabs = ws?.focusedPane?.tabs.map { $0.document.url.lastPathComponent } ?? []
            let active = ws?.focusedPane?.activeTab?.document.url.lastPathComponent ?? "-"
            let window = model.window(forSlot: slot.id)
            // K = 모델의 키 윈도우(동작 라우팅 기준), * = AppKit 키 윈도우. 화면이 잠겨 있으면 *는 붙지 않는다.
            let windowState = window.map { "\($0.isVisible ? "v" : "h")\(model.keyWindowID == slot.id ? "K" : "")\($0.isKeyWindow ? "*" : "")" } ?? "none"
            let unreadable = model.fileTree(inWindow: slot.id)?.rootUnreadable == true ? "!" : ""
            return "\(short(slot.id))→\(ws?.name ?? "?")\(unreadable)[\(tabs.joined(separator: ","))|active=\(active)] win=\(windowState)"
        }
        let appWindows = NSApp.windows.filter { $0.isVisible && NSStringFromClass(type(of: $0)).contains("AppKitWindow") }
        let unmapped = appWindows.filter { model.slotID(of: $0) == nil }.count
        for window in NSApp.windows where NSStringFromClass(type(of: window)).contains("AppKitWindow") {
            let slot = model.slotID(of: window).map { String($0.uuidString.prefix(8)) } ?? "-"
            logger.notice("[\(label, privacy: .public)] window slot=\(slot, privacy: .public) visible=\(window.isVisible) key=\(window.isKeyWindow) released=\(window.isReleasedWhenClosed) title=\(window.title, privacy: .public)")
        }
        logger.notice("[\(label, privacy: .public)] slots=\(slots.joined(separator: " ; "), privacy: .public) | windows=\(appWindows.count) unmapped=\(unmapped) key=\(short(model.keyWindowID), privacy: .public) active=\(model.workspace.name, privacy: .public) workspaces=\(model.workspaces.map(\.name).joined(separator: ","), privacy: .public)")
    }
}
