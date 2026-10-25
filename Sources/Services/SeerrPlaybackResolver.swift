import Foundation

/// Seerr's availability and server-side Jellyfin ID never grant access to the signed-in account.
enum SeerrPlaybackResolver {
    static func externalIDs(for title: SeerrTitle) -> [String: String] {
        var ids = ["tmdb": String(title.id)]
        if let imdb = title.externalIds?.imdbId {
            ids["imdb"] = imdb
        }
        if let tvdb = title.externalIds?.tvdbId {
            ids["tvdb"] = String(tvdb)
        }
        return ids
    }

    static func identitiesMatch(_ first: [String: String], _ second: [String: String]) -> Bool {
        func normalize(_ ids: [String: String]) -> [String: String] {
            ids.reduce(into: [:]) { result, pair in
                let key = pair.key.lowercased()
                let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["tmdb", "tvdb", "imdb"].contains(key), !value.isEmpty {
                    result[key] = value
                }
            }
        }
        let first = normalize(first), second = normalize(second)
        let shared = Set(first.keys).intersection(second.keys)
        return !shared.isEmpty && shared.allSatisfy { first[$0] == second[$0] }
    }

    /// Jellyfin's supported public Items API has no external-ID filter. Scan authenticated,
    /// paginated metadata on explicit user action; verify every namespace before offering a match.
    @MainActor static func matches(title: SeerrTitle, provider: any MediaProviderSession, seasonNumber: Int? = nil, userDefaults: UserDefaults = .standard) async throws -> [MediaItem] {
        guard title.mediaType == .movie || title.mediaType == .tv else { return [] }
        let type: MediaItemType = title.mediaType == .tv ? .series : .movie
        let identity = externalIDs(for: title)
        var matches: [MediaItem] = [], seen = Set<String>(), start = 0
        while true {
            try Task.checkCancellation()
            let page = try await provider.items(query: MediaItemQuery(includeTypes: [type], startIndex: start, limit: 200, isRecursive: true))
            var added = 0
            for item in page.items {
                guard let id = item.id, seen.insert(id).inserted else { continue }
                added += 1
                if item.type == type, identitiesMatch(identity, item.externalIDs), ContentRatingGate.admitsStored(item, userDefaults: userDefaults) {
                    matches.append(item)
                }
            }
            start += page.items.count
            if page.items.isEmpty || added == 0 || page.totalRecordCount.map({ start >= $0 }) == true {
                break
            }
            if page.totalRecordCount == nil, page.items.count < 200 {
                break
            }
        }
        guard let seasonNumber else { return matches }
        guard title.mediaType == .tv else { return [] }
        var seasons: [MediaItem] = []
        for series in matches {
            try Task.checkCancellation()
            guard let id = series.id else { continue }
            seasons += try await provider.seasons(seriesID: id).filter {
                $0.type == .season && $0.indexNumber == seasonNumber && ContentRatingGate.admitsStored($0, userDefaults: userDefaults)
            }
        }
        return seasons
    }
}
