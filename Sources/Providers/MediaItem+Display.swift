import Foundation

extension MediaItem {
    var displayTitle: String {
        name ?? String(localized: "Untitled", comment: "Fallback item title")
    }

    /// e.g. `S1·E3` for episodes when both numbers are present.
    var episodeLocator: String? {
        guard let episode = indexNumber else { return name }
        if let season = parentIndexNumber {
            return "S\(season)·E\(episode)"
        }
        return "E\(episode)"
    }

    var yearText: String? {
        productionYear.map(String.init)
    }

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

    var criticRatingText: String? {
        guard let rating = criticRating else { return nil }
        return "\(Int(rating.rounded()))%"
    }

    var genreText: String? {
        joinedNonEmpty(genres)
    }

    var studioText: String? {
        joinedNonEmpty(studios.compactMap(\.name))
    }

    var primaryTagline: String? {
        taglines.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var peopleText: [String] {
        people.prefix(8).compactMap { person in
            guard let name = person.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty
            else { return nil }

            if let role = person.role?.trimmingCharacters(in: .whitespacesAndNewlines),
               !role.isEmpty
            {
                return "\(name) as \(role)"
            }
            return name
        }
    }

    /// Fractional playback progress (0...1) from resume data, if any.
    var playbackProgress: Double? {
        guard let percentage = userData?.playedPercentage else { return nil }
        return percentage / 100.0
    }

    var latestTVDisplayItem: MediaItem {
        guard type == .episode,
              let seriesID,
              let seriesName,
              !seriesName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return self
        }

        var imageTags: [String: String] = [:]
        if let seriesPrimaryImageTag {
            imageTags[MediaImageKind.primary.rawValue] = seriesPrimaryImageTag
        }

        return MediaItem(
            providerKind: providerKind,
            id: seriesID,
            imageTags: imageTags,
            name: seriesName,
            primaryImageAspectRatio: 2.0 / 3.0,
            productionYear: productionYear,
            seriesPrimaryImageTag: seriesPrimaryImageTag,
            type: .series,
            userData: userData
        )
    }

    private func joinedNonEmpty(_ values: [String]) -> String? {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        return cleaned.joined(separator: ", ")
    }
}
