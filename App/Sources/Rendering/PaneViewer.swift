import AppKit
import FileKit
import LayoutKit
import MarkdownCore
import OSLog
import UniformTypeIdentifiers
import WebKit

struct OutlineItem: Equatable, Identifiable {
    var level: Int
    var text: String
    var id: String
}

struct RenderStats: Equatable {
    var swiftRenderMS: Double
    var jsReadyMS: Double?
    var jsEnhancedMS: Double?
    var codeBlocks = 0
    var images = 0
    var headings = 0
    var bytes: Int
    var fromCache: Bool
    var encoding: String
    var changedBlocks: Int?

    init(document: RenderedDocument) {
        swiftRenderMS = Double(document.renderDuration.components.seconds) * 1000
            + Double(document.renderDuration.components.attoseconds) / 1e15
        bytes = document.byteCount
        fromCache = document.fromCache
        encoding = String.localizedName(of: document.encoding)
    }
}

/// 링크 클릭의 의도. ⌘클릭은 새 탭, ⌥클릭은 새 분할(설계 문서 §4.5).
enum NavigationIntent: Equatable {
    case sameTab
    case newTab
    case newSplit(SplitDirection)
}

/// 패인 하나의 웹뷰와 문서 상태(설계 문서 §4.6). 패인마다 하나씩 있다.
/// 문서 열기, 파일 감시와 제자리 갱신, 스크롤 기억, 찾기, 인쇄를 맡는다. 모델 변경은 콜백으로 AppModel에 넘긴다.
@MainActor
@Observable
final class PaneViewer {
    enum State: Equatable {
        case empty
        case loading(URL)
        case loaded(URL)
        case failed(URL, String)

        var showsWebView: Bool {
            switch self {
            case .loading, .loaded: true
            case .empty, .failed: false
            }
        }
    }

    private(set) var state: State = .empty
    private(set) var currentURL: URL?
    private(set) var outline: [OutlineItem] = []
    /// 스크롤 위치에 걸친 헤딩(아웃라인 강조).
    private(set) var activeHeadingID: String?
    private(set) var stats: RenderStats?
    /// 감시 중인 파일이 사라졌다. 돌아오면 자동으로 다시 렌더한다.
    private(set) var isFileMissing = false
    var zoom: CGFloat = 1.0 {
        didSet { webView.pageZoom = zoom }
    }
    let paneID: PaneID
    /// 이 뷰어가 보여 주는 탭. AppModel이 동기화할 때 맞춘다.
    var currentTabID: Tab.ID?
    /// 마지막으로 보고된 스크롤 위치. 탭 전환·세션 저장 때 탭에 기록된다.
    private(set) var currentScrollY: Double = 0

    /// 설정 ▸ 라이브 리로드.
    var isLiveReloadEnabled = true
    /// 문서 위로 떨어진 파일. AppModel이 연결한다.
    var onDropURLs: (([URL]) -> Void)?
    /// 링크 클릭으로 다른 문서로 가려 할 때.
    var onNavigate: ((DocumentRef, NavigationIntent) -> Void)?
    /// 웹뷰가 첫 응답자가 됐을 때(패인 포커스).
    var onFocus: (() -> Void)?
    /// 컨텍스트 메뉴 "외부 편집기로 열기". AppModel이 앱 선택 규칙을 갖고 있다.
    var onOpenInEditor: (() -> Void)?

    // 찾기(⌘F)
    var isFindBarVisible = false
    var findQuery = ""
    var findCaseSensitive = false {
        didSet { Task { await performFind() } }
    }
    private(set) var findCount = 0
    private(set) var findIndex = -1
    /// 증가할 때마다 찾기 입력란이 포커스를 가져간다.
    private(set) var findFocusRequest = 0

