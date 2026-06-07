import SwiftUI

/// Brand color tokens. The A Playa Named Gus palette lives in the asset catalog (`Assets.xcassets`) as the
/// single source of truth — `AccentColor` plus the `Cinema*` colors that the RealityKit
/// "Gus Cinema" also reads (via `UIColor(named:)`). These tokens surface the windowed-UI
/// colors semantically so feature views don't reach for ad-hoc system colors.
extension Color {
    static let jellyfinPurple = Color(red: 0.675, green: 0.361, blue: 0.765)
    static let jellyfinBlue = Color(red: 0.0, green: 0.643, blue: 0.863)
    static let jellyfinNavy = Color(red: 0.0, green: 0.043, blue: 0.145)

    /// Ratings use the app accent so score highlights follow the Jellyfin palette.
    static let gusRatingStar = Color.accentColor
}
