import Foundation
@testable import Gus
import Testing

@Suite("Content rating gate")
struct ContentRatingGateTests {
    @Test("rating strings map to ranks across movie and TV systems")
    func ratingRanks() {
        #expect(ContentRatingGate.rank(for: "G") == 0)
        #expect(ContentRatingGate.rank(for: "TV-Y7") == 0)
        #expect(ContentRatingGate.rank(for: "PG") == 1)
        #expect(ContentRatingGate.rank(for: "TV-PG") == 1)
        #expect(ContentRatingGate.rank(for: "PG-13") == 2)
        #expect(ContentRatingGate.rank(for: "TV-14") == 2)
        #expect(ContentRatingGate.rank(for: "R") == 3)
        #expect(ContentRatingGate.rank(for: "TV-MA") == 3)
        #expect(ContentRatingGate.rank(for: "NC-17") == 4)
        #expect(ContentRatingGate.rank(for: " r ") == 3)
        #expect(ContentRatingGate.rank(for: nil) == nil)
        #expect(ContentRatingGate.rank(for: "Something Else") == nil)
    }

    @Test("limits admit content at or below their tier")
    func limitsAdmitByTier() {
        let kidsMovie = MediaItem(id: "1", name: "Kids", officialRating: "G", type: .movie)
        let teenMovie = MediaItem(id: "2", name: "Teen", officialRating: "PG-13", type: .movie)
        let matureShow = MediaItem(id: "3", name: "Mature", officialRating: "TV-MA", type: .series)

        #expect(ContentRatingGate.admits(kidsMovie, limit: .general, hideUnrated: false))
        #expect(!ContentRatingGate.admits(teenMovie, limit: .general, hideUnrated: false))
        #expect(ContentRatingGate.admits(teenMovie, limit: .teen, hideUnrated: false))
        #expect(!ContentRatingGate.admits(matureShow, limit: .teen, hideUnrated: false))
        #expect(ContentRatingGate.admits(matureShow, limit: .mature, hideUnrated: false))
        #expect(ContentRatingGate.admits(matureShow, limit: .off, hideUnrated: true))
    }

    @Test("unrated media follows the hide-unrated policy")
    func unratedPolicy() {
        let unrated = MediaItem(id: "1", name: "Mystery", type: .movie)

        #expect(ContentRatingGate.admits(unrated, limit: .teen, hideUnrated: false))
        #expect(!ContentRatingGate.admits(unrated, limit: .teen, hideUnrated: true))
    }

    @Test("containers and non-video kinds stay visible for navigation")
    func containersStayVisible() {
        let library = MediaItem(collectionType: .movies, id: "lib", name: "Movies", type: .collectionFolder)
        let album = MediaItem(id: "album", name: "Album", type: .musicAlbum)

        #expect(ContentRatingGate.admits(library, limit: .general, hideUnrated: true))
        #expect(ContentRatingGate.admits(album, limit: .general, hideUnrated: true))
    }

    @Test("filter respects the stored preference")
    func filterRespectsStoredPreference() throws {
        let defaults = try #require(UserDefaults(suiteName: "gus-rating-tests-\(UUID().uuidString)"))
        let items = [
            MediaItem(id: "1", name: "Kids", officialRating: "G", type: .movie),
            MediaItem(id: "2", name: "Mature", officialRating: "R", type: .movie),
        ]

        // Off by default: nothing filtered.
        #expect(ContentRatingGate.filter(items, userDefaults: defaults).count == 2)

        defaults.set(ContentRatingGate.Limit.general.rawValue, forKey: ContentRatingGate.limitDefaultsKey)
        let filtered = ContentRatingGate.filter(items, userDefaults: defaults)
        #expect(filtered.count == 1)
        #expect(filtered.first?.id == "1")
    }
}
