import Foundation
import JavaScriptCore

/// 스크립트 없이 보이는 정적 페이지(Quick Look 데이터 기반 미리보기용).
/// 앱에서 JS가 하던 일(코드 하이라이팅, KaTeX 수식, 이모지 숏코드)을 JavaScriptCore로 미리 실행해 HTML에 박고,
/// CSS와 폰트를 인라인으로, 문서 옆의 이미지를 첨부(cid:)로 넣는다. Mermaid는 DOM이 필요해 코드 블록으로 남긴다.
public struct StaticPreviewPage: Sendable {
    public var html: String
    /// cid 키 → 첨부. Quick Look의 QLPreviewReply.attachments에 그대로 넣는다.
    public var attachments: [String: StaticAttachment]
}

public struct StaticAttachment: Sendable {
    public var data: Data
    /// UTType identifier (예: public.png)
    public var typeIdentifier: String
    public init(data: Data, typeIdentifier: String) {
        self.data = data
        self.typeIdentifier = typeIdentifier
    }
}

public final class StaticPreviewBuilder: @unchecked Sendable {
    public typealias ImageLoader = (URL) -> StaticAttachment?

    private let assetsRoot: URL
    private let lock = NSLock()
    private var context: JSContext?
    private var loadedLanguages: Set<String> = []
    private var katexLoaded = false
    private var emojiTable: [String: String]?
    private var baseCSS: String?
    private var katexCSS: String?

    public init(assetsRoot: URL) {
        self.assetsRoot = assetsRoot
    }

    // MARK: 페이지

    public func page(bodyHTML: String, title: String, documentURL: URL, settings: RenderSettings, isLarge: Bool = false, imageLoader: ImageLoader) -> StaticPreviewPage {
        lock.lock(); defer { lock.unlock() }
        var usedMath = false
        var html = transformCodeBlocks(bodyHTML, settings: settings, isLarge: isLarge, usedMath: &usedMath)
        if settings.math, !isLarge {
            html = transformText(html) { [self] text in renderInlineMath(text, usedMath: &usedMath) }
        }
        if settings.emoji {
            html = transformText(html) { [self] text in replaceEmoji(text) }
        }
        var attachments: [String: StaticAttachment] = [:]
        html = embedImages(html, documentURL: documentURL, loader: imageLoader, attachments: &attachments)

        var css = loadBaseCSS()
        if usedMath { css += loadKaTeXCSS() }
        let width = settings.contentMaxWidth.map { ".markdown-body{max-width:\($0)px}" } ?? ".markdown-body{max-width:none}"
        let page = """
        <!doctype html>
        <html lang="\(HTMLTemplate.escapeAttribute(settings.language))">
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <title>\(HTMLTemplate.escapeText(title))</title>
        <style>\(css)</style>
        <style>\(width)</style>
        </head>
        <body>
        <article class="markdown-body\(isLarge ? " cmarks-large" : "")" id="doc">
        \(html)
        </article>
        </body>
        </html>
        """
        return StaticPreviewPage(html: page, attachments: attachments)
    }

    // MARK: 코드 블록 (하이라이팅 · 수식 블록 · mermaid)

