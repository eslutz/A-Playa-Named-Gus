import SwiftUI

/// Liquid Glass adoption helpers.
///
/// Glass is applied to floating controls; content surfaces retain native Materials.
extension View {
    /// Liquid Glass surface for a floating control cluster or badge, with an
    /// platform-native treatment. visionOS uses its native
    /// `glassBackgroundEffect` (the platform's own glass; `glassEffect` is iOS-family).
    @ViewBuilder
    func gusGlassSurface(in shape: some InsettableShape) -> some View {
        #if os(visionOS)
            glassBackgroundEffect(in: shape)
        #else
            glassEffect(.regular, in: shape)

        #endif
    }

    /// Capsule variant of `gusGlassSurface` — the common shape for floating pills.
    func gusGlassCapsule() -> some View {
        gusGlassSurface(in: Capsule())
    }

    /// Prominent action over artwork, using the platform’s native glass style.
    @ViewBuilder
    func gusProminentGlassButtonStyle() -> some View {
        #if os(visionOS)
            buttonStyle(.borderedProminent)
        #else
            buttonStyle(.glassProminent)

        #endif
    }

    /// Secondary action over artwork, using the platform’s native glass style.
    @ViewBuilder
    func gusGlassButtonStyle() -> some View {
        #if os(visionOS)
            buttonStyle(.bordered)
        #else
            buttonStyle(.glass)

        #endif
    }
}
