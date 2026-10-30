import Foundation

/// Stable opaque colors shared by the TV picker and its accessibility labels.
enum ThemeAccentPreset: String, CaseIterable, Identifiable {
    case gus = "4F7C82", blue = "007AFF", purple = "AF52DE", pink = "FF2D55"
    case red = "FF3B30", orange = "FF9500", yellow = "FFCC00", green = "34C759"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .gus: String(localized: "Gus Teal")
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        case .pink: String(localized: "Pink")
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        }
    }
}

extension ThemeAccent {
    /// User entry is forgiving; persisted values retain the strict six-digit format.
    static func userInput(_ text: String) -> ThemeAccent? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        return ThemeAccent(hex: value)
    }
}
