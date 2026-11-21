import Foundation

/// All candidates come from this account's Seerr client. The model only proposes filters.
@MainActor enum SeerrNaturalSearch {
    static func results(for intent: SeerrSearchIntent, store: SeerrStore) async throws -> [SeerrTitle] {
        guard intent.isSupported else { throw SeerrClientError.invalidPayload }
        let client = try store.requireClient()
        let revision = store.revision
        let restriction = store.restrictionRevision
        func checkSession() throws {
            try Task.checkCancellation()
            guard store.revision == revision, store.restrictionRevision == restriction else { throw CancellationError() }
        }

        var pools: [[SeerrTitle]] = []
        var lookupTerms: [String] = []
        let people = intent.people + intent.credits.map(\.name)
        for term in intent.keywords + people + intent.characters where !lookupTerms.contains(term) {
            lookupTerms.append(term)
        }
        for term in lookupTerms.prefix(2) {
            try checkSession()
            let page = try await client.search(query: term)
            pools.append(page.results)
            if people.contains(term),
               let person = page.results.first(where: { $0.mediaType == .person && SeerrSearchIntent.sameName($0.displayTitle, term) })
            {
                try checkSession()
                let credits = try await client.personCredits(id: person.id)
                let roles = intent.credits.filter { SeerrSearchIntent.sameName($0.name, term) }
                if roles.isEmpty {
                    pools.append(credits.cast + credits.crew)
                } else {
                    let cast = roles.contains { $0.matches(name: term, role: "actor") } ? credits.cast : []
                    let crew = credits.crew.filter { title in
                        title.job == nil || roles.contains { $0.matches(name: term, role: title.job) }
                    }
                    pools.append(cast + crew)
                }
            }
        }

        // A named lookup alone doesn't need a popular feed. Each qualifying type gets
        // one page, leaving at most one additional page for a single-type search.
        if lookupTerms.isEmpty || !intent.genres.isEmpty || intent.minimumYear != nil || intent.maximumYear != nil {
            let types = intent.types.filter { $0 == .movie || $0 == .tv }
            for type in types {
                try checkSession()
                let directory = intent.genres.isEmpty ? [] : try await client.categories(type == .movie ? .movieGenres : .tvGenres)
                let ids = intent.genres.compactMap { genre in directory.first { SeerrSearchIntent.genreMatches(genre, $0.name, forRetrieval: true) }?.id }
                guard ids.count == intent.genres.count else { continue }
                for page in 1 ... (types.count == 1 ? 2 : 1) {
                    try checkSession()
                    let response = try await client.discoverTitles(type: type, genreIDs: ids, minimumYear: intent.minimumYear, maximumYear: intent.maximumYear, page: page)
                    pools.append(response.results)
                    if response.page >= response.totalPages {
                        break
                    }
                }
            }
        }
        try checkSession()

        // Interleave pools before the detail budget so one large credits page cannot
        // starve the second query. Revalidate all exact terms after fetching details.
        var seen = Set<String>()
        var candidates: [SeerrTitle] = []
        for index in 0 ..< (pools.map(\.count).max() ?? 0) {
            for pool in pools where index < pool.count {
                let title = pool[index]
                guard title.id > 0, let type = title.mediaType, [.person, .movie, .tv].contains(type),
                      intent.mediaType == nil || intent.mediaType == type.rawValue,
                      seen.insert(title.seerrCatalogID).inserted else { continue }
                candidates.append(title)
            }
            if candidates.count >= 24 {
                break
            }
        }
        let requiresDetails = !intent.genres.isEmpty || !people.isEmpty || !intent.characters.isEmpty
        let admitted = try await store.admitted(Array(candidates.prefix(24)), requiringDetails: requiresDetails)
        try checkSession()
        var scored: [(item: SeerrTitle, score: Int)] = []
        for item in admitted where store.admits(item) {
            if let score = intent.score(item) {
                scored.append((item, score))
            }
        }
        // Swift's stable sort preserves Seerr order for equal scores.
        return scored.sorted { $0.score > $1.score }.map(\.item)
    }
}

extension SeerrSearchIntent {
    var filterDescription: String {
        var values = keywords + genres + people
        values += credits.map(\.displayLabel)
        values += characters + themes
        switch mediaType {
        case "movie": values.insert(String(localized: "Movies"), at: 0)
        case "tv": values.insert(String(localized: "TV Series"), at: 0)
        case "person": values.insert(String(localized: "People"), at: 0)
        default: break
        }
        if let minimumYear {
            values.append(String(localized: "From \(String(minimumYear))"))
        }
        if let maximumYear {
            values.append(String(localized: "Through \(String(maximumYear))"))
        }
        return values.joined(separator: " · ")
    }
}
