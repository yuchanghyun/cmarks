import Foundation
import Testing
@testable import cmarks

/// 영어 지역화 완전성. 카탈로그의 모든 키에 영어가 있고, 소스의 한글 문자열 리터럴이 카탈로그에 빠지지 않았는지 검사한다.
struct LocalizationTests {
    static let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    static func catalogKeys() throws -> [String: String] {
        let url = repoRoot.appending(path: "App/Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let strings = json["strings"] as! [String: Any]
        var result: [String: String] = [:]
        for (key, value) in strings {
            let unit = ((value as? [String: Any])?["localizations"] as? [String: Any])?["en"] as? [String: Any]
            result[key] = (unit?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
        }
        return result
    }

    /// 컴파일러가 실제로 지역화 키로 추출한 문자열(.stringsdata). 빌드 산출물이 없으면 nil.
    static func compilerExtractedKeys() throws -> Set<String>? {
        let root = repoRoot.appending(path: "build/Build/Intermediates.noindex/cmarks.build/Debug/cmarks.build/Objects-normal")
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        var keys: Set<String> = []
        for case let url as URL in files where url.pathExtension == "stringsdata" {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            for entry in ((json?["tables"] as? [String: Any])?["Localizable"] as? [[String: Any]]) ?? [] {
                if let key = entry["key"] as? String { keys.insert(key) }
            }
        }
        return keys.isEmpty ? nil : keys
    }

    @Test func everyCatalogKeyHasEnglish() throws {
        let catalog = try Self.catalogKeys()
        #expect(catalog.count > 150)
        for (key, english) in catalog {
            #expect(!english.isEmpty, "영어 없음: \(key)")
            // 서식 지정자는 그대로 유지되어야 한다
            for token in ["%lld", "%@", "%.1f"] where key.contains(token) {
                #expect(english.contains(token), "\(key) → \(english) 에 \(token) 없음")
            }
        }
    }

    @Test func compiledEnglishBundleResolvesEveryKey() throws {
        let catalog = try Self.catalogKeys()
        let path = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let english = try #require(Bundle(path: path))
        let sentinel = "<<missing>>"
        for (key, expected) in catalog {
            let value = english.localizedString(forKey: key, value: sentinel, table: nil)
            #expect(value == expected, "\(key): 컴파일된 값 \(value) ≠ \(expected)")
        }
        #expect(english.localizedString(forKey: "cmarks로 열기", value: sentinel, table: "ServicesMenu") == "Open in cmarks")
    }

    /// 새 UI 문자열을 추가하면 카탈로그에도 넣어야 한다. 주석과 보간 문자열은 건너뛴다.
    @Test func koreanLiteralsInSourcesAreLocalized() throws {
        let catalog = try Self.catalogKeys()
        let sources = try FileManager.default.subpathsOfDirectory(atPath: Self.repoRoot.appending(path: "App/Sources").path)
            .filter { $0.hasSuffix(".swift") }
        let literal = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*[가-힣](?:[^"\\]|\\.)*)""#)
        let extracted = try Self.compilerExtractedKeys()
        var missing: Set<String> = []
        var notExtracted: Set<String> = []
        for file in sources {
            let text = try String(contentsOf: Self.repoRoot.appending(path: "App/Sources/\(file)"), encoding: .utf8)
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                let code = String(trimmed.split(separator: "//", maxSplits: 1).first ?? "")
                for match in literal.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                    let value = String(code[Range(match.range(at: 1), in: code)!])
                    if value.contains("\\(") { continue } // 보간은 컴파일러가 서식 키로 추출한다
                    if value.hasPrefix("subsystem") || value.contains("privacy") { continue }
                    if catalog[value] == nil { missing.insert("\(file): \(value)") }
                    // 단축키 표는 String 튜플을 LocalizedStringKey로 조회하므로 컴파일러 추출 대상이 아니다
                    if let extracted, !file.hasSuffix("ShortcutHelpView.swift"), !extracted.contains(value) {
                        notExtracted.insert("\(file): \(value)")
                    }
                }
            }
        }
        #expect(missing.isEmpty, "카탈로그에 없는 한글 리터럴: \(missing.sorted())")
        // 삼항식 안의 리터럴처럼 String으로 추론되어 지역화를 건너뛰는 경우를 잡는다
        #expect(notExtracted.isEmpty, "지역화 키로 추출되지 않은 리터럴: \(notExtracted.sorted())")
    }
}
