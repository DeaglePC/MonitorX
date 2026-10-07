import Foundation
import Observation
import Synchronization

@main
struct LanguageSwitchCheck {
    static func main() throws {
        let suite = "MonitorXLanguageCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let localizer = Localizer(defaults: defaults)

        for (language, title) in [(AppLanguage.en, "Overview"), (.zhHans, "概览"),
                                   (.ja, "概要"), (.en, "Overview")] {
            localizer.language = language
            precondition(localizer.string("Overview") == title)
            precondition(localizer.resolvedCode == language.rawValue)
            precondition(defaults.string(forKey: "language") == language.rawValue)
            precondition(Localizer(defaults: defaults).string("Overview") == title)
        }

        let invalidated = Mutex(false)
        withObservationTracking {
            _ = localizer.string("Overview")
        } onChange: {
            invalidated.withLock { $0 = true }
        }
        localizer.language = .zhHans
        precondition(invalidated.withLock { $0 }, "Language changes must invalidate observing views")
        precondition(localizer.string("Overview") == "概览")

        localizer.language = .ar
        precondition(localizer.layoutDirection == .rightToLeft)
        localizer.language = .en
        precondition(localizer.layoutDirection == .leftToRight)
        precondition(localizer.string("Missing translation") == "Missing translation")

        localizer.language = .system
        precondition(AppLanguage.allCases.contains { $0.rawValue == localizer.resolvedCode })
        precondition(defaults.string(forKey: "language") == "")

        var checked = 0
        for language in AppLanguage.allCases where language != .system {
            localizer.language = language
            let url = Bundle.module.url(forResource: language.rawValue,
                                        withExtension: "lproj", subdirectory: "Localization")!
            let data = try Data(contentsOf: url.appendingPathComponent("Localizable.strings"))
            let translations = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
            for (key, expected) in translations {
                precondition(localizer.string(key) == expected, "\(language.rawValue): \(key)")
                checked += 1
            }
        }
        print("Language switching passed: \(checked) translations, persistence, observation and layout direction")
    }
}
