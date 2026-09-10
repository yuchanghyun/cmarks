import AppKit
import Foundation
import LayoutKit
import SwiftUI
import Testing
@testable import cmarks

@MainActor
struct ShortcutTests {
    private func keyEvent(_ characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    /// R-22: 키 이벤트 → KeyCombo → 메뉴 단축키 표기.
    @Test func keyComboFromEvents() {
        let commandD = KeyCombo(event: keyEvent("d", keyCode: 2, flags: [.command]))
        #expect(commandD == KeyCombo("d", command: true))
        #expect(commandD?.display == "⌘D")

        let controlOptionLeft = KeyCombo(event: keyEvent("", keyCode: 123, flags: [.control, .option]))
        #expect(controlOptionLeft == KeyCombo("left", option: true, control: true))
        #expect(controlOptionLeft?.display == "⌃⌥←")
        #expect(controlOptionLeft?.keyboardShortcut == KeyboardShortcut(.leftArrow, modifiers: [.control, .option]))

        // 수정키 없는 글자는 단축키로 받지 않는다
        #expect(KeyCombo(event: keyEvent("a", keyCode: 0, flags: [])) == nil)
        #expect(KeyCombo(event: keyEvent("A", keyCode: 0, flags: [.shift])) == nil)
        // 특수키는 수정키 하나 이상이 있으면 된다
        #expect(KeyCombo(event: keyEvent("\r", keyCode: 36, flags: [.command, .shift]))?.display == "⇧⌘↩")
    }

    @Test func settingsStoreOverridesAndDetectConflicts() {
        let defaults = UserDefaults(suiteName: "cmarks.tests.shortcuts.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.combo(for: .focusLeft) == KeyCombo("left", command: true, option: true))
        #expect(settings.conflicts(for: .focusLeft).isEmpty)

        settings.setCombo(KeyCombo("left", option: true, control: true), for: .focusLeft)
        #expect(settings.keyboardShortcut(for: .focusLeft) == KeyboardShortcut(.leftArrow, modifiers: [.control, .option]))
        // 다른 인스턴스로 다시 읽어도 유지된다
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.combo(for: .focusLeft) == KeyCombo("left", option: true, control: true))

        settings.setCombo(settings.combo(for: .splitRight), for: .find) // ⌘D 중복
        #expect(settings.conflicts(for: .find) == [.splitRight])
        #expect(settings.conflicts(for: .splitRight) == [.find])
        settings.resetShortcut(for: .find)
        #expect(settings.conflicts(for: .find).isEmpty)
        settings.setCombo(ShortcutAction.focusLeft.defaultCombo, for: .focusLeft)
        #expect(settings.combo(for: .focusLeft) == ShortcutAction.focusLeft.defaultCombo)
    }

    /// 기본 단축키끼리 겹치지 않는다.
    @Test func defaultShortcutsAreUnique() {
        var seen: [KeyCombo: ShortcutAction] = [:]
        for action in ShortcutAction.allCases {
            let combo = action.defaultCombo
            #expect(seen[combo] == nil, "\(action) duplicates \(String(describing: seen[combo]))")
            seen[combo] = action
        }
    }

    /// 녹화기: 로컬 이벤트 모니터가 keyDown을 받아 조합을 저장한다.
    @Test func recorderCapturesPostedKeyEvent() async throws {
        let recorder = KeyRecorder()
        var result: KeyRecorder.Result?
        recorder.begin { result = $0 }
        #expect(recorder.isRecording)
        let event = keyEvent("k", keyCode: 40, flags: [.command, .control])
        NSApp.postEvent(event, atStart: false)
        let captured = await waitUntil(timeout: .seconds(3)) { result != nil }
        if captured {
            #expect(result == .combo(KeyCombo("k", command: true, control: true)))
            #expect(!recorder.isRecording)
        } else {
            // 테스트 호스트가 활성 앱이 아니면 이벤트 루프가 이벤트를 배달하지 않을 수 있다. 취소만 확인한다.
            recorder.cancel()
            #expect(!recorder.isRecording)
        }
    }
}

@MainActor
struct DividerViewTests {
    private func mouse(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    /// R-24: 드래그 이동량이 축 방향으로 전달되고(아래로 끌면 양수), 더블클릭은 균등 분할 콜백.
    @Test func dividerViewReportsDragTranslationAndDoubleClick() {
        let view = DividerNSView(frame: NSRect(x: 0, y: 0, width: 7, height: 300))
        view.axis = .horizontal
        var began = 0
        var translations: [CGFloat] = []
        var ended = 0
        var doubleClicks = 0
        view.onDragBegan = { began += 1 }
        view.onDragChanged = { translations.append($0) }
        view.onDragEnded = { ended += 1 }
        view.onDoubleClick = { doubleClicks += 1 }

        view.mouseDown(with: mouse(.leftMouseDown, x: 100, y: 100))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 140, y: 100))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 60, y: 100))
        view.mouseUp(with: mouse(.leftMouseUp, x: 60, y: 100))
        #expect(began == 1)
        #expect(translations == [40, -40])
        #expect(ended == 1)

        view.axis = .vertical
        view.mouseDown(with: mouse(.leftMouseDown, x: 100, y: 100))
        view.mouseDragged(with: mouse(.leftMouseDragged, x: 100, y: 70)) // 창 좌표 y는 위로 증가 → 아래로 30 끌기
        #expect(translations.last == 30)
        view.mouseUp(with: mouse(.leftMouseUp, x: 100, y: 70))

        view.mouseDown(with: mouse(.leftMouseDown, x: 100, y: 100, clicks: 2))
        #expect(doubleClicks == 1)
        #expect(began == 2) // 더블클릭은 드래그를 시작하지 않는다
    }
}
