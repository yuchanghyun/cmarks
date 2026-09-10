import SwiftUI
import WebKit

/// PaneViewer가 소유한 WKWebView를 SwiftUI에 붙인다. 뷰 트리가 바뀌어도 웹뷰는 재생성되지 않는다.
struct WebViewHost: NSViewRepresentable {
    let webView: DocumentWebView

    func makeNSView(context: Context) -> DocumentWebView {
        webView
    }

    func updateNSView(_ nsView: DocumentWebView, context: Context) {}
}
