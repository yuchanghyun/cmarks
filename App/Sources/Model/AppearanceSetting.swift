import AppKit

/// 테마 설정(설계 문서 §5.3). NSApp.appearance를 바꾸면 웹뷰의 prefers-color-scheme도 따라간다.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "시스템")
        case .light: String(localized: "라이트")
        case .dark: String(localized: "다크")
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    var next: AppearanceSetting {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
