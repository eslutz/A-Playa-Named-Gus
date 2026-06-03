import SwiftUI

/// Brand color tokens. The Gus palette lives in the asset catalog (`Assets.xcassets`) as the
/// single source of truth — `AccentColor` plus the `Cinema*` colors that the RealityKit
/// "Gus Cinema" also reads (via `UIColor(named:)`). These tokens surface the windowed-UI
/// colors semantically so feature views don't reach for ad-hoc system colors.
extension Color {
    /// Pineapple-gold used for rating indicators — a sibling of the app `AccentColor`.
    static let gusRatingStar = Color.accentColor
}
