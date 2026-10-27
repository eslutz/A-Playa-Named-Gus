import Foundation

/// Device-local accent preference, independent of account and light/dark appearance.
enum ThemePreference: String, CaseIterable, Identifiable {
    case gus, apple, custom

    static let defaultsKey = "gusTheme"
    static let customAccentKey = "gusCustomAccent"
    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .gus: String(localized: "Gus Default")
        case .apple: String(localized: "Apple Default")
        case .custom: String(localized: "Custom")
        }
    }
}

/// Opaque sRGB storage with deterministic contrast calculations and safe decoding.
struct ThemeAccent: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    static let gus = ThemeAccent(hex: "4F7C82")!

    init?(hex: String) {
        guard hex.count == 6, hex.allSatisfy({ $0.isASCII && $0.isHexDigit }), let value = UInt32(hex, radix: 16) else { return nil }
        red = Double((value >> 16) & 255) / 255
        green = Double((value >> 8) & 255) / 255
        blue = Double(value & 255) / 255
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red.isFinite ? min(max(red, 0), 1) : 0
        self.green = green.isFinite ? min(max(green, 0), 1) : 0
        self.blue = blue.isFinite ? min(max(blue, 0), 1) : 0
    }

    var hex: String {
        String(format: "%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    var usesBlackForeground: Bool {
        (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
    }

    /// Preserve hue while adjusting control/link tint for contrast on the native canvas.
    func readable(onDark: Bool) -> ThemeAccent {
        var result = self
        for _ in 0 ..< 100 {
            let contrast = onDark ? (result.luminance + 0.05) / 0.09 : 0.95 / (result.luminance + 0.05)
            if contrast >= 4.5 {
                return result
            }
            let target = onDark ? 1.0 : 0.0
            result = ThemeAccent(red: result.red + (target - result.red) * 0.05, green: result.green + (target - result.green) * 0.05, blue: result.blue + (target - result.blue) * 0.05)
        }
        return result
    }
}
