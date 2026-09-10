import Foundation

public struct FrontMatter: Equatable, Sendable {
    public enum Format: String, Sendable {
        case yaml
        case toml
    }

    public var format: Format
    /// 펜스 사이 원문(펜스 제외).
    public var raw: String

    public init(format: Format, raw: String) {
        self.format = format
        self.raw = raw
    }
}

/// 문서 맨 앞의 `---`(YAML) 또는 `+++`(TOML) 블록을 분리한다.
/// 닫는 펜스가 없으면 프런트매터가 아니다(GitHub과 동일하게 수평선으로 렌더링된다).
public enum FrontMatterParser {
    public static func split(_ text: String) -> (frontMatter: FrontMatter?, body: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return (nil, text) }

        let marker = first.trimmingCharacters(in: .whitespaces)
        let format: FrontMatter.Format
        switch marker {
        case "---": format = .yaml
        case "+++": format = .toml
        default: return (nil, text)
        }

        for index in 1..<lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            let closes = line == marker || (format == .yaml && line == "...")
            guard closes else { continue }
            let raw = lines[1..<index].joined(separator: "\n")
            let body = lines[(index + 1)...].joined(separator: "\n")
            return (FrontMatter(format: format, raw: raw), body)
        }
        return (nil, text)
    }
}
