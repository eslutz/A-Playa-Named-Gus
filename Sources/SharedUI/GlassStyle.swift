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

    /// Prominent action over artwork, using the platform’s native button style.
    @ViewBuilder
    func gusProminentGlassButtonStyle() -> some View {
        #if os(tvOS)
            buttonStyle(.bordered)
        #elseif os(visionOS)
            buttonStyle(.borderedProminent)
        #else
            buttonStyle(.glassProminent)

        #endif
    }

    /// Let TV focus choose the foreground; a fixed accent foreground disappears on white focus.
    @ViewBuilder
    func gusProminentActionForeground() -> some View {
        #if os(tvOS)
            self
        #else
            gusPhoneProminentForeground()
        #endif
    }

    /// TV buttons use the system's untinted focus treatment for readable white focus plates.
    @ViewBuilder
    func gusProminentActionTint() -> some View {
        #if os(tvOS)
            self
        #else
            gusPhoneActionTint()
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

/// Native glass shares sampling between adjacent floating controls.
struct GusGlassControlGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if os(visionOS) || os(tvOS)
            content
        #else
            GlassEffectContainer(spacing: 8) { content }
        #endif
    }
}
