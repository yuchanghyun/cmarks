import AppKit
import Foundation
import OSLog

/// 도움말 ▸ 문제 신고…. 진단 정보(버전, macOS, 설치 경로, 설정, 이번 실행의 최근 로그)를 클립보드에 복사하고
/// GitHub 이슈 양식(.github/ISSUE_TEMPLATE/bug_report.yml)을 버전·macOS·설치 방법이 채워진 채로 연다.
nonisolated enum ProblemReporter {
    nonisolated static let repository = "yuchanghyun/cmarks"
    nonisolated static let subsystem = "com.changhyunyoo.cmarks"

    nonisolated struct Environment: Sendable {
        var appVersion: String
        var build: String
        var macOS: String
        var model: String
        var architecture: String
        /// bug_report.yml 드롭다운 값과 같아야 한다: DMG · Homebrew · Built from source
        var installSource: String
        var language: String
    }

    nonisolated static func currentEnvironment(bundle: Bundle = .main) -> Environment {
        let info = bundle.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var arch = "arm64"
        #if arch(x86_64)
        arch = "x86_64"
        #endif
        if sysctlInt("sysctl.proc_translated") == 1 { arch += " (Rosetta)" }
        let path = bundle.bundlePath
        let install: String
        if FolderAccess.isSandboxed {
            install = "App Store"
        } else if ["/opt/homebrew/Caskroom/cmarks", "/usr/local/Caskroom/cmarks"].contains(where: { FileManager.default.fileExists(atPath: $0) }) {
            install = "Homebrew"
        } else if path.hasPrefix("/Applications/") {
            install = "DMG"
        } else {
            install = "Built from source"
        }
        return Environment(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?",
            macOS: "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) (\(sysctlString("kern.osversion") ?? "?"))",
            model: sysctlString("hw.model") ?? "?",
            architecture: arch,
            installSource: install,
            language: bundle.preferredLocalizations.first ?? "?"
        )
    }

    /// 이슈 양식의 입력란(id: version, macos, install)을 미리 채운 주소.
    nonisolated static func issueURL(environment env: Environment) -> URL {
        var components = URLComponents(string: "https://github.com/\(repository)/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "version", value: "\(env.appVersion) (\(env.build))"),
            URLQueryItem(name: "macos", value: "\(env.macOS), \(env.model), \(env.architecture)"),
            URLQueryItem(name: "install", value: env.installSource),
        ]
        return components.url!
    }

    /// 이슈에 붙여 넣을 진단 블록.
    nonisolated static func diagnostics(environment env: Environment, settingsSummary: String, recentLog: [String]) -> String {
        var lines = [
            "cmarks \(env.appVersion) (\(env.build))",
            "\(env.macOS) · \(env.model) · \(env.architecture)",
            "Install: \(env.installSource) · Language: \(env.language)",
            "Settings: \(settingsSummary)",
        ]
        if !recentLog.isEmpty {
            lines.append("Recent log (this session, last \(recentLog.count) entries):")
            lines.append(contentsOf: recentLog)
        }
        return "```text\n" + lines.joined(separator: "\n") + "\n```"
    }

    /// 이번 실행에서 남긴 앱 로그(최근 10분, 최대 80줄). 실패하면 빈 배열.
    nonisolated static func recentLogLines(limit: Int = 80) -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }
        let position = store.position(timeIntervalSinceEnd: -600)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        guard let entries = try? store.getEntries(at: position, matching: predicate) else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        var lines: [String] = []
        for case let entry as OSLogEntryLog in entries {
            lines.append("\(formatter.string(from: entry.date)) [\(entry.category)] \(entry.composedMessage)")
        }
        return Array(lines.suffix(limit))
    }

    @MainActor static func settingsSummary(_ s: AppSettings) -> String {
        func flag(_ name: String, _ on: Bool) -> String { "\(name)=\(on ? "on" : "off")" }
        return [
            flag("math", s.math), flag("mermaid", s.mermaid), flag("emoji", s.emoji), flag("footnotes", s.footnotes),
            flag("rawHTML", s.rawHTML), flag("hardBreaks", s.hardBreaks), flag("smartPunctuation", s.smartPunctuation),
            flag("frontMatter", s.showFrontMatter), "largeMB=\(s.largeDocumentMB)", "hugeMB=\(s.hugeDocumentMB)",
            flag("liveReload", s.liveReload), flag("restoreSession", s.restoreSession),
            flag("singleClickPreview", s.singleClickPreview), flag("openLinksInNewTab", s.openLinksInNewTab),
            flag("followSymlinks", s.followSymlinks), flag("githubWidth", s.useGitHubWidth), "zoom=\(s.defaultZoom)",
        ].joined(separator: " ")
    }

    /// 메뉴 동작: 안내 → 클립보드 복사 → 브라우저로 이슈 양식 열기.
    @MainActor static func report(settings: AppSettings) {
        let alert = NSAlert()
        alert.messageText = String(localized: "문제 신고")
        alert.informativeText = String(localized: "진단 정보(버전, macOS, 설정, 이번 실행의 최근 로그)를 클립보드에 복사한 뒤 GitHub 이슈 양식을 엽니다. 양식의 본문에 붙여 넣어 주세요. 문서 내용은 포함되지 않습니다.")
        alert.addButton(withTitle: String(localized: "이슈 양식 열기"))
        alert.addButton(withTitle: String(localized: "취소"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let env = currentEnvironment()
        let text = diagnostics(environment: env, settingsSummary: settingsSummary(settings), recentLog: recentLogLines())
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        NSWorkspace.shared.open(issueURL(environment: env))
    }

    nonisolated private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    nonisolated private static func sysctlInt(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
