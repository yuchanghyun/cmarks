import AppKit
import WebKit

enum DocumentContextAction {
    case revealInFinder
    case copySource
    case openInEditor
}

/// WKWebView는 파일 드롭을 스스로 받아 그 URL로 이동하려 한다. 마크다운·텍스트·폴더 드롭은 앱이 열도록 넘기고 나머지는 거절한다.
/// 컨텍스트 메뉴에서는 브라우저용 항목(새로고침, 새 창, 다운로드 등)을 빼고 뷰어 항목을 더한다.
@MainActor
final class DocumentWebView: WKWebView {
    var onDropURLs: (([URL]) -> Void)?
    var onContextAction: ((DocumentContextAction) -> Void)?

    /// WebKit 기본 메뉴 중 뷰어에 맞지 않는 항목(identifier 접미사).
    private static let hiddenMenuItems = [
        "Reload", "GoBack", "GoForward", "OpenLinkInNewWindow", "OpenImageInNewWindow", "OpenFrameInNewWindow",
        "OpenMediaInNewWindow", "DownloadImage", "DownloadLinkedFile", "DownloadMedia", "ShareMenu", "SearchWeb",
        "Translate", "AddHighlightToCurrentQuickNote", "AddHighlightToNewQuickNote",
    ]

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for item in menu.items {
            guard let id = item.identifier?.rawValue else { continue }
            if Self.hiddenMenuItems.contains(where: { id.hasSuffix($0) }) { menu.removeItem(item) }
        }
        while let first = menu.items.first, first.isSeparatorItem { menu.removeItem(first) }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        for (title, action) in [("Finder에서 보기", #selector(contextRevealInFinder(_:))), ("Markdown 소스 복사", #selector(contextCopySource(_:))), ("기본 편집기로 열기", #selector(contextOpenInEditor(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
    }

    @objc private func contextRevealInFinder(_ sender: Any?) { onContextAction?(.revealInFinder) }
    @objc private func contextCopySource(_ sender: Any?) { onContextAction?(.copySource) }
    @objc private func contextOpenInEditor(_ sender: Any?) { onContextAction?(.openInEditor) }
    /// 클릭 등으로 이 웹뷰가 첫 응답자가 되면 호출된다. 패인 포커스에 쓴다.
    var onBecomeFirstResponder: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onBecomeFirstResponder?() }
        return accepted
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !Self.acceptedURLs(in: sender.draggingPasteboard).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.acceptedURLs(in: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onDropURLs?(urls)
        return true
    }

    private func dragOperation(for info: NSDraggingInfo) -> NSDragOperation {
        Self.acceptedURLs(in: info.draggingPasteboard).isEmpty ? [] : .copy
    }

    static func acceptedURLs(in pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return accepted(urls)
    }

    /// 마크다운, 일반 텍스트, 폴더만 받는다.
    nonisolated static func accepted(_ urls: [URL]) -> [URL] {
        urls.filter { url in
            if DocumentService.isMarkdown(url) || url.pathExtension.lowercased() == "txt" { return true }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }
}
