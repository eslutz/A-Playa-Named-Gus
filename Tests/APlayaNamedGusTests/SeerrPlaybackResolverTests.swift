import Foundation
@testable import Gus
import Testing

@Suite("Seerr authenticated Jellyfin identity matching")
@MainActor
struct SeerrPlaybackResolverTests {
    @Test("every shared external-ID namespace must agree")
    func rejectsConflictingNamespaces() {
        #expect(!SeerrPlaybackResolver.identitiesMatch(["tmdb": "100", "imdb": "tt100"], ["tmdb": "100", "imdb": "tt999"]))
        #expect(!SeerrPlaybackResolver.identitiesMatch(["tmdb": "100", "imdb": "tt100"], ["tmdb": "999", "imdb": "tt100"]))
        #expect(!SeerrPlaybackResolver.identitiesMatch(["tmdb": "100"], ["imdb": "100"]))
        #expect(!SeerrPlaybackResolver.identitiesMatch(["tmdb": "100"], [:]))
        #expect(!SeerrPlaybackResolver.identitiesMatch(["unsupported": "100"], ["unsupported": "100"]))
        #expect(SeerrPlaybackResolver.identitiesMatch(["TMDB": "100", "IMDB": " ttABC "], ["tmdb": "100", "imdb": "ttabc"]))
    }

    @Test("equal TMDB numbers cannot cross movie and series namespaces")
    func rejectsWrongMediaType() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let movie = Self.item("movie", type: .movie, ids: ["tmdb": "100"])
        let series = Self.item("series", type: .series, ids: ["tmdb": "100"])
        provider.itemsHandler = { query in
            #expect(query.includeTypes == [.movie] || query.includeTypes == [.series])
            return .init(items: [movie, series], totalRecordCount: 2)
        }
        let movieMatches = try await SeerrPlaybackResolver.matches(title: SeerrTitle(id: 100, mediaType: .movie), provider: provider)
        let seriesMatches = try await SeerrPlaybackResolver.matches(title: SeerrTitle(id: 100, mediaType: .tv), provider: provider)
        #expect(movieMatches.map(\.id) == ["movie"])
        #expect(seriesMatches.map(\.id) == ["series"])
    }

    @Test("authenticated pagination returns exact accessible matches and ignores advertised server IDs")
    func paginatesAccessibleMetadata() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let first = Self.item("visible-first", type: .movie, ids: ["tmdb": "100", "imdb": "tt100"])
        let conflicting = Self.item("wrong-imdb", type: .movie, ids: ["tmdb": "100", "imdb": "tt999"])
        let second = Self.item("visible-second", type: .movie, ids: ["Tmdb": "100", "Imdb": "tt100"])
        let wrongType = Self.item("same-number-series", type: .series, ids: ["tmdb": "100", "imdb": "tt100"])
        var offsets: [Int] = []
        provider.itemsHandler = { query in
            offsets.append(query.startIndex)
            #expect(query.includeTypes == [.movie])
            #expect(query.isRecursive)
            #expect(query.limit == 200)
            switch query.startIndex {
            case 0: return .init(items: [first, conflicting], totalRecordCount: 5)
            case 2: return .init(items: [first, second], totalRecordCount: 5)
            default: return .init(items: [wrongType], totalRecordCount: 5)
            }
        }
        let title = SeerrTitle(
            id: 100,
            mediaType: .movie,
            mediaInfo: SeerrMediaInfo(id: 900, tmdbId: 100, status: .available, jellyfinMediaId: "server-only-inaccessible"),
            externalIds: SeerrExternalIDs(imdbId: "tt100")
        )
        let matches = try await SeerrPlaybackResolver.matches(title: title, provider: provider)
        #expect(offsets == [0, 2, 4])
        #expect(matches.map(\.id) == ["visible-first", "visible-second"])
        #expect(!matches.contains { $0.id == "server-only-inaccessible" })
    }

    @Test("repeated pages terminate without creating duplicate playback choices")
    func stopsRepeatedPages() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let match = Self.item("visible", type: .movie, ids: ["tmdb": "100"])
        var calls = 0
        provider.itemsHandler = { _ in
            calls += 1
            return .init(items: [match], totalRecordCount: 500)
        }
        let matches = try await SeerrPlaybackResolver.matches(title: SeerrTitle(id: 100, mediaType: .movie), provider: provider)
        #expect(calls == 2)
        #expect(matches.map(\.id) == ["visible"])
    }

    @Test("household restrictions exclude matching mature and unrated playback candidates")
    func appliesContentRestrictions() async throws {
        let suite = "gus-seerr-playback-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(ContentRatingGate.Limit.general.rawValue, forKey: ContentRatingGate.limitDefaultsKey)
        defaults.set(true, forKey: ContentRatingGate.hideUnratedDefaultsKey)
        let provider = FakeMediaProviderSession(capabilities: .init())
        let general = Self.item("general", type: .movie, ids: ["tmdb": "100"], rating: "G")
        let mature = Self.item("mature", type: .movie, ids: ["tmdb": "100"], rating: "R")
        let unrated = Self.item("unrated", type: .movie, ids: ["tmdb": "100"], rating: nil)
        provider.itemsHandler = { _ in .init(items: [general, mature, unrated], totalRecordCount: 3) }
        let matches = try await SeerrPlaybackResolver.matches(title: SeerrTitle(id: 100, mediaType: .movie), provider: provider, userDefaults: defaults)
        #expect(matches.map(\.id) == ["general"])
    }

    @Test("season zero is resolved from matching accessible series and must have the exact season type and index")
    func resolvesSpecialsSeason() async throws {
        let suite = "gus-seerr-specials-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(ContentRatingGate.Limit.general.rawValue, forKey: ContentRatingGate.limitDefaultsKey)
        defaults.set(true, forKey: ContentRatingGate.hideUnratedDefaultsKey)
        let provider = FakeMediaProviderSession(capabilities: .init())
        let matching = Self.item("matching-series", type: .series, ids: ["tmdb": "100"], rating: "TV-G")
        let other = Self.item("other-series", type: .series, ids: ["tmdb": "999"], rating: "TV-G")
        provider.itemsHandler = { _ in .init(items: [matching, other], totalRecordCount: 2) }
        var seasonCalls = 0
        provider.seasonsHandler = {
            seasonCalls += 1
            return [
                MediaItem(id: "specials", indexNumber: 0, officialRating: "TV-G", type: .season),
                MediaItem(id: "regular", indexNumber: 1, officialRating: "TV-G", type: .season),
                MediaItem(id: "wrong-type", indexNumber: 0, officialRating: "G", type: .movie),
                MediaItem(id: "restricted-specials", indexNumber: 0, officialRating: "TV-MA", type: .season),
            ]
        }
        let matches = try await SeerrPlaybackResolver.matches(
            title: SeerrTitle(id: 100, mediaType: .tv),
            provider: provider,
            seasonNumber: 0,
            userDefaults: defaults
        )
        #expect(seasonCalls == 1)
        #expect(matches.map(\.id) == ["specials"])
    }

    private static func item(_ id: String, type: MediaItemType, ids: [String: String], rating: String? = "G") -> MediaItem {
        var item = MediaItem(id: id, officialRating: rating, type: type)
        item.externalIDs = ids
        return item
    }
}
