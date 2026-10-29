import AppKit

/// The app's theme from Settings: as the system, or always light or dark. Applied to the whole app,
/// so menus, alerts, Settings and the About panel follow too; the player stays dark either way.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Системная"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }

    private static let key = "appearance"

    /// Dark until changed: the look the app had before it had a choice.
    @MainActor
    static var current: AppearancePreference {
        get { UserDefaults.standard.string(forKey: key).flatMap(Self.init) ?? .dark }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            newValue.apply()
        }
    }

    /// `nil` hands the choice back to the system, including its automatic switching through the day.
    @MainActor
    func apply() {
        NSApplication.shared.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
