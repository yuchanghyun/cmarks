import Foundation
import Testing
@testable import cmarks

struct ProblemReporterTests {
    static let env = ProblemReporter.Environment(
        appVersion: "1.1.1", build: "4", macOS: "macOS 26.6.2 (25G83)", model: "MacBookPro18,2",
        architecture: "arm64", installSource: "DMG", language: "en")

    @Test func issueURLPrefillsTheForm() throws {
        let url = ProblemReporter.issueURL(environment: Self.env)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "github.com")
        #expect(components.path == "/yuchanghyun/cmarks/issues/new")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query["template"] == "bug_report.yml")
        #expect(query["version"] == "1.1.1 (4)")
        #expect(query["macos"] == "macOS 26.6.2 (25G83), MacBookPro18,2, arm64")
        #expect(query["install"] == "DMG")
    }

    @Test func diagnosticsIncludeEnvironmentSettingsAndLog() {
        let text = ProblemReporter.diagnostics(environment: Self.env, settingsSummary: "math=on", recentLog: ["12:00:00.000 [app] hello"])
        #expect(text.hasPrefix("```text\n"))
        #expect(text.contains("cmarks 1.1.1 (4)"))
        #expect(text.contains("MacBookPro18,2"))
        #expect(text.contains("Install: DMG · Language: en"))
        #expect(text.contains("Settings: math=on"))
        #expect(text.contains("[app] hello"))
        #expect(text.hasSuffix("\n```"))
    }

    @Test func currentEnvironmentReadsTheBundle() {
        let env = ProblemReporter.currentEnvironment()
        #expect(!env.appVersion.isEmpty && env.appVersion != "?")
        #expect(env.macOS.hasPrefix("macOS "))
        #expect(["DMG", "Homebrew", "Built from source"].contains(env.installSource))
        // 테스트 호스트는 DerivedData에서 실행된다
        #expect(env.installSource == "Built from source")
    }

    @Test func recentLogDoesNotThrow() {
        let lines = ProblemReporter.recentLogLines(limit: 5)
        #expect(lines.count <= 5)
    }
}
