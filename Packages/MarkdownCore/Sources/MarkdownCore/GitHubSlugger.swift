import Foundation

/// GitHub 헤딩 앵커 알고리즘(github-slugger와 동일). web/src/slugger.js와 같은 테스트 벡터를 통과해야 한다.
/// 소문자화 → 글자(L)·숫자(N)·결합 기호(M)·공백·`-`·`_` 외 제거 → 공백을 `-`로.
public struct GitHubSlugger: Sendable {
    private var occurrences: [String: Int] = [:]

    public init() {}

    public static func slug(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            if scalar == " " {
                result.append("-")
                continue
            }
            if scalar == "-" || scalar == "_" {
                result.append(scalar)
                continue
            }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber,
                 .nonspacingMark, .spacingMark, .enclosingMark:
                result.append(scalar)
            default:
                continue
            }
        }
        return String(result)
    }

    /// 같은 문서 안에서 중복되는 슬러그에 -1, -2… 를 붙인다.
    public mutating func uniqueSlug(_ text: String) -> String {
        let base = Self.slug(text)
        var result = base
        while occurrences[result] != nil {
            occurrences[base, default: 0] += 1
            result = "\(base)-\(occurrences[base]!)"
        }
        occurrences[result] = 0
        return result
    }
}
