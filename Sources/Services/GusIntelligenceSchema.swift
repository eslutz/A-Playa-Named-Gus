#if canImport(FoundationModels) && !os(tvOS)
    import Foundation
    import FoundationModels

    @available(watchOS 27, *)
    @Generable
    struct RequestedCredit: Sendable {
        var name: String
        @Guide(description: "Job required for this person", .anyOf(["actor", "director", "writer", "producer", "composer", "author", "narrator", "artist"]))
        var role: String
    }

    @available(watchOS 27, *)
    @Generable
    struct SearchTerms: Sendable {
        @Guide(description: "Explicit title or name lookups")
        var keywords: [String]
        @Guide(description: "Genres explicitly requested, such as science fiction. Empty for title lookups.")
        var genres: [String]
        @Guide(description: "Credited people whose job was not specified")
        var people: [String]
        var credits: [RequestedCredit]
        var characters: [String]
        @Guide(description: "Soft descriptive terms or plot motifs")
        var themes: [String]
        @Guide(description: "Verbatim phrases from the request for constraints that cannot be represented. Empty when the request is fully supported.")
        var unsupported: [String]
        @Guide(description: "Inclusive earliest requested release year")
        var minimumYear: Int?
        @Guide(description: "Inclusive latest requested release year")
        var maximumYear: Int?

        var requiredCredits: [GusCreditRequirement] {
            credits.map { GusCreditRequirement(name: $0.name, role: $0.role) }
        }

        func validate() throws {
            let groups = [keywords, genres, people, characters, themes, unsupported]
            let validTerms = groups.allSatisfy { terms in
                terms.count <= 8 && terms.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 160 }
            }
            guard validTerms, credits.count <= 8, requiredCredits.allSatisfy(\.isSupported),
                  (minimumYear ?? 1) >= 1, (maximumYear ?? 9999) <= 9999,
                  (minimumYear ?? 1) <= (maximumYear ?? 9999) else { throw GusIntelligenceError.invalidResponse }
        }
    }

    @available(watchOS 27, *)
    @Generable
    struct LibraryQuery: Sendable {
        var terms: SearchTerms
        @Guide(description: "Only requested types from movie, series, episode, book, audioBook, musicAlbum, audio")
        var mediaTypes: [String]
        var minimumMinutes: Int?
        var maximumMinutes: Int?
        @Guide(description: "Use all unless the request explicitly asks for a viewing or playback state", .anyOf(["all", "unplayed", "played", "resumable"]))
        var status: String
        @Guide(description: "True only if the person explicitly asks for their favorites. Otherwise false.")
        var favoritesOnly: Bool

        func intent() throws -> GusSearchIntent {
            try terms.validate()
            let types = mediaTypes.compactMap(MediaItemType.init(rawValue:))
            let allowed: Set<MediaItemType> = [.movie, .series, .episode, .book, .audioBook, .musicAlbum, .audio]
            guard types.count == mediaTypes.count, types.allSatisfy(allowed.contains),
                  let status = MediaItemStatusFilter(rawValue: status),
                  (minimumMinutes ?? 0) >= 0, (minimumMinutes ?? 0) <= (maximumMinutes ?? .max) else { throw GusIntelligenceError.invalidResponse }
            let value = GusSearchIntent(
                mediaTypes: types,
                keywords: terms.keywords,
                genres: terms.genres,
                people: terms.people,
                credits: terms.requiredCredits,
                characters: terms.characters,
                themes: terms.themes,
                unsupported: terms.unsupported,
                minimumYear: terms.minimumYear,
                maximumYear: terms.maximumYear,
                minimumMinutes: minimumMinutes,
                maximumMinutes: maximumMinutes,
                status: status,
                favoritesOnly: favoritesOnly
            )
            guard !value.appliedFilters.isEmpty || !value.unsupported.isEmpty else { throw GusIntelligenceError.invalidResponse }
            return value
        }
    }

    @available(watchOS 27, *)
    @Generable
    struct DiscoverQuery: Sendable {
        var terms: SearchTerms
        @Guide(description: "The requested result type", .anyOf(["any", "movie", "tv", "person"]))
        var mediaType: String

        func intent() throws -> SeerrSearchIntent {
            try terms.validate()
            guard ["any", "movie", "tv", "person"].contains(mediaType),
                  mediaType != "any" || !terms.credits.isEmpty || terms.minimumYear != nil || terms.maximumYear != nil
                  || [terms.keywords, terms.genres, terms.people, terms.characters, terms.themes, terms.unsupported].contains(where: { !$0.isEmpty })
            else { throw GusIntelligenceError.invalidResponse }
            return SeerrSearchIntent(
                mediaType: mediaType == "any" ? nil : mediaType,
                keywords: terms.keywords,
                genres: terms.genres,
                people: terms.people,
                credits: terms.requiredCredits,
                characters: terms.characters,
                themes: terms.themes,
                unsupported: terms.unsupported,
                minimumYear: terms.minimumYear,
                maximumYear: terms.maximumYear
            ).normalizedPersonLookup()
        }
    }

    @available(watchOS 27, *)
    @Generable
    struct RankedHandles: Sendable {
        var handles: [Int]
    }
#endif
