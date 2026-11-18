import Foundation

extension MediaItem {
    var displayTitle: String {
        name ?? String(localized: "Untitled", comment: "Fallback item title")
    }

    /// e.g. `S1·E3` for episodes; `nil` when no episode number exists (falling back to
    /// the item name here would duplicate the title wherever the locator is shown
    /// alongside it).
    var episodeLocator: String? {
        guard let episode = indexNumber else { return nil }
        if let season = parentIndexNumber {
            return String(localized: "S\(season.formatted(.number.grouping(.never)))·E\(episode.formatted(.number.grouping(.never)))")
        }
        return String(localized: "E\(episode.formatted(.number.grouping(.never)))")
    }

    var yearText: String? {
        productionYear.map(String.init)
    }

    /// Human runtime, e.g. `1h 47m`, derived from `runTimeTicks` (100 ns units).
    var runtimeText: String? {
        guard let ticks = runTimeTicks, ticks > 0 else { return nil }
        let totalSeconds = Int(ticks / 10_000_000)
        let visibleSeconds = max(60, totalSeconds - (totalSeconds % 60))

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(visibleSeconds))
    }

    var communityRatingText: String? {
        guard let rating = communityRating, rating.isFinite else { return nil }
        return String(localized: "★ \(rating.formatted(.number.precision(.fractionLength(1))))")
    }

    var criticRatingText: String? {
        guard let rating = criticRating, rating.isFinite else { return nil }
        return (rating / 100).formatted(.percent.precision(.fractionLength(0)))
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
                return String(localized: "\(name) as \(role)")
            }
            return name
        }
    }

    /// Fractional playback progress (0...1) from resume data, if any.
    var playbackProgress: Double? {
        guard let percentage = userData?.playedPercentage, percentage.isFinite else { return nil }
        return min(1, max(0, percentage / 100.0))
    }

    /// Decorative artwork fallback for the item's media type.
    var artworkPlaceholderSymbol: String {
        switch type {
        case .book, .audioBook: return "book"
        case .audio, .musicAlbum, .musicArtist, .playlist: return "music.note"
        case .series, .season, .episode: return "tv"
        case .photo, .photoAlbum: return "photo"
        case .boxSet: return "rectangle.stack"
        default: return "film"
        }
    }

    /// SF Symbol representing a library's collection type.
    var librarySymbol: String {
        switch collectionType {
        case .movies: return "film"
        case .tvshows: return "tv"
        case .music: return "music.note"
        case .books: return "book"
        case .photos: return "photo"
        case .livetv: return "antenna.radiowaves.left.and.right"
        default: return "rectangle.stack"
        }
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

/// Spoken identity is independent of compact visual captions and artwork.
struct MediaItemAccessibility: Equatable {
    let label: String
    let value: String
}

extension MediaItem {
    var mediaAccessibility: MediaItemAccessibility {
        var identity: [String] = []
        if type == .episode {
            if let seriesName {
                identity.append(seriesName)
            }
            if let season = parentIndexNumber {
                identity.append(String(localized: "Season \(season.formatted())"))
            }
            if let episode = indexNumber {
                identity.append(String(localized: "Episode \(episode.formatted())"))
            }
        }
        identity.append(displayTitle)
        if let program = currentProgramName {
            identity.append(String(localized: "Now playing \(program)"))
        }
        var details: [String] = []
        if type != .book, let ticks = runTimeTicks, ticks > 0 {
            let duration = Duration.seconds(Double(ticks) / 10_000_000).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
            details.append(String(localized: "Duration: \(duration)"))
        }
        let position = max(0, userData?.playbackPositionTicks ?? 0)
        let progress = playbackProgress ?? 0
        if type == .liveChannel || type == .liveProgram {
            details.append(String(localized: "Live"))
        } else if position > 0 || (progress > 0 && progress < 1) {
            details.append(userData?.isWatched == true ? (isAudioPlayable ? String(localized: "Listening Again") : String(localized: "Rewatching")) : String(localized: "In Progress"))
            if type != .book, let ticks = runTimeTicks, ticks > position, position > 0 {
                let remaining = Duration.seconds(Double(ticks - position) / 10_000_000).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
                details.append(String(localized: "\(remaining) remaining"))
            } else if progress.isFinite, progress > 0, progress < 1 {
                details.append(String(localized: "Playback progress \(progress.formatted(.percent.precision(.fractionLength(0))))"))
            }
        } else if let watched = userData?.isWatched, [MediaItemType.movie, .episode, .audio, .audioBook, .video, .recording].contains(type ?? .unknown) {
            details.append(watched ? (isAudioPlayable ? String(localized: "Played") : String(localized: "Watched")) : (isAudioPlayable ? String(localized: "Unplayed") : String(localized: "Unwatched")))
        }
        if userData?.isFavorite == true {
            details.append(String(localized: "Favorite"))
        }
        func joined(_ components: [String]) -> String {
            var seen = Set<String>()
            return components.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ", ")
        }
        return MediaItemAccessibility(label: joined(identity), value: joined(details))
    }
}

enum BookDetailMetadata {
    static func synopsis(_ value: String?) -> String? {
        let cleaned = value?.replacingOccurrences(of: #"\r\n"#, with: "\n")
            .replacingOccurrences(of: #"\n"#, with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
        return nonblank(cleaned)
    }

    static func genres(_ values: [String]) -> [String] {
        let values = values.compactMap { nonblank($0) }
        guard values.count == 1, let packed = values.first else { return uniqueGenres(values) }

        // The source catalog uses commas both as a separator and inside this genre name.
        let compound = "Movie, TV & Video Game Tie-Ins"
        let protected = packed.replacingOccurrences(of: compound, with: "Movie\u{1F} TV & Video Game Tie-Ins", options: .caseInsensitive)
        var quoted = false
        var names: [String] = []
        var name = ""
        for character in protected {
            if character == "\"" {
                quoted.toggle()
            } else if !quoted, character == "," || character == ";" || character.isNewline {
                names.append(name)
                name = ""
            } else {
                name.append(character)
            }
        }
        guard !quoted else { return values }
        names.append(name)
        return uniqueGenres(names.map { $0.replacingOccurrences(of: "\u{1F}", with: ",") })
    }

    private static func uniqueGenres(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { nonblank($0) }.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func nonblank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func epubFraction(locator: String?) -> Double? {
        guard let data = locator?.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let locations = object["locations"] as? [String: Any] else { return nil }
        return locations["totalProgression"] as? Double
    }

    static func credit(for person: MediaPerson) -> String {
        let role = nonblank(person.role)
        if role?.caseInsensitiveCompare("Narrator") == .orderedSame {
            return String(localized: "Narrator")
        }
        switch person.creditType?.lowercased() {
        case "author", "writer": return String(localized: "Author")
        case "narrator": return String(localized: "Narrator")
        case "illustrator": return String(localized: "Illustrator")
        case "translator": return String(localized: "Translator")
        case "coverartist": return String(localized: "Cover Artist")
        case "editor": return String(localized: "Editor")
        default: return role ?? String(localized: "Contributor")
        }
    }
}

extension MediaItem {
    var isBookFormat: Bool {
        type == .book || type == .audioBook
    }
}
