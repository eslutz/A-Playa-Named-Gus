import SwiftUI

extension Scene {
    /// Menu-bar commands where SwiftUI exposes them; no-op on tvOS.
    @SceneBuilder
    func gusCommands(appModel: AppModel, navigation: AppNavigationModel) -> some Scene {
        #if os(tvOS)
            self
        #else
            commands {
                GusCommands(appModel: appModel, navigation: navigation)
            }
        #endif
    }
}

/// The handful of cross-platform UI tweaks. Keeping them in one place means feature views
/// stay free of `#if os(...)` noise and read like ordinary SwiftUI.
extension View {
    /// Pointer/Optic-ID hover lift on platforms that support it; no-op elsewhere.
    @ViewBuilder
    func posterHoverEffect() -> some View {
        #if os(iOS) || os(visionOS)
            hoverEffect(.highlight)
        #else
            self
        #endif
    }

    /// Preserve native focus styling on tvOS while keeping poster links visually plain on
    /// pointer/touch platforms.
    @ViewBuilder
    func posterNavigationStyle() -> some View {
        #if os(tvOS)
            self
        #else
            buttonStyle(.plain)
        #endif
    }

    /// Groups related focusable controls on tvOS; no-op elsewhere.
    @ViewBuilder
    func tvFocusSection() -> some View {
        #if os(tvOS)
            focusSection()
        #else
            self
        #endif
    }

    /// Keyboard shortcuts are unavailable on tvOS; keep feature views platform-neutral.
    @ViewBuilder
    func gusKeyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        #if os(tvOS)
            self
        #else
            keyboardShortcut(key, modifiers: modifiers)
        #endif
    }

    /// Default action shortcut on keyboard platforms; no-op on tvOS.
    @ViewBuilder
    func gusDefaultActionShortcut() -> some View {
        #if os(tvOS)
            self
        #else
            keyboardShortcut(.defaultAction)
        #endif
    }

    /// Native searchable UI, avoiding presentation/focus overloads that tvOS doesn't expose.
    @ViewBuilder
    func gusSearchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        isFocused: FocusState<Bool>.Binding,
        prompt: Text
    ) -> some View {
        #if os(tvOS)
            searchable(text: text, prompt: prompt)
        #else
            searchable(text: text, isPresented: isPresented, prompt: prompt)
                .searchFocused(isFocused)
        #endif
    }

    /// visionOS glass panel background; no-op on other platforms.
    @ViewBuilder
    func glassBackground() -> some View {
        #if os(visionOS)
            glassBackgroundEffect()
        #else
            self
        #endif
    }

    /// URL-entry conveniences (no autocorrect/autocapitalization, URL keyboard) where
    /// the platform supports them.
    @ViewBuilder
    func urlFieldStyle() -> some View {
        #if os(iOS) || os(visionOS)
            keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        #else
            autocorrectionDisabled()
        #endif
    }
}

/// Adaptive poster grid columns, tuned per platform/idiom.
enum PosterGrid {
    static var columns: [GridItem] {
        #if os(tvOS)
            return Array(repeating: GridItem(.flexible(), spacing: 40), count: 6)
        #elseif os(macOS)
            return [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 20)]
        #elseif os(visionOS)
            return [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 28)]
        #else
            return [GridItem(.adaptive(minimum: 110, maximum: 180), spacing: 16)]
        #endif
    }

    static var spacing: CGFloat {
        #if os(tvOS)
            return 40
        #elseif os(visionOS)
            return 28
        #else
            return 16
        #endif
    }
}
