import AppKit
import SwiftUI

/// 사용자가 바꿀 수 있는 단축키 동작. 메뉴는 `AppSettings.keyboardShortcut(for:)`를 읽는다.
/// 탭 1–8(⌃n), 워크스페이스 1–8(⌘n), 창 닫기(⌥⌘W), 설정(⌘,)은 고정이다.
enum ShortcutAction: String, CaseIterable, Identifiable {
    case newWorkspace, newWindow, quickOpen, openFile, reopenClosedTab, closeTab
    case nextTab, previousTab
    case splitRight, splitDown, toggleZoomPane
    case focusLeft, focusRight, focusUp, focusDown
    case resizeLeft, resizeRight, resizeUp, resizeDown
    case closeWorkspace, renameWorkspace, nextWorkspace, previousWorkspace, lastWorkspace
    case back, forward, reload, find, findNext, findPrevious, searchWorkspace
    case zoomIn, zoomOut, zoomReset
    case toggleSidebar, toggleOutline, cycleAppearance
    case print, exportPDF, revealInFinder, openInEditor, shortcutHelp

    var id: String { rawValue }

    var group: String {
        switch self {
        case .newWorkspace, .newWindow, .quickOpen, .openFile, .reopenClosedTab, .closeTab: String(localized: "파일·탭")
        case .nextTab, .previousTab: String(localized: "파일·탭")
        case .splitRight, .splitDown, .toggleZoomPane, .focusLeft, .focusRight, .focusUp, .focusDown,
             .resizeLeft, .resizeRight, .resizeUp, .resizeDown: String(localized: "패인")
        case .closeWorkspace, .renameWorkspace, .nextWorkspace, .previousWorkspace, .lastWorkspace: String(localized: "워크스페이스")
        case .back, .forward, .reload, .find, .findNext, .findPrevious, .searchWorkspace, .zoomIn, .zoomOut, .zoomReset: String(localized: "문서")
        case .toggleSidebar, .toggleOutline, .cycleAppearance, .print, .exportPDF, .revealInFinder, .openInEditor, .shortcutHelp: String(localized: "보기·기타")
        }
    }

    var title: String {
        switch self {
        case .newWorkspace: String(localized: "새 워크스페이스")
        case .newWindow: String(localized: "새 창")
        case .quickOpen: String(localized: "빠른 열기 / 새 탭")
        case .openFile: String(localized: "파일 열기")
        case .reopenClosedTab: String(localized: "닫은 탭 다시 열기")
        case .closeTab: String(localized: "탭 닫기")
        case .nextTab: String(localized: "다음 탭")
        case .previousTab: String(localized: "이전 탭")
        case .splitRight: String(localized: "오른쪽으로 분할")
        case .splitDown: String(localized: "아래로 분할")
        case .toggleZoomPane: String(localized: "패인 확대 토글")
        case .focusLeft: String(localized: "왼쪽 패인")
        case .focusRight: String(localized: "오른쪽 패인")
        case .focusUp: String(localized: "위 패인")
        case .focusDown: String(localized: "아래 패인")
        case .resizeLeft: String(localized: "패인 좁히기")
        case .resizeRight: String(localized: "패인 넓히기")
        case .resizeUp: String(localized: "패인 낮추기")
        case .resizeDown: String(localized: "패인 높이기")
        case .closeWorkspace: String(localized: "워크스페이스 닫기")
        case .renameWorkspace: String(localized: "워크스페이스 이름 변경")
        case .nextWorkspace: String(localized: "다음 워크스페이스")
        case .previousWorkspace: String(localized: "이전 워크스페이스")
        case .lastWorkspace: String(localized: "마지막 워크스페이스")
        case .back: String(localized: "뒤로")
        case .forward: String(localized: "앞으로")
        case .reload: String(localized: "다시 렌더링")
        case .find: String(localized: "찾기")
        case .findNext: String(localized: "다음 찾기")
        case .findPrevious: String(localized: "이전 찾기")
        case .searchWorkspace: String(localized: "워크스페이스에서 찾기")
        case .zoomIn: String(localized: "확대")
        case .zoomOut: String(localized: "축소")
        case .zoomReset: String(localized: "실제 크기")
        case .toggleSidebar: String(localized: "사이드바 토글")
        case .toggleOutline: String(localized: "아웃라인 토글")
        case .cycleAppearance: String(localized: "테마 순환")
        case .print: String(localized: "인쇄")
        case .exportPDF: String(localized: "PDF로 내보내기")
        case .revealInFinder: String(localized: "Finder에서 보기")
        case .openInEditor: String(localized: "외부 편집기로 열기")
        case .shortcutHelp: String(localized: "단축키 표")
        }
    }

