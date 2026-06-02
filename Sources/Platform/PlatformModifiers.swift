import SwiftUI

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
        #else
        return 16
        #endif
    }
}
