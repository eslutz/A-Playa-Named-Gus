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
    /// Platform-appropriate hover/focus affordance for poster cards.
    ///
    /// - iOS / visionOS: `.lift` (card lift with shadow) per HIG guidance for tappable
    ///   content tiles — the system applies focus scale/parallax automatically on tvOS,
    ///   so no explicit effect is needed there.
    /// - tvOS / macOS: no-op (system card-scale is applied by the focus engine on tvOS;
    ///   cursor change is sufficient on macOS).
    @ViewBuilder
    func posterHoverEffect() -> some View {
        #if os(visionOS)
            hoverEffect(.lift)
                .visionHoverEffect(cornerRadius: 12)
        #elseif os(iOS)
            hoverEffect(.lift)
        #else
            self
        #endif
    }

    /// Matches visionOS hover hit-testing to the visible rounded rectangle, avoiding the
    /// oversized default focus plate on poster and form rows. No-op elsewhere.
    @ViewBuilder
    func visionHoverEffect(cornerRadius: CGFloat) -> some View {
        #if os(visionOS)
            buttonBorderShape(.roundedRectangle(radius: cornerRadius))
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
        #else
            return [GridItem(.adaptive(minimum: minimumItemWidth, maximum: maximumItemWidth), spacing: spacing)]
        #endif
    }

    static var minimumItemWidth: CGFloat {
        #if os(tvOS)
            return 220
        #elseif os(macOS)
            return 160
        #elseif os(visionOS)
            return 180
        #else
            return 140
        #endif
    }

    static var maximumItemWidth: CGFloat {
        #if os(tvOS)
            return 260
        #elseif os(macOS)
            return 220
        #elseif os(visionOS)
            return 240
        #else
            return 220
        #endif
    }

    static var spacing: CGFloat {
        #if os(tvOS)
            return 40
        #elseif os(visionOS)
            return 28
        #elseif os(iOS)
            return 18
        #else
            return 20
        #endif
    }
}
