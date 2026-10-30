import SwiftUI

private struct GusThemeFillKey: EnvironmentKey {
    static let defaultValue = Color.accentColor
}

private struct GusThemeForegroundKey: EnvironmentKey {
    static let defaultValue = Color.gusProminentActionForeground
}

extension EnvironmentValues {
    var gusThemeFill: Color {
        get { self[GusThemeFillKey.self] }
        set { self[GusThemeFillKey.self] = newValue }
    }

    var gusThemeForeground: Color {
        get { self[GusThemeForegroundKey.self] }
        set { self[GusThemeForegroundKey.self] = newValue }
    }
}

extension View {
    func gusTheme() -> some View {
        modifier(GusThemeModifier())
    }
}

private struct GusThemeModifier: ViewModifier {
    #if os(iOS) || os(tvOS)
        @AppStorage(ThemePreference.defaultsKey) private var mode = ThemePreference.gus.rawValue
        @AppStorage(ThemePreference.customAccentKey) private var custom = ThemeAccent.gus.hex
        @Environment(\.colorScheme) private var colorScheme
    #endif

    func body(content: Content) -> some View {
        #if os(iOS) || os(tvOS)
            let preference = ThemePreference(rawValue: mode) ?? .gus
            let accent = ThemeAccent(hex: custom) ?? .gus
            let fill: Color = preference == .gus ? Color("AccentColor") : preference == .apple ? .blue : accent.color
            let tint: Color = preference == .custom ? accent.readable(onDark: colorScheme == .dark).color : fill
            let foreground: Color = preference == .gus ? .gusProminentActionForeground : preference == .custom && accent.usesBlackForeground ? .black : .white
            #if os(tvOS)
                if #available(tvOS 27.0, *) {
                    content.tint(tint)
                        .accentColor(tint)
                        .environment(\.gusThemeFill, fill)
                        .environment(\.gusThemeForeground, foreground)
                } else {
                    // Match the native untinted TV action styles: OS 26 can
                    // otherwise paint an unfocused label in its plate color.
                    content.buttonStyle(.bordered).tint(nil)
                        .environment(\.gusThemeFill, fill)
                        .environment(\.gusThemeForeground, foreground)
                }
            #else
                content.tint(tint)
                    .accentColor(tint)
                    .environment(\.gusThemeFill, fill)
                    .environment(\.gusThemeForeground, foreground)
            #endif
        #else
            content
        #endif
    }
}

#if os(iOS) || os(tvOS)
    extension ThemeAccent {
        var color: Color {
            Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
        }
    }

    #if os(iOS)
        struct ThemeSettingsControls: View {
            @AppStorage(ThemePreference.defaultsKey) private var mode = ThemePreference.gus.rawValue
            @AppStorage(ThemePreference.customAccentKey) private var custom = ThemeAccent.gus.hex

            var body: some View {
                Picker("Theme", selection: Binding(get: {
                    (ThemePreference(rawValue: mode) ?? .gus).rawValue
                }, set: { mode = $0 })) {
                    ForEach(ThemePreference.allCases) { theme in Text(theme.title).tag(theme.rawValue) }
                }
                .accessibilityIdentifier("Settings.theme")
                if mode == ThemePreference.custom.rawValue {
                    ColorPicker("Accent Color", selection: Binding(get: {
                        (ThemeAccent(hex: custom) ?? .gus).color
                    }, set: { color in
                        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                        if UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                            custom = ThemeAccent(red: Double(red), green: Double(green), blue: Double(blue)).hex
                        }
                    }), supportsOpacity: false)
                        .accessibilityIdentifier("Settings.accentColor")
                }
            }
        }
    #endif
#endif
