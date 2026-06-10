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
        MediaItem(collectionType: .tvshows, id: "lib-shows", name: "Shows"),
        MediaItem(collectionType: .music, id: "lib-music", name: "Music"),
    ]

    @Test("defaults to the Libraries grid first, then server libraries in order")
    func defaultsToLibrariesThenServerOrder() {
        let store = Self.makeStore()
        let sections = store.resolvedSections(libraries: Self.libraries, serverID: "s", userID: "u")

        #expect(sections.map(\.id) == ["libraries", "lib-movies", "lib-shows", "lib-music"])
        let allVisible = sections.allSatisfy(\.isVisible)
        #expect(allVisible)
        #expect(sections[1].title == "Movies")
        #expect(sections[1].systemImage == "film")
    }

    @Test("hiding and reordering persist and round-trip through resolution")
    func hideAndReorder() {
        let store = Self.makeStore()
        store.setVisibility(false, forSectionID: "lib-shows", libraries: Self.libraries, serverID: "s", userID: "u")
        store.move(sectionID: "lib-music", by: -2, libraries: Self.libraries, serverID: "s", userID: "u")

        let sections = store.resolvedSections(libraries: Self.libraries, serverID: "s", userID: "u")
        #expect(sections.map(\.id) == ["libraries", "lib-music", "lib-movies", "lib-shows"])
        #expect(
            store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").map(\.id)
                == ["libraries", "lib-music", "lib-movies"]
        )
    }

    @Test("unknown stored sections drop and new libraries append visible")
    func gracefulServerChanges() {
        let store = Self.makeStore()
        // Establish an order including a library that will disappear.
        store.move(sectionID: "lib-music", by: -1, libraries: Self.libraries, serverID: "s", userID: "u")

        let changed = [
            MediaItem(collectionType: .movies, id: "lib-movies", name: "Movies"),
            MediaItem(collectionType: .music, id: "lib-music", name: "Music"),
            MediaItem(collectionType: .books, id: "lib-books", name: "Books"),
        ]
        let sections = store.resolvedSections(libraries: changed, serverID: "s", userID: "u")

        #expect(!sections.contains { $0.id == "lib-shows" })
        #expect(sections.last?.id == "lib-books")
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
        store.setVisibility(false, forSectionID: "lib-movies", libraries: Self.libraries, serverID: "s1", userID: "u1")

        let other = store.resolvedSections(libraries: Self.libraries, serverID: "s2", userID: "u2")
        #expect(other.first { $0.id == "lib-movies" }?.isVisible == true)
    }
}
