import Foundation

extension MediaItem {
    var displayTitle: String {
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if type == .episode, let indexNumber,
           title?.isEmpty != false || title?.localizedCaseInsensitiveCompare(seriesName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") == .orderedSame
        {
            return String(localized: "Episode \(indexNumber.formatted())")
        }
        if let title, !title.isEmpty {
            return title
        }
        return String(localized: "Untitled", comment: "Fallback item title")
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
        displayYear.map(String.init)
    }

    var displayYear: Int? {
        if let productionYear {
            return productionYear
        }
        guard isBookFormat, let premiereDate else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.component(.year, from: premiereDate)
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
        guard type != .boxSet, let percentage = userData?.playedPercentage, percentage.isFinite else { return nil }
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
            type: .series
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
        mediaAccessibility(showSeriesProgress: UserDefaults.standard.bool(forKey: Self.seriesProgressKey))
    }

    static var seriesProgressKey: String {
        "showSeriesProgress"
    }

    func cardProgress(showSeriesProgress: Bool) -> Double? {
        guard type != .series || showSeriesProgress,
              let progress = playbackProgress, progress > 0, progress < 1 else { return nil }
        return progress
    }

    func mediaAccessibility(showSeriesProgress: Bool) -> MediaItemAccessibility {
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
        if isBookFormat {
            identity += [bookAuthorText, yearText].compactMap { $0 }
        }
        if let program = currentProgramName {
            identity.append(String(localized: "Now playing \(program)"))
        }
        var details: [String] = []
        if type != .book, let ticks = runTimeTicks, ticks > 0 {
            let duration = Duration.seconds(Double(ticks) / 10_000_000).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
            details.append(String(localized: "Duration: \(duration)"))
        }
        let position = type == .boxSet || type == .series ? 0 : max(0, userData?.playbackPositionTicks ?? 0)
        let progress = cardProgress(showSeriesProgress: showSeriesProgress) ?? 0
        if type == .liveChannel || type == .liveProgram {
            details.append(String(localized: "Live"))
        } else if position > 0 || (progress > 0 && progress < 1) {
            if userData?.isWatched == true, type == .book {
                details.append(String(localized: "Reading Again"))
            } else {
                details.append(userData?.isWatched == true ? (isAudioPlayable ? String(localized: "Listening Again") : String(localized: "Rewatching")) : String(localized: "In Progress"))
            }
            if type != .book, let ticks = runTimeTicks, ticks > position, position > 0 {
                let remaining = Duration.seconds(Double(ticks - position) / 10_000_000).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
                details.append(String(localized: "\(remaining) remaining"))
            } else if progress.isFinite, progress > 0, progress < 1 {
                let percent = progress.formatted(.percent.precision(.fractionLength(0)))
                switch type {
                case .book: details.append(String(localized: "Reading progress \(percent)"))
                case .audioBook: details.append(String(localized: "Listening progress \(percent)"))
                default: details.append(String(localized: "Playback progress \(percent)"))
                }
            }
        } else if isBookFormat, let finished = userData?.isWatched {
            details.append(finished ? completedStatusTitle : (type == .book ? String(localized: "Unread") : String(localized: "Unfinished")))
        } else if let watched = userData?.isWatched, [MediaItemType.movie, .episode, .audio, .video, .recording].contains(type ?? .unknown) {
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
        guard var text = nonblank(value) else { return nil }
        text = text.replacingOccurrences(of: #"\r\n"#, with: "\n")
            .replacingOccurrences(of: #"\n"#, with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
        if text.contains("&") {
            // CommonMark decodes named and numeric HTML entities without loading remote content.
            // Parse only the entity itself so ordinary punctuation in a synopsis stays literal.
            text = text.replacing(#/&(?:#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]+);/#) { match in
                let entity = String(match.output)
                guard let decoded = try? AttributedString(markdown: entity, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return entity }
                return String(decoded.characters)
            }
        }
        if text.contains("<") {
            text = text.replacingOccurrences(of: #"(?is)<(script|style)\b[^>]*>.*?</\1\s*>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)<br\b[^>]*>"#, with: "\n", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)</?(p|div|li)\b[^>]*>"#, with: "\n\n", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)</?[a-z][\w:-]*(?:\s[^<>]*)?/?>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?:\n[\t ]*){3,}"#, with: "\n\n", options: .regularExpression)
        }
        return nonblank(text)
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

    fileprivate static func nonblank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func epubFraction(locator: String?) -> Double? {
        guard let data = locator?.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let locations = object["locations"] as? [String: Any] else { return nil }
        return locations["totalProgression"] as? Double
    }

    enum Byline { case author, narrator }

    static func byline(for person: MediaPerson) -> Byline? {
        let role = nonblank(person.role)?.lowercased()
        let kind = nonblank(person.creditType)?.lowercased()
        if role == "narrator" || kind == "narrator" {
            return .narrator
        }
        if ["author", "writer"].contains(kind) || ["author", "writer"].contains(role) {
            return .author
        }
        return nil
    }
}

extension MediaItem {
    private func contributorNames(_ byline: BookDetailMetadata.Byline) -> [String] {
        var seen: Set<String> = []
        return people.compactMap { person in
            guard BookDetailMetadata.byline(for: person) == byline,
                  let name = person.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, seen.insert(name.lowercased()).inserted else { return nil }
            return name
        }
    }

    var bookAuthorNames: [String] {
        let authors = contributorNames(.author)
        guard authors.isEmpty, type == .audioBook,
              let albumAuthor = BookDetailMetadata.nonblank(albumArtist),
              artists.contains(where: { BookDetailMetadata.nonblank($0)?.caseInsensitiveCompare(albumAuthor) == .orderedSame }),
              !bookNarratorNames.contains(where: { $0.caseInsensitiveCompare(albumAuthor) == .orderedSame })
        else { return authors }
        return [albumAuthor]
    }

    var bookNarratorNames: [String] {
        contributorNames(.narrator)
    }

    var bookAuthorText: String? {
        let names = bookAuthorNames
        return names.isEmpty ? nil : names.formatted(.list(type: .and))
    }

    var bookBrowseSubtitle: String? {
        guard isBookFormat else { return nil }
        let components = [bookAuthorText, yearText].compactMap { $0 }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    var completedStatusTitle: String {
        switch type {
        case .book: String(localized: "Read", comment: "Completed reading status")
        case .audioBook: String(localized: "Finished")
        default: String(localized: "Watched")
        }
    }

    var completionActionTitle: String {
        completionActionTitle(markingComplete: userData?.isWatched != true)
    }

    func completionActionTitle(markingComplete: Bool) -> String {
        let finished = !markingComplete
        switch type {
        case .book: return finished ? String(localized: "Mark as Unread") : String(localized: "Mark as Read")
        case .audioBook: return finished ? String(localized: "Mark as Unfinished") : String(localized: "Mark as Finished")
        default: return finished ? String(localized: "Mark as Unwatched") : String(localized: "Mark as Watched")
        }
    }

    /// Audio covers may belong to the album. Other titles use the poster sequence,
    /// including the tagged series cover when the item has one.
    var coverArtworkRole: MediaArtworkRole {
        isAudioPlayable && albumID != nil && albumPrimaryImageTag != nil ? .square : .poster
    }

    var hasTaggedCoverArtwork: Bool {
        imageTags["Primary"] != nil || imageTags["Thumb"] != nil || !backdropImageTags.isEmpty ||
            (seriesID != nil && seriesPrimaryImageTag != nil) || coverArtworkRole == .square
    }

    var isBookFormat: Bool {
        type == .book || type == .audioBook
    }
}

extension MediaItem {
    var genreSearchTargets: [RelatedSearch] {
        let byName = Dictionary(grouping: genreItems) { RelatedSearch.normalizedName($0.name ?? "") }
        let targets = genres.map { name in
            let matches = byName[RelatedSearch.normalizedName(name)] ?? []
            let ids = Set(matches.compactMap(\.id))
            return RelatedSearch(kind: .genre, id: ids.count == 1 ? ids.first : nil, name: name)
        }
        return uniqueRelatedTargets(targets)
    }

    var studioSearchTargets: [RelatedSearch] {
        uniqueRelatedTargets(studios.compactMap { studio in
            studio.name.map { RelatedSearch(kind: .studio, id: studio.id, name: $0) }
        })
    }

    private func uniqueRelatedTargets(_ targets: [RelatedSearch]) -> [RelatedSearch] {
        var seen = Set<String>()
        return targets.filter { !$0.name.isEmpty && seen.insert($0.identityKey).inserted }
    }
}
