import SwiftUI

#if os(tvOS)
    struct TVThemeSettingsControls: View {
        @AppStorage(ThemePreference.defaultsKey) private var mode = ThemePreference.gus.rawValue
        @AppStorage(ThemePreference.customAccentKey) private var custom = ThemeAccent.gus.hex
        let editAccent: () -> Void

        var body: some View {
            Section("Theme") {
                Picker("Theme", selection: Binding(get: {
                    (ThemePreference(rawValue: mode) ?? .gus).rawValue
                }, set: { mode = $0 })) {
                    ForEach(ThemePreference.allCases) { preference in
                        Text(preference.title).tag(preference.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("Settings.theme")
                if mode == ThemePreference.custom.rawValue {
                    Button(action: editAccent) {
                        Text("Accent Color")
                    }
                    .accessibilityValue(custom)
                    .accessibilityIdentifier("Settings.accentColor")
                }
            }
        }
    }

    private struct TVAccentPresentation: ViewModifier {
        @Binding var isPresented: Bool
        @AppStorage(ThemePreference.customAccentKey) private var custom = ThemeAccent.gus.hex

        func body(content: Content) -> some View {
            content.gusTVTask(isPresented: $isPresented) {
                NavigationStack {
                    TVAccentEditor(initial: custom) { custom = $0 }
                }
            }
        }
    }

    private struct TVAccentEditor: View {
        @Environment(\.dismiss) private var dismiss
        @State private var draft: String
        let save: (String) -> Void

        init(initial: String, save: @escaping (String) -> Void) {
            _draft = State(initialValue: initial)
            self.save = save
        }

        private var accent: ThemeAccent? {
            ThemeAccent.userInput(draft)
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    Text("Accent Color").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text("Choose an accent or enter a six-digit hex color.")
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 300), spacing: 32), count: 4), spacing: 32) {
                        ForEach(ThemeAccentPreset.allCases) { preset in
                            Button { draft = preset.rawValue } label: {
                                HStack {
                                    Circle().fill(ThemeAccent(hex: preset.rawValue)!.color)
                                        .frame(width: 32, height: 32).accessibilityHidden(true)
                                    Text(preset.title).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "checkmark").opacity(accent?.hex == preset.rawValue ? 1 : 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 64)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(preset.title)
                            .accessibilityValue(preset.rawValue)
                            .accessibilityAddTraits(accent?.hex == preset.rawValue ? .isSelected : [])
                            .accessibilityIdentifier("Theme.preset." + preset.rawValue)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Hex Color").font(.headline)
                        TextField("Hex Color", text: $draft)
                            .autocorrectionDisabled().textInputAutocapitalization(.characters)
                            .accessibilityIdentifier("Theme.hex")
                    }
                    if let accent {
                        HStack {
                            Text("Accent Preview")
                                .foregroundStyle(accent.usesBlackForeground ? .black : .white)
                                .padding(24).background(accent.color, in: RoundedRectangle(cornerRadius: 16))
                            Text("#" + accent.hex).monospaced()
                        }
                        .accessibilityIdentifier("Theme.preview")
                    } else {
                        Text("Enter six hexadecimal digits, such as 4F7C82.")
                            .accessibilityIdentifier("Theme.validation")
                    }
                }
                .padding(64)
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let accent else { return }
                        save(accent.hex)
                        dismiss()
                    }
                    .disabled(accent == nil)
                    .accessibilityIdentifier("Theme.save")
                }
            }
            .gusTVCanvas()
            .tint(nil)
        }
    }
#endif

extension View {
    @ViewBuilder func gusTVAccentEditor(isPresented: Binding<Bool>) -> some View {
        #if os(tvOS)
            modifier(TVAccentPresentation(isPresented: isPresented))
        #else
            self
        #endif
    }
}
