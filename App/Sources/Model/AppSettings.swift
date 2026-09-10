import FileKit
import Foundation
import MarkdownCore
import SwiftUI

/// 설정 창 항목(PLAN.md §5.3). UserDefaults에 저장하고, 바뀌면 AppModel이 렌더·트리·뷰어에 반영한다.
@MainActor
@Observable
final class AppSettings {
    var onChange: (() -> Void)?

    // 외형
    var useGitHubWidth: Bool { didSet { store(useGitHubWidth, "useGitHubWidth") } }
    var defaultZoom: Double { didSet { store(defaultZoom, "defaultZoom") } }

    // 렌더링
    var math: Bool { didSet { store(math, "math") } }
    var mermaid: Bool { didSet { store(mermaid, "mermaid") } }
    var emoji: Bool { didSet { store(emoji, "emoji") } }
    var footnotes: Bool { didSet { store(footnotes, "footnotes") } }
    var rawHTML: Bool { didSet { store(rawHTML, "rawHTML") } }
    var hardBreaks: Bool { didSet { store(hardBreaks, "hardBreaks") } }
    var smartPunctuation: Bool { didSet { store(smartPunctuation, "smartPunctuation") } }
    var showFrontMatter: Bool { didSet { store(showFrontMatter, "showFrontMatter") } }
    var largeDocumentMB: Int { didSet { store(largeDocumentMB, "largeDocumentMB") } }
    var hugeDocumentMB: Int { didSet { store(hugeDocumentMB, "hugeDocumentMB") } }

    // 파일
    var markdownExtensions: String { didSet { store(markdownExtensions, "markdownExtensions") } }
    var ignoredDirectories: String { didSet { store(ignoredDirectories, "ignoredDirectories") } }
    var followSymlinks: Bool { didSet { store(followSymlinks, "followSymlinks") } }

    // 동작
    var singleClickPreview: Bool { didSet { store(singleClickPreview, "singleClickPreview") } }
    var openLinksInNewTab: Bool { didSet { store(openLinksInNewTab, "openLinksInNewTab") } }
    var restoreSession: Bool { didSet { store(restoreSession, "restoreSession") } }
    var liveReload: Bool { didSet { store(liveReload, "liveReload") } }
    var cleanupEphemeral: Bool { didSet { store(cleanupEphemeral, "cleanupEphemeral") } }

    // 단축키(설정 ▸ 단축키에서 직접 입력). 기본값과 다른 것만 저장한다.
    private(set) var shortcutOverrides: [String: KeyCombo] {
        didSet {
            guard !isLoading, let data = try? JSONEncoder().encode(shortcutOverrides) else { return }
            defaults.set(data, forKey: "settings.shortcuts")
            onChange?()
        }
    }

    static let defaultExtensions = "md markdown mdown mkd mkdn mdtxt mdtext mdx qmd rmd"
    static let defaultIgnored = ".git node_modules .build DerivedData .svn .hg __pycache__ .venv Pods"

