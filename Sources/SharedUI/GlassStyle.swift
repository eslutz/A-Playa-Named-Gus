import SwiftUI

/// Liquid Glass adoption helpers.
///
/// The deployment floors (iOS/tvOS 18, macOS 15, visionOS 2) predate the Liquid Glass
/// design language, so every adoption point gates on the OS 26 SDKs and falls back to
/// the system Material treatment older releases render natively. Per the HIG, glass is
/// applied to the floating control layer (player overlays, badges, hero actions) —
/// content surfaces (cards, pills, form rows) stay on Materials by design.
extension View {
    /// Liquid Glass surface for a floating control cluster or badge, with an
    /// ultra-thin-material fallback before OS 26. visionOS uses its native
    /// `glassBackgroundEffect` (the platform's own glass; `glassEffect` is iOS-family).
    @ViewBuilder
    func gusGlassSurface(in shape: some InsettableShape) -> some View {
        #if os(visionOS)
            glassBackgroundEffect(in: shape)
        #else
            if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
                glassEffect(.regular, in: shape)
            } else {
                background(.ultraThinMaterial, in: shape)
            }
        #endif
    }

    /// Capsule variant of `gusGlassSurface` — the common shape for floating pills.
    func gusGlassCapsule() -> some View {
        gusGlassSurface(in: Capsule())
    }

    /// Prominent action button floating over artwork: `.glassProminent` on OS 26+,
    /// `.borderedProminent` before (and on visionOS, where bordered buttons are
    /// already glass-native).
    @ViewBuilder
    func gusProminentGlassButtonStyle() -> some View {
        #if os(visionOS)
            buttonStyle(.borderedProminent)
        #else
            if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.borderedProminent)
            }
        #endif
    }

    /// Secondary action button floating over artwork: `.glass` on OS 26+,
    /// `.bordered` before (and on visionOS — see above).
    @ViewBuilder
    func gusGlassButtonStyle() -> some View {
        #if os(visionOS)
            buttonStyle(.bordered)
        #else
            if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
                buttonStyle(.glass)
            } else {
                buttonStyle(.bordered)
            }
        #endif
    }
}
