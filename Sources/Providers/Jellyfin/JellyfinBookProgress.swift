import Foundation

/// Maps EPUB reading progress to Jellyfin's user-data model.
///
/// Jellyfin assigns books a fixed 1-second synthetic runtime (`RunTimeTicks` of
/// 10,000,000), so reading position rides on `PlaybackPositionTicks` scaled across that
/// span. `PlayedPercentage` is derived from it server-side, which is what feeds the
/// "Continue" row and syncs to other clients. Verified against Jellyfin 10.11 (ADR 0009).
///
/// The model carries only a scalar fraction (0...1 through the book), not a Readium
/// `Locator`: cross-device resume lands on the right percentage and the reader snaps to
/// the nearest locator. Exact-page resume stays local (`BookProgressStore`).
enum JellyfinBookProgress {
    /// Jellyfin's synthetic per-book runtime, in ticks.
    static let bookRuntimeTicks = 10_000_000

    /// Converts a 0...1 reading fraction to `PlaybackPositionTicks`.
    static func ticks(forFraction fraction: Double) -> Int {
        let clamped = min(max(fraction, 0), 1)
        return Int((clamped * Double(bookRuntimeTicks)).rounded())
    }

    /// Converts `PlaybackPositionTicks` back to a 0...1 reading fraction.
    static func fraction(forTicks ticks: Int) -> Double {
        guard ticks > 0 else { return 0 }
        return min(Double(ticks) / Double(bookRuntimeTicks), 1)
    }
}