    let webView: DocumentWebView
    private let documents: DocumentService
    private let schemeHandler: LocalSchemeHandler
    private let delegate: WebViewDelegate
    private let logger = Logger(subsystem: "com.changhyunyoo.cmarks", category: "viewer")
    private var loadTask: Task<Void, Never>?
    private var watcher: FileWatcher?
    /// 페이지의 app.js가 ready를 보낸 뒤 true. 테스트가 기다리는 신호이기도 하다.
    private(set) var isPageReady = false
    private var pendingFragment: String?
    private var pendingScrollY: Double?
    private var scrollPositions: [URL: Double] = [:]
    private var userScrolledSinceLoad = false

    init(paneID: PaneID, documents: DocumentService) {
        self.paneID = paneID
        self.documents = documents
        let assetsRoot = Bundle.main.resourceURL!.appending(path: "web")
        self.schemeHandler = LocalSchemeHandler(documents: documents, assetsRoot: assetsRoot)
        self.delegate = WebViewDelegate()

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: DocumentService.scheme)
        configuration.websiteDataStore = .nonPersistent()
        configuration.suppressesIncrementalRendering = true
        configuration.userContentController.add(WeakScriptMessageHandler(delegate), name: "cmarks")

        let webView = DocumentWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        // GitHub 배경색. 라이트/다크에 따라 바뀌어 첫 페인트 전 흰 플래시를 막는다.
        webView.underPageBackgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0x0d / 255, green: 0x11 / 255, blue: 0x17 / 255, alpha: 1)
                : .white
        }
        #if DEBUG
        webView.isInspectable = true
        #endif
        self.webView = webView

        delegate.viewer = self
        webView.onDropURLs = { [weak self] urls in self?.onDropURLs?(urls) }
        webView.onBecomeFirstResponder = { [weak self] in self?.onFocus?() }
        webView.onContextAction = { [weak self] action in self?.perform(action) }
        // WebContent 프로세스를 미리 띄워 첫 문서 표시 지연을 줄인다. 배경색은 GitHub 테마와 맞춰 다크 모드에서 흰 플래시가 없다.
        webView.loadHTMLString(Self.warmUpHTML, baseURL: nil)
    }

    // MARK: - 문서 열기

    /// 문서를 연다. `scrollY`가 있으면(탭 전환) 그 위치로, 없으면 이 URL의 마지막 스크롤 위치로 돌아간다. 앵커가 있으면 앵커가 우선.
    func open(_ ref: DocumentRef, scrollY: Double? = nil) {
        let fileURL = ref.url.standardizedFileURL
        let fragment = ref.fragment
        loadTask?.cancel()
        if let previous = currentURL, previous != fileURL {
            scrollPositions[previous] = currentScrollY
        }
        currentURL = fileURL
        pendingFragment = fragment
        pendingScrollY = scrollY
        currentScrollY = scrollY ?? scrollPositions[fileURL] ?? 0
        isPageReady = false
        userScrolledSinceLoad = false
        isFileMissing = false
        state = .loading(fileURL)
        startWatching(fileURL)

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let document = try await documents.render(fileURL)
                guard !Task.isCancelled, currentURL == fileURL else { return }
                stats = RenderStats(document: document)
                outline = []
                activeHeadingID = nil
                webView.load(URLRequest(url: DocumentService.documentURL(for: fileURL, fragment: fragment)))
                state = .loaded(fileURL)
            } catch {
                guard !Task.isCancelled, currentURL == fileURL else { return }
                state = .failed(fileURL, error.localizedDescription)
            }
        }
    }

    /// 문서를 닫고 빈 상태로 돌아간다(Phase 3에서는 탭 닫기가 된다).
    func close() {
        loadTask?.cancel()
        watcher?.stop()
        watcher = nil
        currentURL = nil
        currentTabID = nil
        currentScrollY = 0
        outline = []
        stats = nil
        isFileMissing = false
        isPageReady = false
        hideFindBar()
        state = .empty
        webView.loadHTMLString(Self.warmUpHTML, baseURL: nil)
    }

    /// ⌘R. 캐시를 버리고 다시 렌더하되 스크롤은 유지한다.
    func reload() {
        Task { await reloadInPlace(force: true) }
    }

    /// 파일이 바뀌었을 때. 페이지가 떠 있으면 morph로 제자리 갱신, 아니면 전체 로드.
    func reloadInPlace(force: Bool) async {
        guard let url = currentURL else { return }
        if force { await documents.invalidate(url) }
        do {
            let document = try await documents.render(url)
            guard url == currentURL else { return }
            isFileMissing = false
            guard isPageReady, case .loaded = state else {
                open(DocumentRef(url: url), scrollY: currentScrollY)
                return
            }
            // 같은 mtime·크기·설정이면 내용이 그대로다(xattr 변경 같은 속성 이벤트). 페이지는 이미 그 내용을 보여 주고 있다.
            if document.fromCache, !force { return }
            stats = RenderStats(document: document)
            _ = try await webView.callAsyncJavaScript(
                "return await window.cmarks.morph(html);",
                arguments: ["html": document.bodyHTML],
                contentWorld: .page
            )
        } catch {
            guard url == currentURL else { return }
            if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                isFileMissing = true
                return
            }
            logger.error("reload failed, falling back to full load: \(error.localizedDescription, privacy: .public)")
            open(DocumentRef(url: url), scrollY: currentScrollY)
        }
    }

    func showFailure(_ url: URL, message: String) {
        state = .failed(url, message)
    }

    /// 설정이 바뀌어 다시 렌더해야 할 때. 스크롤은 유지한다.
    func reloadPreservingScroll() {
        guard let url = currentURL else { return }
        open(DocumentRef(url: url), scrollY: currentScrollY)
    }

    /// 다시 렌더할 필요 없는 설정(본문 폭)을 페이지에 바로 반영한다.
    func applyConfig(_ config: [String: Any]) {
        guard isPageReady else { return }
        Task {
            _ = try? await webView.callAsyncJavaScript("window.cmarks.setConfig(config);", arguments: ["config": config], contentWorld: .page)
        }
    }

    // MARK: - 파일 감시(설계 문서 §4.7)

    private func startWatching(_ url: URL) {
        watcher?.stop()
        watcher = FileWatcher(url: url) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFileEvent(event, for: url)
            }
        }
    }

    private func handleFileEvent(_ event: FileWatcher.Event, for url: URL) {
        guard url == currentURL else { return }
        switch event {
        case .disappeared:
            isFileMissing = true
            logger.notice("file disappeared \(url.lastPathComponent, privacy: .public)")
        case .changed:
            guard isLiveReloadEnabled else { return }
            Task { await reloadInPlace(force: false) }
        }
    }

    // MARK: - 컨텍스트 메뉴

    private func perform(_ action: DocumentContextAction) {
        guard let url = currentURL else { return }
        switch action {
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .openInEditor:
            onOpenInEditor?()
        case .copySource:
            guard let data = try? Data(contentsOf: url) else { return }
            let text = TextDecoder.decode(data).text
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    func scrollToHeading(_ id: String) {
        activeHeadingID = id
        Task {
            _ = try? await webView.callAsyncJavaScript("window.cmarks.scrollToAnchor(id);", arguments: ["id": id], contentWorld: .page)
        }
    }

    // MARK: - 찾기

    func showFindBar() {
        isFindBarVisible = true
        findFocusRequest += 1
    }

    func hideFindBar() {
        let hadResults = findCount > 0 || !findQuery.isEmpty
        guard isFindBarVisible || hadResults else { return }
        isFindBarVisible = false
        Task { await clearFind() }
    }

    func performFind() async {
        guard isPageReady, !findQuery.isEmpty else {
            findCount = 0
            findIndex = -1
            if isPageReady { await clearFind() }
            return
        }
        let result = try? await webView.callAsyncJavaScript(
            "return window.cmarks.find.search(query, { caseSensitive: caseSensitive });",
            arguments: ["query": findQuery, "caseSensitive": findCaseSensitive],
            contentWorld: .page
        )
        applyFindResult(result)
    }

    func findNext() async {
        guard findCount > 0 else { await performFind(); return }
        applyFindResult(try? await webView.callAsyncJavaScript("return window.cmarks.find.next();", contentWorld: .page))
    }

    func findPrevious() async {
        guard findCount > 0 else { await performFind(); return }
        applyFindResult(try? await webView.callAsyncJavaScript("return window.cmarks.find.prev();", contentWorld: .page))
    }

    private func clearFind() async {
        _ = try? await webView.callAsyncJavaScript("window.cmarks.find.clear();", contentWorld: .page)
        findCount = 0
        findIndex = -1
    }

    private func applyFindResult(_ result: Any?) {
        let dictionary = result as? [String: Any]
        findCount = dictionary?["count"] as? Int ?? 0
        findIndex = dictionary?["index"] as? Int ?? -1
    }

    // MARK: - 인쇄 / PDF

    func printDocument() {
        guard let window = webView.window else { return }
        let operation = webView.printOperation(with: Self.makePrintInfo())
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    /// PDF 내보내기. NSPrintOperation의 파일 저장은 수십~수백 MB의 손상된 파일을 만들고 멈추는 경우가 있어(CHECKPOINTS C-2.6)
    /// WebKit의 createPDF로 문서 전체를 한 장짜리 PDF로 만든다. 페이지 나눔이 필요하면 인쇄 대화상자(⌥⌘P)의 "PDF로 저장"을 쓴다.
    func exportPDF() {
        guard let url = currentURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + ".pdf"
        panel.directoryURL = url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        Task {
            do {
                let data = try await webView.pdf(configuration: WKPDFConfiguration())
                try data.write(to: destination, options: .atomic)
                logger.notice("pdf exported \(destination.lastPathComponent, privacy: .public) \(data.count) bytes")
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                logger.error("PDF export failed: \(error.localizedDescription, privacy: .public)")
                let alert = NSAlert()
                alert.messageText = String(localized: "PDF를 만들 수 없습니다")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    private static func makePrintInfo() -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        return info
    }

    // MARK: - 브릿지 수신

    fileprivate func receive(_ message: [String: Any]) {
        let reason = message["reason"] as? String
        switch message["type"] as? String {
        case "outline":
            let items = (message["items"] as? [[String: Any]]) ?? []
            outline = items.compactMap { item in
                guard let level = item["level"] as? Int, let text = item["text"] as? String, let id = item["id"] as? String else { return nil }
                return OutlineItem(level: level, text: text, id: id)
            }
        case "ready":
            stats?.jsReadyMS = message["ms"] as? Double
            stats?.codeBlocks = message["codeBlocks"] as? Int ?? 0
            stats?.images = message["images"] as? Int ?? 0
            stats?.headings = message["headings"] as? Int ?? 0
            stats?.changedBlocks = message["changedBlocks"] as? Int
            if reason == "load" {
                isPageReady = true
                restoreScrollIfNeeded()
                if isFindBarVisible { Task { await performFind() } }
            }
            logger.notice("js ready(\(reason ?? "?", privacy: .public)) \(message["ms"] as? Double ?? -1, format: .fixed(precision: 2)) ms")
        case "enhanced":
            stats?.jsEnhancedMS = message["ms"] as? Double
            if reason == "load", !userScrolledSinceLoad { restoreScrollIfNeeded() }
            logger.notice("js enhanced(\(reason ?? "?", privacy: .public)) \(message["ms"] as? Double ?? -1, format: .fixed(precision: 2)) ms")
        case "scroll":
            if let y = message["y"] as? Double, let url = currentURL {
                scrollPositions[url] = y
                currentScrollY = y
                userScrolledSinceLoad = true
            }
            activeHeadingID = message["heading"] as? String
        case "loadFull":
            if let url = currentURL {
                documents.allowFullLoad(url)
                Task { await reloadInPlace(force: true) }
            }
        case "link":
            // ⌘클릭·⌥클릭은 JS가 가로채 보낸다(WebKit은 새 창/다운로드로 처리하려 한다).
            guard let href = message["href"] as? String, let url = URL(string: href) else { return }
            let intent: NavigationIntent = (message["newSplit"] as? Bool ?? false) ? .newSplit(.right)
                : (message["newTab"] as? Bool ?? false) ? .newTab : .sameTab
            handleLink(url, intent: intent)
        case "error":
            logger.error("js error \(String(describing: message["where"]), privacy: .public): \(String(describing: message["message"]), privacy: .public)")
        default:
            break
        }
    }

    /// 앵커 없이 열린 문서는 마지막 스크롤 위치로 돌아간다(뒤로/앞으로, 탭 전환).
    private func restoreScrollIfNeeded() {
        guard pendingFragment == nil, let url = currentURL else { return }
        guard let y = pendingScrollY ?? scrollPositions[url], y > 0 else { return }
        Task {
            _ = try? await webView.callAsyncJavaScript("window.cmarks.scrollTo({ y: y });", arguments: ["y": y], contentWorld: .page)
        }
    }

    // MARK: - 내비게이션 정책(설계 문서 §4.5 링크 표)

    fileprivate func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if action.navigationType != .linkActivated {
            return .allow
        }
        if let target = DocumentService.fileURL(fromDocumentURL: url), target.path == currentURL?.path {
            return .allow // 같은 문서 안의 #앵커
        }
        let intent: NavigationIntent = action.modifierFlags.contains(.option) ? .newSplit(.right)
            : action.modifierFlags.contains(.command) ? .newTab : .sameTab
        handleLink(url, intent: intent)
        return .cancel
    }

    /// 링크 분류(설계 문서 §4.5 표). 마크다운은 앱 안에서, 다른 로컬 파일은 기본 앱, 웹은 브라우저.
    fileprivate func handleLink(_ url: URL, intent: NavigationIntent) {
        logger.notice("link \(url.absoluteString, privacy: .public) intent=\(String(describing: intent), privacy: .public)")
        // cmark는 한글 앵커를 퍼센트 인코딩해 둔다. 디코딩해 두어야 문서 URL을 만들 때 두 번 인코딩되지 않는다.
        let fragment = url.fragment?.removingPercentEncoding ?? url.fragment
        if let target = DocumentService.fileURL(fromDocumentURL: url) {
            if DocumentService.isMarkdown(target) {
                onNavigate?(DocumentRef(url: target.standardizedFileURL, fragment: fragment), intent)
            } else {
                NSWorkspace.shared.open(target)
            }
            return
        }
        if url.isFileURL {
            if DocumentService.isMarkdown(url) {
                onNavigate?(DocumentRef(url: url.standardizedFileURL, fragment: fragment), intent)
            } else {
                NSWorkspace.shared.open(url)
            }
            return
        }
        if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
    }

    fileprivate func navigationFailed(_ error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled, let url = currentURL else { return }
        state = .failed(url, nsError.localizedDescription)
    }

    private static let warmUpHTML = """
    <!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="light dark">
    <style>html{background:#fff}@media (prefers-color-scheme:dark){html{background:#0d1117}}</style></head><body></body></html>
    """
}

// MARK: - WebKit 델리게이트

@MainActor
private final class WebViewDelegate: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var viewer: PaneViewer?

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(viewer?.policy(for: navigationAction) ?? .cancel)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        viewer?.navigationFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        viewer?.navigationFailed(error)
    }

    /// target="_blank"·⌘클릭 등 새 창 요청. 마크다운이면 새 탭, 웹이면 외부 브라우저.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            viewer?.handleLink(url, intent: .newTab)
        }
        return nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        viewer?.receive(body)
    }
}

/// WKUserContentController가 핸들러를 강하게 잡으므로 약한 프록시로 순환 참조를 끊는다.
@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
