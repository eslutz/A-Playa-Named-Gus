import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("Navigation preferences")
struct NavigationPreferencesTests {
    private static func makeStore() -> NavigationPreferencesStore {
        NavigationPreferencesStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("gus-nav-tests-\(UUID().uuidString)", isDirectory: true)
        )
    }

    private static let libraries = [
        MediaItem(collectionType: .movies, id: "lib-movies", name: "Movies"),
        MediaItem(collectionType: .movies, id: "lib-family-movies", name: "Family Movies"),
        MediaItem(collectionType: .tvshows, id: "lib-shows", name: "Shows"),
        MediaItem(collectionType: .music, id: "lib-music", name: "Music"),
    ]

    @Test("defaults to the Libraries grid first, then consolidated categories in order")
    func defaultsToLibrariesThenServerOrder() {
        let store = Self.makeStore()
        let sections = store.resolvedSections(libraries: Self.libraries, serverID: "s", userID: "u")

        #expect(sections.map(\.id) == ["libraries", "category.movies", "category.tvshows", "category.music"])
        let allVisible = sections.allSatisfy(\.isVisible)
        #expect(allVisible)
        #expect(sections[1].title == "Movies")
        #expect(sections[1].systemImage == "film")
        #expect(!sections.map(\.title).contains("Family Movies"))
    }

    @Test("hiding and reordering persist and round-trip through resolution")
    func hideAndReorder() {
        let store = Self.makeStore()
        store.setVisibility(false, forSectionID: "category.tvshows", libraries: Self.libraries, serverID: "s", userID: "u")
        store.move(sectionID: "category.music", by: -2, libraries: Self.libraries, serverID: "s", userID: "u")

        let sections = store.resolvedSections(libraries: Self.libraries, serverID: "s", userID: "u")
        #expect(sections.map(\.id) == ["libraries", "category.music", "category.movies", "category.tvshows"])
        #expect(
            store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").map(\.id)
                == ["libraries", "category.music", "category.movies"]
        )
    }

    @Test("unknown stored sections drop and new categories append visible")
    func gracefulServerChanges() {
        let store = Self.makeStore()
        // Establish an order including a category that will disappear.
        store.move(sectionID: "category.music", by: -1, libraries: Self.libraries, serverID: "s", userID: "u")

        let changed = [
            MediaItem(collectionType: .movies, id: "lib-movies", name: "Movies"),
            MediaItem(collectionType: .books, id: "lib-books", name: "Books"),
        ]
        let sections = store.resolvedSections(libraries: changed, serverID: "s", userID: "u")

        #expect(!sections.contains { $0.id == "category.tvshows" })
        #expect(!sections.contains { $0.id == "category.music" })
        #expect(sections.last?.id == "category.books")
        #expect(sections.last?.isVisible == true)
    }

    @Test("moves clamp at the boundaries")
    func movesClampAtBoundaries() {
        let store = Self.makeStore()
        store.move(sectionID: "libraries", by: -1, libraries: Self.libraries, serverID: "s", userID: "u")

        let sections = store.resolvedSections(libraries: Self.libraries, serverID: "s", userID: "u")
        #expect(sections.first?.id == "libraries")
    }

    @Test("preferences are scoped per account")
    func scopedPerAccount() {
        let store = Self.makeStore()
        store.setVisibility(false, forSectionID: "category.movies", libraries: Self.libraries, serverID: "s1", userID: "u1")

        let other = store.resolvedSections(libraries: Self.libraries, serverID: "s2", userID: "u2")
        #expect(other.first { $0.id == "category.movies" }?.isVisible == true)
    }
}
