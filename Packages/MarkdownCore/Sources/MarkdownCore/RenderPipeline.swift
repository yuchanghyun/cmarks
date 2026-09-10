import Foundation

public struct RenderedDocument: Sendable {
    public var url: URL
    public var pageHTML: String
    /// `<article>` 안쪽만. 라이브 리로드(morph)에 쓴다.
    public var bodyHTML: String
    public var title: String
    public var frontMatter: FrontMatter?
    public var encoding: String.Encoding
    public var byteCount: Int
    public var renderDuration: Duration
    public var fromCache: Bool
    /// 앞부분만 보여 주고 있다(대용량 정책).
    public var isTruncated = false
    /// 하이라이팅 등 무거운 후처리를 건너뛰었다.
    public var isLarge = false
}

/// 파일 읽기 → 디코딩 → 프런트매터 분리 → cmark-gfm → 페이지 합성 → 캐시.
/// 액터이므로 읽기와 파싱이 메인 스레드 밖에서 돈다. 결과는 값 타입으로 넘어간다.
public actor RenderPipeline {
    public struct Input: Sendable {
        public var url: URL
        public var data: Data
        public var modificationDate: Date?

        public init(url: URL, data: Data, modificationDate: Date?) {
            self.url = url
            self.data = data
            self.modificationDate = modificationDate
        }
    }

    public typealias Reader = @Sendable (URL) throws -> Input

    private var cache: RenderCache
    private let template: HTMLTemplate

    public init(assetsBaseURL: URL, cacheBytes: Int = 50 << 20) {
        self.template = HTMLTemplate(assetsBaseURL: assetsBaseURL)
        self.cache = RenderCache(maxBytes: cacheBytes)
    }

    /// reader는 이 액터의 실행기에서 호출된다(파일 읽기도 메인 밖).
    public func render(fileURL: URL, settings: RenderSettings, reader: Reader) throws -> RenderedDocument {
        let input = try reader(fileURL)
        return render(input, settings: settings)
    }

    public func render(_ input: Input, settings: RenderSettings) -> RenderedDocument {
        let key = RenderCacheKey(path: input.url.path, modificationDate: input.modificationDate, size: input.data.count, settings: settings)
        if var hit = cache.value(for: key) {
            hit.fromCache = true
            return hit
        }

        let clock = ContinuousClock()
        let start = clock.now

        let decoded = TextDecoder.decode(input.data)
        var text = TextDecoder.normalizeNewlines(decoded.text)
        let isLarge = input.data.count > settings.largeDocumentBytes
        let isHuge = input.data.count > settings.hugeDocumentBytes
        var truncatedTo: Int?
        if isHuge {
            text = Self.truncate(text, to: settings.truncatedCharacterCount)
            truncatedTo = settings.truncatedCharacterCount
        }
        let (frontMatter, body) = FrontMatterParser.split(text)

        var bodyHTML = GFMRenderer(options: settings.gfmOptions).renderHTML(body)
        if let frontMatter, settings.frontMatter == .collapsed {
            bodyHTML = HTMLTemplate.frontMatterHTML(frontMatter) + bodyHTML
        }
        if isLarge {
            bodyHTML = HTMLTemplate.largeDocumentBanner(byteCount: input.data.count, truncatedTo: truncatedTo) + bodyHTML
        }

        let title = input.url.lastPathComponent
        let includeEmoji = settings.emoji && Self.containsShortcode(bodyHTML)
        let page = template.page(bodyHTML: bodyHTML, documentPath: input.url.path, title: title, settings: settings, includeEmojiTable: includeEmoji, isLarge: isLarge)

        let document = RenderedDocument(
            url: input.url,
            pageHTML: page,
            bodyHTML: bodyHTML,
            title: title,
            frontMatter: frontMatter,
            encoding: decoded.encoding,
            byteCount: input.data.count,
            renderDuration: clock.now - start,
            fromCache: false,
            isTruncated: isHuge,
            isLarge: isLarge
        )
        cache.insert(document, for: key)
        return document
    }

    /// 글자 수 기준으로 자르되 줄 끝에서 끊는다.
    static func truncate(_ text: String, to characters: Int) -> String {
        guard text.count > characters else { return text }
        let cut = text.index(text.startIndex, offsetBy: characters)
        if let newline = text[..<cut].lastIndex(of: "\n") {
            return String(text[..<newline]) + "\n"
        }
        return String(text[..<cut])
    }

    /// `:shortcode:` 후보가 있는지. 있을 때만 42KB 이모지 표를 페이지에 미리 싣는다.
    static func containsShortcode(_ html: String) -> Bool {
        html.range(of: ":[a-z0-9_+-]+:", options: [.regularExpression, .caseInsensitive]) != nil
    }

    public func invalidate(path: String) {
        cache.removeAll(path: path)
    }

    public var cachedCount: Int { cache.count }
}
