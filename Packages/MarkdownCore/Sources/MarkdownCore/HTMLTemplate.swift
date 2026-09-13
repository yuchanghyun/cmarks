import Foundation

/// 렌더된 본문을 전체 페이지로 감싼다. CSS/JS는 앱 번들에서 커스텀 스킴으로 서빙된다(설계 문서 §4.4).
public struct HTMLTemplate: Sendable {
    public var assetsBaseURL: URL

    public init(assetsBaseURL: URL) {
        self.assetsBaseURL = assetsBaseURL
    }

    public func page(bodyHTML: String, documentPath: String, title: String, settings: RenderSettings, includeEmojiTable: Bool = false, isLarge: Bool = false) -> String {
        let assets = assetsBaseURL.absoluteString.hasSuffix("/") ? assetsBaseURL.absoluteString : assetsBaseURL.absoluteString + "/"
        let assetsOrigin = assets.hasSuffix("/") ? String(assets.dropLast()) : assets
        let scheme = assetsBaseURL.scheme ?? "cmarks-local"
        let csp = [
            "default-src 'none'",
            "script-src \(assetsOrigin)",
            "style-src \(assetsOrigin) 'unsafe-inline'",
            "img-src \(scheme): data: https: http:",
            "media-src \(scheme): https: http:",
            "font-src \(assetsOrigin)",
            "base-uri 'none'",
            "form-action 'none'",
        ].joined(separator: "; ")

        let config = Self.jsonString(settings.webConfig(isLarge: isLarge))
        let widthStyle = settings.contentMaxWidth.map { "<style>.markdown-body{max-width:\($0)px}</style>" } ?? "<style>.markdown-body{max-width:none}</style>"
        let userStyle = settings.customCSS.isEmpty ? "" : "<style id=\"cmarks-user-css\">\(Self.escapeCSS(settings.customCSS))</style>"

        return """
        <!doctype html>
        <html lang="\(Self.escapeAttribute(settings.language))" data-config="\(Self.escapeAttribute(config))">
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <title>\(Self.escapeText(title))</title>
        <link rel="stylesheet" href="\(assets)vendor/github-markdown.css">
        <link rel="stylesheet" href="\(assets)vendor/hljs/github.min.css" media="(prefers-color-scheme: light)">
        <link rel="stylesheet" href="\(assets)vendor/hljs/github-dark.min.css" media="(prefers-color-scheme: dark)">
        <link rel="stylesheet" href="\(assets)app.css">
        \(widthStyle)
        \(userStyle)
        </head>
        <body>
        <article class="markdown-body\(isLarge ? " cmarks-large" : "")" id="doc" data-document-path="\(Self.escapeAttribute(documentPath))">
        \(bodyHTML)
        </article>
        <script src="\(assets)vendor/hljs/highlight.min.js" defer></script>
        \(includeEmojiTable ? "<script src=\"\(assets)vendor/emoji.js\" defer></script>" : "")
        <script src="\(assets)app.js" defer></script>
        </body>
        </html>
        """
    }

    /// 큰 문서 안내. 버튼의 동작은 app.js가 붙인다(CSP로 인라인 스크립트 불가). 문구는 설정 언어를 따른다.
    public static func largeDocumentBanner(byteCount: Int, truncatedTo characters: Int?, language: String = "ko") -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        let english = language.lowercased().hasPrefix("en")
        if let characters {
            let count = characters.formatted()
            let text = english
                ? "This document is \(size), so only the first \(count) characters are shown. Code highlighting, math and diagrams are skipped."
                : "문서가 \(size)로 커서 앞부분 \(count)자만 표시했습니다. 코드 하이라이팅·수식·다이어그램도 생략했습니다."
            let button = english ? "Show All" : "전체 표시"
            return """
            <div class="cmarks-banner" role="status">\(text) <button type="button" id="cmarks-load-full">\(button)</button></div>

            """
        }
        let text = english
            ? "This document is \(size), so code highlighting, math and diagrams are skipped."
            : "문서가 \(size)로 커서 코드 하이라이팅·수식·다이어그램을 생략했습니다."
        return """
        <div class="cmarks-banner" role="status">\(text)</div>

        """
    }

    /// 프런트매터를 접힌 블록으로. GitHub 파일 뷰의 표 표시는 Phase 5 설정에서 다룬다.
    public static func frontMatterHTML(_ frontMatter: FrontMatter) -> String {
        """
        <details class="cmarks-frontmatter"><summary>Front matter</summary>
        <pre><code class="language-\(frontMatter.format.rawValue)">\(escapeText(frontMatter.raw))
        </code></pre></details>

        """
    }

    public static func escapeText(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(ch)
            }
        }
        return out
    }

    /// 사용자 CSS 안의 `</style>`가 스타일 블록을 끊지 못하게 한다.
    public static func escapeCSS(_ css: String) -> String {
        css.replacingOccurrences(of: "</", with: "<\\/")
    }

    public static func escapeAttribute(_ text: String) -> String {
        escapeText(text).replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func jsonString(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
