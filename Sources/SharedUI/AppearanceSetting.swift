import SwiftUI

/// App-wide appearance preference: follow the system, or force light/dark.
///
/// Stored in `UserDefaults` (see `defaultsKey`) and applied at the window root via
/// `preferredColorScheme`, so it covers every platform with one mechanism.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let defaultsKey = "dev.ericslutz.gus.appearance"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .system:
            return String(localized: "System", comment: "Appearance option: follow the system setting")
        case .light:
            return String(localized: "Light", comment: "Appearance option: always light mode")
        case .dark:
            return String(localized: "Dark", comment: "Appearance option: always dark mode")
        }
    }

    /// The scheme to force, or `nil` to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
