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

    @Test("defaults to Home, required sections, content categories, and hidden empty categories")
    func defaultsToRequiredSectionsAndHiddenEmptyCategories() {
        let store = Self.makeStore()
        let sections = store.resolvedSections(libraries: Self.libraries, serverID: "s", userID: "u")

        #expect(sections.map(\.id) == [
            "home",
            "libraries",
            "category.movies",
            "category.tvshows",
            "category.music",
            "settings",
            "category.books",
            "category.photos",
            "category.livetv",
        ])
        #expect(store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").map(\.id) == [
            "home",
            "libraries",
            "category.movies",
            "category.tvshows",
            "category.music",
            "settings",
        ])
        #expect(store.hiddenSections(libraries: Self.libraries, serverID: "s", userID: "u").map(\.id) == [
            "category.books",
            "category.photos",
            "category.livetv",
        ])
        #expect(sections[2].title == "Movies")
        #expect(sections[2].systemImage == "film")
        #expect(!sections.map(\.title).contains("Family Movies"))
    }

    @Test("Home cannot move or hide, while Settings and Libraries can move but not hide")
    func requiredSectionCapabilities() {
        let store = Self.makeStore()
        let sections = store.resolvedSections(libraries: Self.libraries, serverID: "s", userID: "u")

        let home = sections.first { $0.id == "home" }
        let libraries = sections.first { $0.id == "libraries" }
        let settings = sections.first { $0.id == "settings" }
        let movies = sections.first { $0.id == "category.movies" }

        #expect(home?.canMove == false)
        #expect(home?.canHide == false)
        #expect(libraries?.canMove == true)
        #expect(libraries?.canHide == false)
        #expect(settings?.canMove == true)
        #expect(settings?.canHide == false)
        #expect(movies?.canMove == true)
        #expect(movies?.canHide == true)

        store.setVisibility(false, forSectionID: "home", libraries: Self.libraries, serverID: "s", userID: "u")
        store.setVisibility(false, forSectionID: "libraries", libraries: Self.libraries, serverID: "s", userID: "u")
        store.setVisibility(false, forSectionID: "settings", libraries: Self.libraries, serverID: "s", userID: "u")

        #expect(store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").map(\.id).contains("home"))
        #expect(store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").map(\.id).contains("libraries"))
        #expect(store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").map(\.id).contains("settings"))
    }

    @Test("hiding moves categories to Hidden and showing empty categories returns them to Sections")
    func hidingAndShowingCategories() {
        let store = Self.makeStore()
        store.setVisibility(false, forSectionID: "category.tvshows", libraries: Self.libraries, serverID: "s", userID: "u")
        store.setVisibility(true, forSectionID: "category.books", libraries: Self.libraries, serverID: "s", userID: "u")

        #expect(
            store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").map(\.id)
                == ["home", "libraries", "category.movies", "category.music", "settings", "category.books"]
        )
        #expect(
            store.hiddenSections(libraries: Self.libraries, serverID: "s", userID: "u").map(\.id)
                == ["category.tvshows", "category.photos", "category.livetv"]
        )
        #expect(
            store.resolvedSections(libraries: Self.libraries, serverID: "s", userID: "u")
                .first { $0.id == "category.books" }?.libraries.isEmpty == true
        )
    }

    @Test("hiding and reordering persist and round-trip through resolution")
    func hideAndReorder() {
        let store = Self.makeStore()
        store.setVisibility(false, forSectionID: "category.tvshows", libraries: Self.libraries, serverID: "s", userID: "u")
        store.move(sectionID: "category.music", by: -2, libraries: Self.libraries, serverID: "s", userID: "u")
        store.move(sectionID: "settings", by: -1, libraries: Self.libraries, serverID: "s", userID: "u")

        let sections = store.resolvedSections(libraries: Self.libraries, serverID: "s", userID: "u")
        #expect(sections.map(\.id) == [
            "home",
            "category.music",
            "libraries",
            "settings",
            "category.movies",
            "category.tvshows",
            "category.books",
            "category.photos",
            "category.livetv",
        ])
        #expect(
            store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").map(\.id)
                == ["home", "category.music", "libraries", "settings", "category.movies"]
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

        #expect(sections.first { $0.id == "category.tvshows" }?.isVisible == false)
        #expect(sections.first { $0.id == "category.music" }?.isVisible == false)
        #expect(sections.first { $0.id == "category.books" }?.isVisible == true)
    }

    @Test("moves clamp at the boundaries")
    func movesClampAtBoundaries() {
        let store = Self.makeStore()
        store.move(sectionID: "home", by: 1, libraries: Self.libraries, serverID: "s", userID: "u")
        store.move(sectionID: "libraries", by: -1, libraries: Self.libraries, serverID: "s", userID: "u")

        let sections = store.resolvedSections(libraries: Self.libraries, serverID: "s", userID: "u")
        #expect(sections.first?.id == "home")
        #expect(sections.dropFirst().first?.id == "libraries")
    }

    @Test("preferences are scoped per account")
    func scopedPerAccount() {
        let store = Self.makeStore()
        store.setVisibility(false, forSectionID: "category.movies", libraries: Self.libraries, serverID: "s1", userID: "u1")

        let other = store.resolvedSections(libraries: Self.libraries, serverID: "s2", userID: "u2")
        #expect(other.first { $0.id == "category.movies" }?.isVisible == true)
    }
}