    /// cmux 호환 기본값(설계 문서 §5.2).
    var defaultCombo: KeyCombo {
        switch self {
        case .newWorkspace: KeyCombo("n", command: true)
        case .newWindow: KeyCombo("n", command: true, shift: true)
        case .quickOpen: KeyCombo("p", command: true)
        case .openFile: KeyCombo("o", command: true)
        case .reopenClosedTab: KeyCombo("t", command: true, shift: true)
        case .closeTab: KeyCombo("w", command: true)
        case .nextTab: KeyCombo("]", command: true, shift: true)
        case .previousTab: KeyCombo("[", command: true, shift: true)
        case .splitRight: KeyCombo("d", command: true)
        case .splitDown: KeyCombo("d", command: true, shift: true)
        case .toggleZoomPane: KeyCombo("return", command: true, shift: true)
        case .focusLeft: KeyCombo("left", command: true, option: true)
        case .focusRight: KeyCombo("right", command: true, option: true)
        case .focusUp: KeyCombo("up", command: true, option: true)
        case .focusDown: KeyCombo("down", command: true, option: true)
        case .resizeLeft: KeyCombo("left", command: true, option: true, control: true)
        case .resizeRight: KeyCombo("right", command: true, option: true, control: true)
        case .resizeUp: KeyCombo("up", command: true, option: true, control: true)
        case .resizeDown: KeyCombo("down", command: true, option: true, control: true)
        case .closeWorkspace: KeyCombo("w", command: true, shift: true)
        case .renameWorkspace: KeyCombo("r", command: true, shift: true)
        case .nextWorkspace: KeyCombo("]", command: true, control: true)
        case .previousWorkspace: KeyCombo("[", command: true, control: true)
        case .lastWorkspace: KeyCombo("9", command: true)
        case .back: KeyCombo("[", command: true)
        case .forward: KeyCombo("]", command: true)
        case .reload: KeyCombo("r", command: true)
        case .find: KeyCombo("f", command: true)
        case .findNext: KeyCombo("g", command: true)
        case .findPrevious: KeyCombo("g", command: true, shift: true)
        case .searchWorkspace: KeyCombo("f", command: true, shift: true)
        case .zoomIn: KeyCombo("=", command: true)
        case .zoomOut: KeyCombo("-", command: true)
        case .zoomReset: KeyCombo("0", command: true)
        case .toggleSidebar: KeyCombo("b", command: true)
        case .toggleOutline: KeyCombo("o", command: true, shift: true)
        case .cycleAppearance: KeyCombo("t", command: true, option: true)
        case .print: KeyCombo("p", command: true, option: true)
        case .exportPDF: KeyCombo("p", command: true, shift: true, option: true)
        case .revealInFinder: KeyCombo("r", command: true, option: true)
        case .openInEditor: KeyCombo("e", command: true, shift: true)
        case .shortcutHelp: KeyCombo("/", command: true)
        }
    }

    static var groups: [String] { [String(localized: "파일·탭"), String(localized: "패인"), String(localized: "워크스페이스"), String(localized: "문서"), String(localized: "보기·기타")] }
}

/// 키 하나 + 수정키. `key`는 한 글자("d", "[") 또는 특수키 이름("left", "return" 등).
struct KeyCombo: Codable, Equatable, Hashable {
    var key: String
    var command = false
    var shift = false
    var option = false
    var control = false

    init(_ key: String, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    /// 눌린 키 이벤트로부터. 글자 키는 ⌘·⌃·⌥ 중 하나가 필요하다(일반 입력과 겹치지 않게).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let special: [UInt16: String] = [
            123: "left", 124: "right", 126: "up", 125: "down", 36: "return", 76: "return",
            48: "tab", 49: "space", 51: "delete", 53: "escape", 115: "home", 119: "end", 116: "pageUp", 121: "pageDown",
        ]
        if let name = special[event.keyCode] {
            key = name
        } else {
            // 한글 등 비ASCII 입력 소스가 켜져 있으면 키 문자가 "ㅇ"처럼 나온다. ⌘를 적용한 변환은 레이아웃의 ASCII 글자를 주므로 그것을 먼저 쓴다.
            let candidates = [event.characters(byApplyingModifiers: [.command]), event.charactersIgnoringModifiers, event.characters]
            guard let chosen = candidates.compactMap({ $0 }).first(where: Self.isUsableKeyCharacter) else { return nil }
            key = chosen.lowercased()
        }
        command = flags.contains(.command)
        shift = flags.contains(.shift)
        option = flags.contains(.option)
        control = flags.contains(.control)
        guard command || control || option else { return nil }
    }

    /// 단축키로 쓸 수 있는 글자: 출력 가능한 ASCII 한 글자.
    private static func isUsableKeyCharacter(_ text: String) -> Bool {
        guard text.count == 1, let scalar = text.unicodeScalars.first else { return false }
        return scalar.isASCII && scalar.value > 0x20 && scalar.value < 0x7F
    }

    var keyEquivalent: KeyEquivalent? {
        switch key {
        case "left": .leftArrow
        case "right": .rightArrow
        case "up": .upArrow
        case "down": .downArrow
        case "return": .return
        case "tab": .tab
        case "space": .space
        case "delete": .delete
        case "escape": .escape
        case "home": .home
        case "end": .end
        case "pageUp": .pageUp
        case "pageDown": .pageDown
        default: key.count == 1 ? KeyEquivalent(Character(key)) : nil
        }
    }

    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if control { modifiers.insert(.control) }
        if option { modifiers.insert(.option) }
        if shift { modifiers.insert(.shift) }
        if command { modifiers.insert(.command) }
        return modifiers
    }

    var keyboardShortcut: KeyboardShortcut? {
        keyEquivalent.map { KeyboardShortcut($0, modifiers: eventModifiers) }
    }

    /// 메뉴와 같은 표기: ⌃⌥⇧⌘ 순서 + 키.
    var display: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        let symbol: String = switch key {
        case "left": "←"
        case "right": "→"
        case "up": "↑"
        case "down": "↓"
        case "return": "↩"
        case "tab": "⇥"
        case "space": "␣"
        case "delete": "⌫"
        case "escape": "⎋"
        case "home": "↖"
        case "end": "↘"
        case "pageUp": "⇞"
        case "pageDown": "⇟"
        default: key.uppercased()
        }
        return text + symbol
    }
}
