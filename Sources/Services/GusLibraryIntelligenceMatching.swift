import Foundation

struct GusLibraryPick: Identifiable, Sendable {
    let item: MediaItem
    let reason: String
    var id: String? {
        item.id
    }
}

/// Hard constraints are evaluated from Jellyfin metadata, including on the refreshed record.
enum GusLibraryMatching {
    static let types: [MediaItemType] = [.movie, .series, .episode, .book, .audioBook, .musicAlbum, .audio]

    static func words(_ value: String) -> [String] {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func normalized(_ value: String) -> String {
        words(value).joined(separator: " ")
    }

    static func contains(_ text: String, phrase: String) -> Bool {
        let needle = normalized(phrase)
        return !needle.isEmpty && " \(normalized(text)) ".contains(" \(needle) ")
    }

    static func creators(_ item: MediaItem) -> [String] {
        item.artists + [item.albumArtist].compactMap { $0 } + item.people.compactMap(\.name)
    }

    static func description(_ item: MediaItem) -> String {
        ([item.overview, item.album, item.seriesName].compactMap { $0 } + item.genres + item.taglines).joined(separator: " ")
    }

    /// Exact genre aliases cover Jellyfin's common representations without substring matches.
    private static func genre(_ value: String) -> String {
        switch normalized(value) {
        case "sci fi", "scifi", "science fiction": "science fiction"
        default: normalized(value)
        }
    }

    static func isInProgress(_ item: MediaItem) -> Bool {
        (item.userData?.playbackPositionTicks ?? 0) > 0 || (item.userData?.playedPercentage ?? 0) > 0
    }

    static func accepts(_ item: MediaItem, intent: GusSearchIntent) -> Bool {
        guard let type = item.type, types.contains(type), item.id != nil, intent.unsupported.isEmpty,
              intent.mediaTypes.isEmpty || intent.mediaTypes.contains(type),
              !intent.favoritesOnly || item.userData?.isFavorite == true else { return false }
        if let year = intent.minimumYear, item.productionYear.map({ $0 >= year }) != true {
            return false
        }
        if let year = intent.maximumYear, item.productionYear.map({ $0 <= year }) != true {
            return false
        }
        let minutes = item.runTimeTicks.map { Double($0) / 600_000_000 }
        if let minimum = intent.minimumMinutes, minutes.map({ $0 >= Double(minimum) }) != true {
            return false
        }
        if let maximum = intent.maximumMinutes, minutes.map({ $0 <= Double(maximum) }) != true {
            return false
        }
        switch intent.status {
        case .played: guard item.userData?.isWatched == true else { return false }
        case .unplayed: guard item.userData?.isWatched == false, !isInProgress(item) else { return false }
        case .resumable: guard item.userData?.isWatched != true, isInProgress(item) else { return false }
        case .all: break
        }
        let genres = Set(item.genres.map(genre))
        guard intent.genres.allSatisfy({ genres.contains(genre($0)) }) else { return false }
        let names = Set(creators(item).map(normalized))
        guard intent.people.allSatisfy({ names.contains(normalized($0)) }),
              intent.credits.allSatisfy({ hasCredit($0, item: item) }) else { return false }
        // A cast member may have several credited roles, e.g. "Bruce Wayne / Batman".
        let roles = item.people.compactMap(\.role)
        guard intent.characters.allSatisfy({ character in roles.contains { CatalogNameMatching.role($0, matches: character) } }) else { return false }
        let titleNames = [item.name, item.album, item.seriesName].compactMap { $0 } + creators(item)
        guard intent.keywords.allSatisfy({ keyword in titleNames.contains { contains($0, phrase: keyword) } }) else { return false }
        let text = (titleNames + roles + [description(item)]).joined(separator: " ")
        let themes = intent.themes.flatMap(words)
        return themes.isEmpty || !Set(themes).isDisjoint(with: Set(words(text)))
    }

    private static func hasCredit(_ credit: GusCreditRequirement, item: MediaItem) -> Bool {
        if item.type == .book || item.type == .audioBook {
            if item.bookNarratorNames.contains(where: { credit.matches(name: $0, role: "narrator") }) {
                return true
            }
            if item.bookAuthorNames.contains(where: { credit.matches(name: $0, role: "author") }) {
                return true
            }
        }
        if item.type == .audio || item.type == .musicAlbum {
            let artists = item.artists + [item.albumArtist].compactMap { $0 }
            if artists.contains(where: { credit.matches(name: $0, role: "artist") }) {
                return true
            }
        }
        return item.people.contains { credit.matches(name: $0.name, role: $0.creditType) }
    }

    static func completions(in items: [MediaItem], prefix: String) -> [String] {
        let query = normalized(prefix)
        guard !query.isEmpty else { return [] }
        var seen = Set([query])
        var results: [String] = []
        for item in items {
            for name in [item.name].compactMap({ $0 }) + creators(item) {
                let key = normalized(name)
                if key.hasPrefix(query) || key.contains(" " + query), seen.insert(key).inserted {
                    results.append(name)
                    if results.count == 6 {
                        return results
                    }
                }
            }
        }
        return results
    }

    struct Taste {
        var weights: [String: Int] = [:]
        var tags: [String: String] = [:]
        var seedIDs: Set<String> = []
        var traits: [String] {
            weights.keys.sorted { a, b in
                let lhs = weights[a, default: 0], rhs = weights[b, default: 0]
                return lhs == rhs ? a < b : lhs > rhs
            }.prefix(16).compactMap { tags[$0] }
        }

        init(seeds: [MediaItem]) {
            for item in seeds {
                guard let id = item.id, seedIDs.insert(id).inserted else { continue }
                let weight = item.userData?.isFavorite == true ? 3 : 1
                for (key, value) in Self.tags(for: item) {
                    weights[key, default: 0] += weight
                    tags[key] = value
                }
            }
        }

        private static func tags(for item: MediaItem) -> [String: String] {
            var tags = [String: String]()
            for name in item.genres {
                tags["genre:" + normalized(name)] = name
            }
            for name in creators(item) {
                tags["creator:" + normalized(name)] = name
            }
            return tags.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        func ranked(_ items: [MediaItem]) -> [GusLibraryPick] {
            let scored = items.compactMap { item -> (GusLibraryPick, Int)? in
                guard let id = item.id, !seedIDs.contains(id), item.userData?.isWatched != true,
                      item.userData?.isFavorite != true, !isInProgress(item) else { return nil }
                let tags = Self.tags(for: item)
                let matches = tags.keys.filter { weights[$0] != nil }.sorted { a, b in
                    let lhs = weights[a, default: 0], rhs = weights[b, default: 0]
                    return lhs == rhs ? a < b : lhs > rhs
                }
                guard let best = matches.first, let name = tags[best] else { return nil }
                let reason = String(localized: "Matches your interest in \(name).")
                return (GusLibraryPick(item: item, reason: reason), matches.reduce(0) { $0 + weights[$1, default: 0] })
            }.sorted { lhs, rhs in
                lhs.1 == rhs.1 ? (lhs.0.id ?? "") < (rhs.0.id ?? "") : lhs.1 > rhs.1
            }
            // Give each represented media type a place before filling the shortlist by affinity.
            var seenTypes = Set<MediaItemType>(), first: [GusLibraryPick] = [], rest: [GusLibraryPick] = []
            for (pick, _) in scored {
                if let type = pick.item.type, seenTypes.insert(type).inserted {
                    first.append(pick)
                } else {
                    rest.append(pick)
                }
            }
            return first + rest
        }
    }
}

/// A credited character may have multiple named aliases. A role like “Joker’s henchman”
/// does not establish a credit for the Joker himself.
enum CatalogNameMatching {
    static func role(_ role: String?, matches name: String) -> Bool {
        guard let role else { return false }
        let requested = GusLibraryMatching.words(name)
        guard !requested.isEmpty else { return false }
        return role.split(whereSeparator: { $0 == "/" || $0 == ";" }).contains { component in
            let actual = GusLibraryMatching.words(String(component.prefix { $0 != "(" }))
            return actual == requested || (actual.first == "the" && actual.dropFirst().elementsEqual(requested))
        }
    }
}
