import Foundation

/// The interface language from Settings: as the system, or Russian or English. macOS picks the
/// localization once, at launch, from `AppleLanguages`, so a change takes a relaunch.
/// What the site shows — titles, descriptions, genres, comments — stays in Russian either way.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case russian = "ru"
    case english = "en"

    var id: String { rawValue }

    /// Languages by their own names, as macOS lists them.
    var title: String {
        switch self {
        case .system: String(localized: "Как в системе")
        case .russian: "Русский"
        case .english: "English"
        }
    }

    private static let key = "appLanguage"

    static var current: AppLanguage {
        get { UserDefaults.standard.string(forKey: key).flatMap(Self.init) ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            if newValue == .system {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
            }
        }
    }

    /// The language the interface came up in, for numbers and words put together in code.
    static let interface = Bundle.main.preferredLocalizations.first ?? "ru"
    static var isRussian: Bool { interface == "ru" }
    static let locale = Locale(identifier: isRussian ? "ru_RU" : "en_US")
}