    private let defaults: UserDefaults
    private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: "settings.\(key)") as? Bool ?? fallback }
        func int(_ key: String, _ fallback: Int) -> Int { defaults.object(forKey: "settings.\(key)") as? Int ?? fallback }
        func double(_ key: String, _ fallback: Double) -> Double { defaults.object(forKey: "settings.\(key)") as? Double ?? fallback }
        func string(_ key: String, _ fallback: String) -> String { defaults.string(forKey: "settings.\(key)") ?? fallback }

        useGitHubWidth = bool("useGitHubWidth", true)
        defaultZoom = double("defaultZoom", 1.0)
        math = bool("math", true)
        mermaid = bool("mermaid", true)
        emoji = bool("emoji", true)
        footnotes = bool("footnotes", true)
        rawHTML = bool("rawHTML", true)
        hardBreaks = bool("hardBreaks", false)
        smartPunctuation = bool("smartPunctuation", false)
        showFrontMatter = bool("showFrontMatter", true)
        largeDocumentMB = int("largeDocumentMB", 2)
        hugeDocumentMB = int("hugeDocumentMB", 5)
        markdownExtensions = string("markdownExtensions", Self.defaultExtensions)
        ignoredDirectories = string("ignoredDirectories", Self.defaultIgnored)
        followSymlinks = bool("followSymlinks", false)
        singleClickPreview = bool("singleClickPreview", true)
        openLinksInNewTab = bool("openLinksInNewTab", false)
        restoreSession = bool("restoreSession", true)
        liveReload = bool("liveReload", true)
        cleanupEphemeral = bool("cleanupEphemeral", true)
        if let data = defaults.data(forKey: "settings.shortcuts"), let saved = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            shortcutOverrides = saved
        } else {
            shortcutOverrides = [:]
        }
        isLoading = false
    }

    var extensionSet: Set<String> {
        let parsed = Set(markdownExtensions.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }.filter { !$0.isEmpty })
        return parsed.isEmpty ? ["md"] : parsed
    }

    var ignoredSet: Set<String> {
        Set(ignoredDirectories.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init).filter { !$0.isEmpty })
    }

    var renderSettings: RenderSettings {
        var settings = RenderSettings.github
        settings.math = math
        settings.mermaid = mermaid
        settings.emoji = emoji
        settings.footnotes = footnotes
        settings.rawHTML = rawHTML
        settings.hardBreaks = hardBreaks
        settings.smartPunctuation = smartPunctuation
        settings.frontMatter = showFrontMatter ? .collapsed : .hidden
        settings.contentMaxWidth = useGitHubWidth ? 980 : nil
        settings.largeDocumentBytes = max(1, largeDocumentMB) << 20
        settings.hugeDocumentBytes = max(largeDocumentMB + 1, hugeDocumentMB) << 20
        return settings
    }

    func fileFilter(showHidden: Bool) -> FileFilter {
        FileFilter(markdownExtensions: extensionSet, ignoredDirectoryNames: ignoredSet, showHidden: showHidden, followSymlinks: followSymlinks)
    }

    func resetToDefaults() {
        useGitHubWidth = true
        defaultZoom = 1.0
        math = true
        mermaid = true
        emoji = true
        footnotes = true
        rawHTML = true
        hardBreaks = false
        smartPunctuation = false
        showFrontMatter = true
        largeDocumentMB = 2
        hugeDocumentMB = 5
        markdownExtensions = Self.defaultExtensions
        ignoredDirectories = Self.defaultIgnored
        followSymlinks = false
        singleClickPreview = true
        openLinksInNewTab = false
        restoreSession = true
        liveReload = true
        cleanupEphemeral = true
        shortcutOverrides = [:]
    }

    // MARK: 단축키

    func combo(for action: ShortcutAction) -> KeyCombo {
        shortcutOverrides[action.rawValue] ?? action.defaultCombo
    }

    func keyboardShortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        combo(for: action).keyboardShortcut
    }

    func setCombo(_ combo: KeyCombo, for action: ShortcutAction) {
        if combo == action.defaultCombo {
            shortcutOverrides.removeValue(forKey: action.rawValue)
        } else {
            shortcutOverrides[action.rawValue] = combo
        }
    }

    func resetShortcut(for action: ShortcutAction) {
        shortcutOverrides.removeValue(forKey: action.rawValue)
    }

    func resetAllShortcuts() {
        shortcutOverrides = [:]
    }

    /// 같은 조합을 쓰는 다른 동작.
    func conflicts(for action: ShortcutAction) -> [ShortcutAction] {
        let combo = combo(for: action)
        return ShortcutAction.allCases.filter { $0 != action && self.combo(for: $0) == combo }
    }

    private func store(_ value: Any, _ key: String) {
        guard !isLoading else { return }
        defaults.set(value, forKey: "settings.\(key)")
        onChange?()
    }
}
