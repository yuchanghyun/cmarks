import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// cmark-gfm으로 Markdown을 HTML 조각으로 바꾼다. GitHub 파일 뷰와 같은 확장/옵션 조합(설계 문서 §4.3).
/// 헤딩 앵커, 알림, 이모지 등 DOM 후처리는 web/app.js가 맡는다.
public struct GFMRenderer: Sendable {
    /// GitHub이 켜는 확장. `tagfilter`는 raw HTML을 허용하면서 script/iframe 등 위험 태그만 이스케이프한다.
    public static let extensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]

    public struct Options: OptionSet, Sendable {
        public let rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }

        /// raw HTML 통과(GitHub과 동일). tagfilter와 함께 쓴다.
        public static let unsafe = Options(rawValue: CMARK_OPT_UNSAFE)
        public static let footnotes = Options(rawValue: CMARK_OPT_FOOTNOTES)
        public static let validateUTF8 = Options(rawValue: CMARK_OPT_VALIDATE_UTF8)
        public static let smartPunctuation = Options(rawValue: CMARK_OPT_SMART)
        public static let hardBreaks = Options(rawValue: CMARK_OPT_HARDBREAKS)

        /// GitHub 파일 뷰 기본값: smart/hardbreaks 없음.
        public static let github: Options = [.unsafe, .footnotes, .validateUTF8]
    }

    public var options: Options

    public init(options: Options = .github) {
        self.options = options
    }

    public func renderHTML(_ markdown: String) -> String {
        _ = Self.extensionRegistration

        guard let parser = cmark_parser_new(options.rawValue) else { return "" }
        defer { cmark_parser_free(parser) }

        for name in Self.extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        markdown.utf8CString.withUnsafeBufferPointer { buffer in
            // utf8CString은 널 종료 포함. 마지막 널은 넘기지 않는다.
            cmark_parser_feed(parser, buffer.baseAddress, buffer.count - 1)
        }

        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }

        guard let html = cmark_render_html(document, options.rawValue, cmark_parser_get_syntax_extensions(parser)) else {
            return ""
        }
        defer { free(html) }
        return String(cString: html)
    }

    /// 프로세스당 한 번만 실행되어야 하는 확장 등록. static let 초기화는 스레드 안전하다.
    private static let extensionRegistration: Void = {
        cmark_gfm_core_extensions_ensure_registered()
    }()
}
