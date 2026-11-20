import Foundation

/// Structured search terms. Seerr identifiers are resolved from the authenticated server.
struct SeerrSearchIntent: Hashable, Sendable {
    var mediaType: String?
    var keywords: [String] = []
    var genres: [String] = []
    var people: [String] = []
    var credits: [GusCreditRequirement] = []
    var characters: [String] = []
    var themes: [String] = []
    var unsupported: [String] = []
    var minimumYear: Int?
    var maximumYear: Int?

    var types: [SeerrMediaType] {
        mediaType.flatMap(SeerrMediaType.init(rawValue:)).map { [$0] } ?? [.movie, .tv]
    }

    var isSupported: Bool {
        let terms = [keywords, genres, people, characters, themes]
        return unsupported.isEmpty &&
            (mediaType == nil || ["movie", "tv", "person"].contains(mediaType)) &&
            terms.allSatisfy { $0.count <= 8 && $0.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 160 } } &&
            [minimumYear, maximumYear].compactMap { $0 }.allSatisfy { (1 ... 9999).contains($0) } &&
            (minimumYear ?? 1) <= (maximumYear ?? 9999) &&
            credits.count <= 8 && credits.allSatisfy(\.isSupported) &&
            (mediaType != nil || minimumYear != nil || maximumYear != nil || !credits.isEmpty || terms.contains { !$0.isEmpty }) &&
            (mediaType != "person" || (!keywords.isEmpty && genres.isEmpty && people.isEmpty && credits.isEmpty && characters.isEmpty && minimumYear == nil && maximumYear == nil && themes.isEmpty))
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        words(lhs) == words(rhs)
    }

    static func genreMatches(_ requested: String, _ returned: String, forRetrieval: Bool = false) -> Bool {
        let sciFi = ["sci fi", "science fiction", "scifi"]
        let genre = words(returned).joined(separator: " ")
        let query = words(requested).joined(separator: " ")
        return query == genre || (sciFi.contains(query) && (sciFi.contains(genre) || (forRetrieval && genre == "sci fi fantasy")))
    }

    /// Hard constraints are checked against one title. Theme terms must have supporting text on the title.
    func score(_ title: SeerrTitle) -> Int? {
        guard let type = title.mediaType, [.movie, .tv, .person].contains(type),
              mediaType == nil || type.rawValue == mediaType else { return nil }
        if minimumYear != nil || maximumYear != nil {
            guard let value = title.releaseYear.flatMap(Int.init), value >= (minimumYear ?? 1), value <= (maximumYear ?? 9999) else { return nil }
        }
        let cast = title.credits?.cast ?? []
        let crew = title.credits?.crew ?? []
        let description = " " + Self.words([title.overview ?? "", title.tagline ?? ""].joined(separator: " ")).joined(separator: " ") + " "
        guard genres.allSatisfy({ genre in
                  title.genres?.contains { category in
                      if Self.genreMatches(genre, category.name) {
                          return true
                      }
                      // TMDB groups science fiction with fantasy for TV. The combined category
                      // alone cannot establish the narrower genre requested by the user.
                      return Self.genreMatches(genre, category.name, forRetrieval: true) &&
                          (description.contains(" sci fi ") || description.contains(" science fiction "))
                  } == true
              }),
              people.allSatisfy({ name in (cast + crew).contains { Self.sameName(name, $0.name) } }),
              credits.allSatisfy({ requirement in
                  cast.contains { requirement.matches(name: $0.name, role: "actor") } ||
                      crew.contains { requirement.matches(name: $0.name, role: $0.job) }
              }),
              characters.allSatisfy({ name in cast.contains { CatalogNameMatching.role($0.character, matches: name) } }) else { return nil }

        let name = " " + Self.words(title.displayTitle).joined(separator: " ") + " "
        let titleMatch = keywords.contains { name.contains(" " + Self.words($0).joined(separator: " ") + " ") }
        guard keywords.isEmpty || titleMatch else { return nil }
        let words = Set(Self.words([title.displayTitle, title.overview ?? "", title.tagline ?? ""].joined(separator: " ")))
        let matches = Set(themes.flatMap(Self.words)).intersection(words).count
        guard themes.isEmpty || matches > 0 else { return nil }
        return matches + (titleMatch ? 2 : 0)
    }
}
