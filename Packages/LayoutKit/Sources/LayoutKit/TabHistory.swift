import Foundation

/// 탭 안의 링크 이동 히스토리(⌘[ / ⌘]). 브라우저와 같은 규칙: 새 이동은 현재 위치 뒤의 기록을 버린다.
public extension Tab {
    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }

    mutating func navigate(to ref: DocumentRef) {
        if history.indices.contains(historyIndex) {
            history.removeSubrange(history.index(after: historyIndex)...)
        }
        history.append(ref)
        historyIndex = history.count - 1
        document = ref
    }

    @discardableResult
    mutating func goBack() -> DocumentRef? {
        guard canGoBack else { return nil }
        historyIndex -= 1
        document = history[historyIndex]
        return document
    }

    @discardableResult
    mutating func goForward() -> DocumentRef? {
        guard canGoForward else { return nil }
        historyIndex += 1
        document = history[historyIndex]
        return document
    }
}
