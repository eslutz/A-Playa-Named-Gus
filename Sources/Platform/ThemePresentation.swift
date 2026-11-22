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
        @Environment(\.colorSchemeContrast) private var contrast
    #endif

    func body(content: Content) -> some View {
        #if os(iOS) || os(tvOS)
            let preference = ThemePreference(rawValue: mode) ?? .gus
            let accent = preference == .custom ? ThemeAccent(hex: custom) ?? .gus : .gus
            let apple = preference == .apple
            let dark = colorScheme == .dark
            let fill: Color = apple ? .blue : accent.color
            let tint: Color = apple ? .blue : accent.readable(onDark: dark, increasedContrast: contrast == .increased).color
            let foreground: Color = apple || !accent.usesBlackForeground ? .white : .black
            #if os(tvOS)
                // TabView owns its native row styles; only remove the inherited theme tint here.
                let content = content.tint(nil)
            #endif
            #if os(iOS)
                let content = content.toggleStyle(ThemeSwitchStyle(track: apple ? nil : accent.switchTrack(onDark: dark).color))
            #endif
            content.tint(tint)
                .accentColor(tint)
                .environment(\.gusThemeFill, fill)
                .environment(\.gusThemeForeground, foreground)
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
        private struct ThemeSwitchStyle: ToggleStyle {
            let track: Color?
            func makeBody(configuration: Configuration) -> some View {
                Toggle(configuration)
                    .toggleStyle(.switch)
                    .tint(track)
            }
        }

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
