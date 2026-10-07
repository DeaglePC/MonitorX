import Foundation
import Observation
import SwiftUI

/// Languages the app ships translations for (`Resources/Localization/<code>.lproj/Localizable.strings`).
/// `.system` follows macOS (System Settings › General › Language & Region, including the per-app language).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case en, zhHans = "zh-Hans", zhHant = "zh-Hant", ja, ko
    case es, fr, de, it, pt, ru, uk, pl, nl, sv, tr
    case ar, he, hi, th, vi, id, ms

    var id: String { rawValue }

    /// Shown in the language picker, always in the language itself so anyone can find their own.
    var nativeName: String {
        switch self {
        case .system: L("System Default")
        case .en: "English"
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文"
        case .ja: "日本語"
        case .ko: "한국어"
        case .es: "Español"
        case .fr: "Français"
        case .de: "Deutsch"
        case .it: "Italiano"
        case .pt: "Português"
        case .ru: "Русский"
        case .uk: "Українська"
        case .pl: "Polski"
        case .nl: "Nederlands"
        case .sv: "Svenska"
        case .tr: "Türkçe"
        case .ar: "العربية"
        case .he: "עברית"
        case .hi: "हिन्दी"
        case .th: "ไทย"
        case .vi: "Tiếng Việt"
        case .id: "Bahasa Indonesia"
        case .ms: "Bahasa Melayu"
        }
    }
}

/// Resolves UI strings for the chosen language. Keys are the English text, so a missing translation
/// falls back to readable English. SwiftPM builds load the same translations from their resource bundle.
///
/// `language` is observed: SwiftUI views that call `L(...)` re-render as soon as it changes.
@Observable
final class Localizer {
    static let shared = Localizer()

    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Self.defaultsKey)
            resolve()
        }
    }

    /// Language code actually in use (e.g. "de"), after resolving `.system`.
    private(set) var resolvedCode = "en"

    @ObservationIgnored private var bundle: Bundle?
    @ObservationIgnored private let defaults: UserDefaults
    private static let defaultsKey = "language"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: Self.defaultsKey) ?? "") ?? .system
        resolve()
    }

    var locale: Locale { Locale(identifier: resolvedCode) }

    var layoutDirection: LayoutDirection {
        Locale.Language(identifier: resolvedCode).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    func string(_ key: String) -> String {
        _ = language   // register the dependency for SwiftUI observation
        return bundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    private func resolve() {
        let shipped = AppLanguage.allCases.map(\.rawValue).filter { !$0.isEmpty }
        let code: String
        if language == .system {
            // Best match against the user's language list (which includes the per-app language override).
            code = Bundle.preferredLocalizations(from: shipped).first ?? "en"
        } else {
            code = language.rawValue
        }
        resolvedCode = code
        // Packaged apps keep .lproj folders in Contents/Resources. `swift run` / debug builds
        // keep them in SwiftPM's resource bundle instead. Resolve that bundle only if needed,
        // since the standalone .app does not need to ship the SwiftPM bundle as well.
        let path = Bundle.main.path(forResource: code, ofType: "lproj")
            ?? Bundle.module.path(forResource: code, ofType: "lproj", inDirectory: "Localization")
        bundle = path.flatMap(Bundle.init(path:))
    }
}

/// Localized string for an English key.
func L(_ key: String) -> String {
    Localizer.shared.string(key)
}

/// Localized format string; arguments are substituted with `%@` / `%1$@` placeholders (pass them as strings).
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: Localizer.shared.string(key), locale: Localizer.shared.locale, arguments: args)
}
