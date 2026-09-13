import Foundation
import MarkdownCore
import Testing
import WebKit
@testable import cmarks

/// Quick Look 확장이 만드는 정적 페이지를 실제 WebKit(WKWebView)에 띄워 스크립트 없이도 하이라이팅·수식·CSS가 그려지는지 본다.
/// (Quick Look 패널 자체는 원격 레이어라 화면 캡처로 검증할 수 없다.)
@MainActor
struct StaticPreviewIntegrationTests {
    @Test func staticPageRendersInWebKitWithoutScripts() async throws {
        let assets = Bundle.main.resourceURL!.appending(path: "web")
        let builder = StaticPreviewBuilder(assetsRoot: assets)
        let markdown = """
        # Title

        Some text with :smile: and math $E = mc^2$.

        ```swift
        let value = 42
        ```

        > [!TIP]
        > Alerts render too.

        | a | b |
        |---|---|
        | 1 | 2 |
        """
        let pipeline = RenderPipeline(assetsBaseURL: URL(string: "cmarks-local://assets/")!)
        let url = URL(fileURLWithPath: "/tmp/static-preview-integration/doc.md")
        var settings = RenderSettings.github
        settings.language = "en"
        let document = try await pipeline.render(fileURL: url, settings: settings) { url in
            RenderPipeline.Input(url: url, data: Data(markdown.utf8), modificationDate: nil)
        }
        let page = builder.page(bodyHTML: document.bodyHTML, title: document.title, documentURL: url, settings: settings) { _ in nil }

        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(false, forKey: "javaScriptEnabled")   // Quick Look처럼 스크립트 없이
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
        let delegate = LoadWaiter()
        webView.navigationDelegate = delegate
        webView.loadHTMLString(page.html, baseURL: nil)
        try await delegate.wait()
        // 검사할 때만 스크립트를 켠다(페이지 자체는 스크립트 없이 로드됐다)
        configuration.preferences.setValue(true, forKey: "javaScriptEnabled")
        let probe = """
        (() => {
          const kw = document.querySelector('.hljs-keyword');
          const katex = document.querySelector('.katex');
          const title = document.querySelector('h1');
          const alert = document.querySelector('.markdown-alert, .markdown-alert-tip');
          const cs = (el) => el ? getComputedStyle(el) : null;
          return {
            scripts: document.scripts.length,
            keywordColor: kw ? cs(kw).color : null,
            titleSize: title ? cs(title).fontSize : null,
            katexHeight: katex ? katex.getBoundingClientRect().height : 0,
            katexFont: katex ? cs(katex.querySelector('.katex-mathml, .katex-html') || katex).fontFamily : null,
            emoji: document.body.textContent.includes('😄'),
            table: !!document.querySelector('table td'),
            alert: !!alert,
            bodyBackground: cs(document.body).backgroundColor,
          };
        })()
        """
        let result = try await webView.evaluateJavaScript(probe) as? [String: Any]
        let info = try #require(result)
        #expect(info["scripts"] as? Int == 0)
        #expect((info["keywordColor"] as? String).map { $0 != "rgb(31, 35, 40)" && $0 != "rgb(0, 0, 0)" } == true, "키워드에 하이라이터 색이 적용되어야 함: \(String(describing: info["keywordColor"]))")
        #expect((info["titleSize"] as? String).map { $0.hasPrefix("32") } == true, "h1 32px(github-markdown.css): \(String(describing: info["titleSize"]))")
        #expect((info["katexHeight"] as? Double ?? 0) > 10)
        #expect(info["emoji"] as? Bool == true)
        #expect(info["table"] as? Bool == true)
        #expect(info["alert"] as? Bool == true)
    }
}

@MainActor
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    func wait() async throws {
        try await withCheckedThrowingContinuation { self.continuation = $0 }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { continuation?.resume(); continuation = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { continuation?.resume(throwing: error); continuation = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { continuation?.resume(throwing: error); continuation = nil }
}
