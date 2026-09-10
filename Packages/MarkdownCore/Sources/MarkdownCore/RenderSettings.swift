import Foundation

/// 렌더링 옵션(PLAN.md §5.3 렌더링 항목). 캐시 키의 일부이므로 Hashable.
public struct RenderSettings: Hashable, Codable, Sendable {
    public enum FrontMatterDisplay: String, Codable, Sendable {
        case hidden
        case collapsed
    }

    public var math = true
    public var mermaid = true
    public var emoji = true
    public var footnotes = true
    /// raw HTML 통과. GitHub과 같이 tagfilter가 위험 태그를 이스케이프한다.
    public var rawHTML = true
    public var hardBreaks = false
    public var smartPunctuation = false
    public var frontMatter: FrontMatterDisplay = .collapsed
    /// nil이면 창 폭 전체. GitHub 파일 뷰는 980px.
    public var contentMaxWidth: Int? = 980
    /// 이 크기를 넘는 문서는 하이라이팅·수식·다이어그램을 건너뛴다(PLAN.md Phase 5 대용량 정책).
    public var largeDocumentBytes = 2 << 20
    /// 이 크기를 넘는 문서는 앞부분만 보여 주고 "전체 표시" 버튼을 둔다.
    public var hugeDocumentBytes = 5 << 20
    /// 앞부분만 보여 줄 때의 글자 수.
    public var truncatedCharacterCount = 1_000_000

    public init() {}

    /// GitHub 파일 뷰 기본값.
    public static let github = RenderSettings()

    var gfmOptions: GFMRenderer.Options {
        var options: GFMRenderer.Options = [.validateUTF8]
        if rawHTML { options.insert(.unsafe) }
        if footnotes { options.insert(.footnotes) }
        if hardBreaks { options.insert(.hardBreaks) }
        if smartPunctuation { options.insert(.smartPunctuation) }
        return options
    }

    /// web/app.js가 읽는 설정(data-config). 큰 문서면 무거운 후처리를 끈다.
    public func webConfig(isLarge: Bool) -> [String: Any] {
        [
            "math": math && !isLarge,
            "mermaid": mermaid && !isLarge,
            "emoji": emoji,
            "highlight": !isLarge,
            "contentMaxWidth": contentMaxWidth.map { $0 as Any } ?? NSNull(),
        ]
    }
}
