import SwiftUI

/// Brand color tokens. The A Playa Named Gus palette lives in the asset catalog (`Assets.xcassets`) as the
/// single source of truth — `AccentColor` plus the `Cinema*` colors that the RealityKit
/// "Gus Cinema" also reads (via `UIColor(named:)`). These tokens surface the windowed-UI
/// colors semantically so feature views don't reach for ad-hoc system colors.
extension Color {
    /// Ratings use the app accent so score highlights follow the app palette.
    static let gusRatingStar = Color.accentColor
}
