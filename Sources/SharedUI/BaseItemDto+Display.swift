import Foundation
import JellyfinAPI

/// Lightweight display helpers for `BaseItemDto`, mirroring (a small slice of) Swiftfin's
/// `BaseItemDto` extensions but using only Foundation formatting.
extension BaseItemDto {

    var displayTitle: String { name ?? "Untitled" }

    /// e.g. `S1·E3` for episodes when both numbers are present.
    var episodeLocator: String? {
        guard let episode = indexNumber else { return name }
        if let season = parentIndexNumber {
            return "S\(season)·E\(episode)"
        }
        return "E\(episode)"
    }

    var yearText: String? { productionYear.map(String.init) }

    /// Human runtime, e.g. `1h 47m`, derived from `runTimeTicks` (100 ns units).
    var runtimeText: String? {
        guard let ticks = runTimeTicks, ticks > 0 else { return nil }
        let totalSeconds = Int(ticks / 10_000_000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var communityRatingText: String? {
        guard let rating = communityRating else { return nil }
        return String(format: "★ %.1f", rating)
    }

    /// Fractional playback progress (0...1) from resume data, if any.
    var playbackProgress: Double? {
        guard let percentage = userData?.playedPercentage else { return nil }
        return percentage / 100.0
    }
}
