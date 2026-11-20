#if canImport(FoundationModels) && !os(tvOS)
    import Foundation
    import FoundationModels

    @available(watchOS 27, *)
    @Generable
    struct RequestedCredit: Sendable {
        @Guide(description: "Copy the words that specify this person's job from the request, such as ‘narrated by’ or ‘write’. A title or a name alone is not evidence of a job.")
        var jobPhrase: String
        var name: String
        @Guide(description: "Job required for this person", .anyOf(["actor", "director", "writer", "producer", "composer", "author", "narrator", "artist"]))
        var role: String
    }

    @available(watchOS 27, *)
    @Generable
    struct RequestedRange: Sendable {
        @Guide(description: "Copy the exact words from the request that describe this range, including the number or time expression.")
        var phrase: String
        @Guide(description: "Inclusive lower bound. Omit for an upper bound alone.")
        var minimum: Int?
        @Guide(description: "Inclusive upper bound. Omit for a lower bound alone. An exact value has equal bounds.")
        var maximum: Int?

        func bounds(in prompt: String) throws -> (Int?, Int?) {
            let text = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                guard (minimum ?? 0) == 0, (maximum ?? 0) == 0 else { throw GusIntelligenceError.invalidResponse }
                return (nil, nil)
            }
            guard prompt.localizedCaseInsensitiveContains(text), minimum != nil || maximum != nil,
                  (minimum ?? .min) <= (maximum ?? .max) else { throw GusIntelligenceError.invalidResponse }
            return (minimum, maximum)
        }
    }

    @available(watchOS 27, *)
    @Generable
    struct SearchTerms: Sendable {
        @Guide(description: "Release year constraint, only when requested. For a single release year use the same year for both bounds.")
        var releaseYears: RequestedRange?
        @Guide(description: "Titles or people being looked up directly. Leave empty when finding titles by contributor, genre, or date.")
        var keywords: [String]
        @Guide(description: "Genres explicitly requested, such as science fiction. Empty for title lookups.")
        var genres: [String]
        @Guide(description: "Names with no specified job. A person with a requested job belongs only in credits.")
        var people: [String]
        @Guide(description: "Only the named person and job requested. Omit other possible jobs. For example, writing a book calls for author, and reading it aloud calls for narrator.")
        var credits: [RequestedCredit]
        var characters: [String]
        @Guide(description: "Soft descriptive terms or plot motifs")
        var themes: [String]
        @Guide(description: "Verbatim phrases from the request for constraints that cannot be represented. Empty when the request is fully supported.")
        var unsupported: [String]
        func validated(in prompt: String) throws -> (credits: [GusCreditRequirement], minimumYear: Int?, maximumYear: Int?) {
            let groups = [keywords, genres, people, characters, themes, unsupported]
            let validTerms = groups.allSatisfy { terms in
                terms.count <= 8 && terms.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 160 }
            }
            let requiredCredits = try credits.compactMap { credit -> GusCreditRequirement? in
                let phrase = credit.jobPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
                guard prompt.localizedCaseInsensitiveContains(credit.name) else { throw GusIntelligenceError.invalidResponse }
                let namedTitle = keywords.contains { $0.localizedCaseInsensitiveCompare(credit.name) == .orderedSame }
                guard !phrase.isEmpty, phrase.localizedCaseInsensitiveCompare(credit.name) != .orderedSame,
                      prompt.localizedCaseInsensitiveContains(phrase)
                else {
                    guard namedTitle else { throw GusIntelligenceError.invalidResponse }
                    return nil
                }
                return GusCreditRequirement(name: credit.name, role: credit.role)
            }
            let (minimumYear, maximumYear) = try releaseYears?.bounds(in: prompt) ?? (nil, nil)
            guard validTerms, credits.count <= 8, requiredCredits.allSatisfy(\.isSupported),
                  (minimumYear ?? 1) >= 1, (maximumYear ?? 9999) <= 9999,
                  (minimumYear ?? 1) <= (maximumYear ?? 9999) else { throw GusIntelligenceError.invalidResponse }
            return (requiredCredits, minimumYear, maximumYear)
        }
    }

    @available(watchOS 27, *)
    @Generable
    struct LibraryQuery: Sendable {
        var terms: SearchTerms
        @Guide(description: "Only requested types from movie, series, episode, book, audioBook, musicAlbum, audio")
        var mediaTypes: [String]
        @Guide(description: "Runtime or reading duration in minutes. Omit the entire range unless the person requested a duration.")
        var durationMinutes: RequestedRange?
        @Guide(description: "Use all unless the request explicitly asks for a viewing or playback state", .anyOf(["all", "unplayed", "played", "resumable"]))
        var status: String
        @Guide(description: "True only if the person explicitly asks for their favorites. Otherwise false.")
        var favoritesOnly: Bool

        func intent(for prompt: String) throws -> GusSearchIntent {
            let constraints = try terms.validated(in: prompt)
            let (minimumMinutes, maximumMinutes) = try durationMinutes?.bounds(in: prompt) ?? (nil, nil)
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
                credits: constraints.credits,
                characters: terms.characters,
                themes: terms.themes,
                unsupported: terms.unsupported,
                minimumYear: constraints.minimumYear,
                maximumYear: constraints.maximumYear,
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

        func intent(for prompt: String) throws -> SeerrSearchIntent {
            let constraints = try terms.validated(in: prompt)
            guard ["any", "movie", "tv", "person"].contains(mediaType),
                  mediaType != "any" || !constraints.credits.isEmpty || constraints.minimumYear != nil || constraints.maximumYear != nil
                  || [terms.keywords, terms.genres, terms.people, terms.characters, terms.themes, terms.unsupported].contains(where: { !$0.isEmpty })
            else { throw GusIntelligenceError.invalidResponse }
            return SeerrSearchIntent(
                mediaType: mediaType == "any" ? nil : mediaType,
                keywords: terms.keywords,
                genres: terms.genres,
                people: terms.people,
                credits: constraints.credits,
                characters: terms.characters,
                themes: terms.themes,
                unsupported: terms.unsupported,
                minimumYear: constraints.minimumYear,
                maximumYear: constraints.maximumYear
            ).normalizedPersonLookup()
        }
    }

    @available(watchOS 27, *)
    @Generable
    struct RankedHandles: Sendable {
        var handles: [Int]
    }
#endif