    private static let codeBlock = try! NSRegularExpression(pattern: #"<pre(?: lang="[^"]*")?><code class="language-([A-Za-z0-9_+#.-]+)"[^>]*>([\s\S]*?)</code></pre>"#)

    private func transformCodeBlocks(_ html: String, settings: RenderSettings, isLarge: Bool, usedMath: inout Bool) -> String {
        let ns = html as NSString
        var out = ""
        var cursor = 0
        for match in Self.codeBlock.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let lang = ns.substring(with: match.range(at: 1)).lowercased()
            let escaped = ns.substring(with: match.range(at: 2))
            let source = Self.unescapeEntities(escaped)
            let original = ns.substring(with: match.range)
            switch lang {
            case "math" where settings.math && !isLarge:
                usedMath = true
                out += "<div class=\"cmarks-math-block\">\(renderKaTeX(source, display: true))</div>"
            case "mermaid":
                let note = settings.language.lowercased().hasPrefix("en") ? "Mermaid diagram — open in cmarks to render it." : "Mermaid 다이어그램 — cmarks에서 열면 그려집니다."
                out += original + "<p class=\"cmarks-static-note\">\(note)</p>"
            default:
                if isLarge { out += original; break }
                if let value = highlight(source, language: lang) {
                    out += "<pre><code class=\"hljs language-\(lang)\">\(value)</code></pre>"
                } else {
                    out += original
                }
            }
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    // MARK: 텍스트 구간 변환 (태그·코드·링크 밖의 텍스트에만)

    private static let tag = try! NSRegularExpression(pattern: #"<(/?)([A-Za-z][A-Za-z0-9]*)[^>]*>"#)
    private static let skippedTags: Set<String> = ["pre", "code", "a", "kbd", "script", "style", "textarea", "svg", "math"]

    private func transformText(_ html: String, _ transform: (String) -> String) -> String {
        let ns = html as NSString
        var out = ""
        var cursor = 0
        var skipDepth = 0
        for match in Self.tag.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let text = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out += skipDepth == 0 ? transform(text) : text
            let closing = match.range(at: 1).length > 0
            let name = ns.substring(with: match.range(at: 2)).lowercased()
            if Self.skippedTags.contains(name) {
                let selfClosing = ns.substring(with: match.range).hasSuffix("/>")
                if closing { skipDepth = max(0, skipDepth - 1) } else if !selfClosing { skipDepth += 1 }
            }
            out += ns.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        let tail = ns.substring(from: cursor)
        out += skipDepth == 0 ? transform(tail) : tail
        return out
    }

    // MARK: 수식

    private static let mathPattern = try! NSRegularExpression(pattern: #"\$\$([\s\S]+?)\$\$|\$([^\s$][^$\n]*?)\$"#)

    private func renderInlineMath(_ text: String, usedMath: inout Bool) -> String {
        guard text.contains("$") else { return text }
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for match in Self.mathPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let display = match.range(at: 1).location != NSNotFound
            let raw = ns.substring(with: display ? match.range(at: 1) : match.range(at: 2))
            usedMath = true
            out += renderKaTeX(Self.unescapeEntities(raw), display: display)
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    private func renderKaTeX(_ source: String, display: Bool) -> String {
        let ctx = jsContext()
        if !katexLoaded {
            evaluate(file: "vendor/katex/katex.min.js", in: ctx)
            katexLoaded = true
        }
        guard let katex = ctx.objectForKeyedSubscript("katex"), !katex.isUndefined,
              let result = katex.invokeMethod("renderToString", withArguments: [source, ["displayMode": display, "throwOnError": false]]),
              !result.isUndefined else {
            return "<code>\(HTMLTemplate.escapeText(source))</code>"
        }
        return result.toString()
    }

    // MARK: 하이라이팅

    private func highlight(_ source: String, language: String) -> String? {
        let ctx = jsContext()
        guard let hljs = ctx.objectForKeyedSubscript("hljs"), !hljs.isUndefined else { return nil }
        func known() -> Bool {
            guard let value = hljs.invokeMethod("getLanguage", withArguments: [language]) else { return false }
            return !value.isUndefined && !value.isNull
        }
        if !known(), !loadedLanguages.contains(language) {
            loadedLanguages.insert(language)
            evaluate(file: "vendor/hljs/languages/\(language).min.js", in: ctx)
        }
        guard known(),
              let result = hljs.invokeMethod("highlight", withArguments: [source, ["language": language, "ignoreIllegals": true]]),
              let value = result.forProperty("value"), !value.isUndefined else { return nil }
        return value.toString()
    }

    // MARK: 이모지

    private static let shortcode = try! NSRegularExpression(pattern: #":([a-z0-9_+-]+):"#)

    private func replaceEmoji(_ text: String) -> String {
        guard text.contains(":") else { return text }
        let table = loadEmojiTable()
        guard !table.isEmpty else { return text }
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for match in Self.shortcode.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1))
            guard let emoji = table[name] else { continue }
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out += emoji
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    private func loadEmojiTable() -> [String: String] {
        if let emojiTable { return emojiTable }
        var table: [String: String] = [:]
        if let source = try? String(contentsOf: assetsRoot.appending(path: "vendor/emoji.js"), encoding: .utf8),
           let start = source.firstIndex(of: "{"), let end = source.lastIndex(of: "}"),
           let object = try? JSONSerialization.jsonObject(with: Data(source[start...end].utf8)) as? [String: String] {
            table = object
        }
        emojiTable = table
        return table
    }

    // MARK: 이미지 첨부

    private static let image = try! NSRegularExpression(pattern: #"<img\b([^>]*?)\bsrc="([^"]+)""#)

    private func embedImages(_ html: String, documentURL: URL, loader: ImageLoader, attachments: inout [String: StaticAttachment]) -> String {
        let ns = html as NSString
        var out = ""
        var cursor = 0
        let base = documentURL.deletingLastPathComponent()
        for match in Self.image.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let src = Self.unescapeEntities(ns.substring(with: match.range(at: 2)))
            let lower = src.lowercased()
            guard !lower.hasPrefix("http:"), !lower.hasPrefix("https:"), !lower.hasPrefix("data:"), !lower.hasPrefix("cid:") else { continue }
            let fileURL: URL
            if lower.hasPrefix("file:") {
                guard let url = URL(string: src) else { continue }
                fileURL = url
            } else if src.hasPrefix("/") {
                fileURL = URL(fileURLWithPath: src)
            } else {
                fileURL = base.appending(path: src.removingPercentEncoding ?? src)
            }
            guard let attachment = loader(fileURL.standardizedFileURL) else { continue }
            let key = "img\(attachments.count + 1)"
            attachments[key] = attachment
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out += "<img\(ns.substring(with: match.range(at: 1)))src=\"cid:\(key)\""
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    // MARK: CSS

    private func loadBaseCSS() -> String {
        if let baseCSS { return baseCSS }
        func read(_ rel: String) -> String { (try? String(contentsOf: assetsRoot.appending(path: rel), encoding: .utf8)) ?? "" }
        var css = read("vendor/github-markdown.css")
        css += "@media (prefers-color-scheme: light){\(read("vendor/hljs/github.min.css"))}"
        css += "@media (prefers-color-scheme: dark){\(read("vendor/hljs/github-dark.min.css"))}"
        css += read("app.css")
        css += """
        body{margin:0;background:#fff}@media (prefers-color-scheme: dark){body{background:#0d1117}}
        .markdown-body{box-sizing:border-box;min-width:200px;margin:0 auto;padding:32px 40px}
        .cmarks-math-block{overflow-x:auto;margin:0 0 16px}
        .cmarks-static-note{font-size:12px;color:#59636e;margin:-8px 0 16px}
        .cmarks-frontmatter{margin:0 0 16px}
        """
        baseCSS = css
        return css
    }

    private static let fontSource = try! NSRegularExpression(pattern: #"url\(fonts/([^)]+)\.woff2\) format\("woff2"\),url\(fonts/[^)]+\.woff\) format\("woff"\),url\(fonts/[^)]+\.ttf\) format\("truetype"\)"#)

    /// KaTeX CSS의 폰트를 data: URI로 바꿔 넣는다(woff2만). 수식이 있는 문서에서만 쓴다.
    private func loadKaTeXCSS() -> String {
        if let katexCSS { return katexCSS }
        guard var css = try? String(contentsOf: assetsRoot.appending(path: "vendor/katex/katex.min.css"), encoding: .utf8) else { return "" }
        let ns = css as NSString
        var out = ""
        var cursor = 0
        for match in Self.fontSource.matches(in: css, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let name = ns.substring(with: match.range(at: 1))
            if let data = try? Data(contentsOf: assetsRoot.appending(path: "vendor/katex/fonts/\(name).woff2")) {
                out += "url(data:font/woff2;base64,\(data.base64EncodedString())) format(\"woff2\")"
            } else {
                out += ns.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        css = out
        katexCSS = css
        return css
    }

    // MARK: JavaScriptCore

    private func jsContext() -> JSContext {
        if let context { return context }
        let ctx = JSContext()!
        ctx.evaluateScript("var window = this; var self = this; var globalThis = this;")
        evaluate(file: "vendor/hljs/highlight.min.js", in: ctx)
        context = ctx
        return ctx
    }

    private func evaluate(file rel: String, in ctx: JSContext) {
        let url = assetsRoot.appending(path: rel)
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return }
        ctx.evaluateScript(source, withSourceURL: url)
    }

    // MARK: 엔티티

    static func unescapeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
        for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        if out.contains("&#") {
            let numeric = try! NSRegularExpression(pattern: #"&#(x?)([0-9A-Fa-f]+);"#)
            let ns = out as NSString
            var result = ""
            var cursor = 0
            for match in numeric.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                let hex = match.range(at: 1).length > 0
                let digits = ns.substring(with: match.range(at: 2))
                if let value = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(value) {
                    result.unicodeScalars.append(scalar)
                } else {
                    result += ns.substring(with: match.range)
                }
                cursor = match.range.location + match.range.length
            }
            result += ns.substring(from: cursor)
            out = result
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }
}
