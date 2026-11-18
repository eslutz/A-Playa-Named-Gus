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

        #expect(sections.filter { $0.id != "downloaded" && $0.id != "playlists" }.map(\.id) == [
            "home",
            "libraries",
            "category.movies",
            "category.tvshows",
            "category.music",
            "discover",
            "settings",
            "category.books",
            "category.audiobooks",
            "category.photos",
            "category.livetv",
        ])
        #expect(store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").filter { $0.id != "downloaded" && $0.id != "playlists" }.map(\.id) == [
            "home",
            "libraries",
            "category.movies",
            "category.tvshows",
            "category.music",
            "discover",
            "settings",
        ])
        #expect(store.hiddenSections(libraries: Self.libraries, serverID: "s", userID: "u").filter { $0.id != "downloaded" && $0.id != "playlists" }.map(\.id) == [
            "category.books",
            "category.audiobooks",
            "category.photos",
            "category.livetv",
        ])
        #expect(sections.first { $0.id == "category.movies" }?.title == "Movies")
        #expect(sections.first { $0.id == "category.movies" }?.systemImage == "film")
        #expect(!sections.map(\.title).contains("Family Movies"))
    }

    @Test("book format discovery is scoped, paged by type, and retains its last result on failure")
    func bookFormatDiscovery() async throws {
        let store = Self.makeStore()
        let libraries = [MediaItem(collectionType: .books, id: "mixed", name: "Library")]
        let provider = FakeMediaProviderSession(capabilities: .init())
        let url = try #require(URL(string: "https://jellyfin.example.invalid"))
        let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: .init(id: "u", name: "Test", serverID: "s"), server: .init(id: "s", name: "Server", url: url), mediaProvider: provider)
        for types in [[MediaItemType.book, .audioBook], [.book], [.audioBook], []] {
            provider.itemsHandler = { query in
                let type = try #require(query.includeTypes?.first)
                #expect(query.includeTypes?.count == 1)
                #expect(query.limit == 1)
                let results = types.contains(type) ? [MediaItem(id: "one", type: type)] : []
                return MediaItemPage(items: results, totalRecordCount: results.count)
            }
            await store.refreshBookFormats(session: session)
            let detected = store.visibleSections(libraries: libraries, serverID: "s", userID: "u")
                .compactMap(\.category).filter { $0 == .books || $0 == .audiobooks }
            #expect(detected == types.map { $0 == .book ? .books : .audiobooks })
        }
        provider.itemsHandler = { _ in throw GusError.offline }
        await store.refreshBookFormats(session: session)
        #expect(!store.visibleSections(libraries: libraries, serverID: "s", userID: "u").contains { $0.category == .books })
        #expect(store.visibleSections(libraries: libraries, serverID: "s", userID: "other").contains { $0.category == .books })
        #expect(LibraryRequest.parameters(scope: .category(.books), startIndex: 60, limit: 60).includeTypes == [.book])
        #expect(LibraryRequest.parameters(scope: .category(.audiobooks), startIndex: 60, limit: 60).includeTypes == [.audioBook])
    }

    @Test("the previous Books preference migrates to Audiobooks once")
    func migrateBookVisibility() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gus-book-nav-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let saved = [NavigationSectionPreference(id: NavigationCategory.books.id, isVisible: false)]
        try JSONEncoder().encode(saved).write(to: directory.appendingPathComponent(scope.storageKey + ".json"))
        let store = NavigationPreferencesStore(directory: directory)
        store.load(serverID: "s", userID: "u")
        #expect(store.hiddenSections(libraries: [], serverID: "s", userID: "u").contains { $0.category == .audiobooks })
        store.setVisibility(true, forSectionID: NavigationCategory.audiobooks.id, libraries: [], serverID: "s", userID: "u")
        let reopened = NavigationPreferencesStore(directory: directory)
        reopened.load(serverID: "s", userID: "u")
        #expect(reopened.visibleSections(libraries: [], serverID: "s", userID: "u").contains { $0.category == .audiobooks })
        #expect(reopened.hiddenSections(libraries: [], serverID: "s", userID: "u").contains { $0.category == .books })
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
            store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").filter { $0.id != "downloaded" && $0.id != "playlists" }.map(\.id)
                == ["home", "libraries", "category.movies", "category.music", "discover", "settings", "category.books"]
        )
        #expect(
            store.hiddenSections(libraries: Self.libraries, serverID: "s", userID: "u").filter { $0.id != "downloaded" && $0.id != "playlists" }.map(\.id)
                == ["category.tvshows", "category.audiobooks", "category.photos", "category.livetv"]
        )
        #expect(
            store.resolvedSections(libraries: Self.libraries, serverID: "s", userID: "u")
                .first { $0.id == "category.books" }?.libraries.isEmpty == true
        )
    }

    @Test("hiding and reordering persist and round-trip through resolution")
    func hideAndReorder() throws {
        let store = Self.makeStore()
        store.setVisibility(false, forSectionID: "category.tvshows", libraries: Self.libraries, serverID: "s", userID: "u")
        // Required sections vary by platform and now include Playlists. Move
        // Music before Libraries without assuming their numeric positions.
        let movable = store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").filter(\.canMove)
        let musicIndex = try #require(movable.firstIndex { $0.id == "category.music" })
        let librariesIndex = try #require(movable.firstIndex { $0.id == "libraries" })
        store.move(sectionID: "category.music", by: librariesIndex - musicIndex, libraries: Self.libraries, serverID: "s", userID: "u")
        let updated = store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").filter(\.canMove)
        let settingsIndex = try #require(updated.firstIndex { $0.id == "settings" })
        let moviesIndex = try #require(updated.firstIndex { $0.id == "category.movies" })
        store.move(sectionID: "settings", by: moviesIndex - settingsIndex, libraries: Self.libraries, serverID: "s", userID: "u")

        let sections = store.resolvedSections(libraries: Self.libraries, serverID: "s", userID: "u")
        #expect(sections.filter { $0.id != "downloaded" && $0.id != "playlists" }.map(\.id) == [
            "home",
            "category.music",
            "libraries",
            "settings",
            "category.movies",
            "discover",
            "category.tvshows",
            "category.books",
            "category.audiobooks",
            "category.photos",
            "category.livetv",
        ])
        #expect(
            store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").filter { $0.id != "downloaded" && $0.id != "playlists" }.map(\.id)
                == ["home", "category.music", "libraries", "settings", "category.movies", "discover"]
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

    @Test("Discover can be hidden and restored independently for each account")
    func discoverVisibility() {
        let store = Self.makeStore()
        let before = store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").map(\.id)
        #expect(before.contains("discover"))
        store.setVisibility(false, forSectionID: "discover", libraries: Self.libraries, serverID: "s", userID: "u")
        let after = store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").map(\.id)
        #expect(Array(before.prefix(4)) == Array(after.prefix(4)))
        #expect(!after.contains("discover"))
        #expect(store.visibleSections(libraries: Self.libraries, serverID: "other", userID: "u").contains { $0.id == "discover" })
        store.setVisibility(true, forSectionID: "discover", libraries: Self.libraries, serverID: "s", userID: "u")
        let restored = store.visibleSections(libraries: Self.libraries, serverID: "s", userID: "u").map(\.id)
        #expect(Set(restored) == Set(before))
        #expect(Array(restored.prefix(4)) == Array(before.prefix(4)))
    }

    @Test("preferences are scoped per account")
    func scopedPerAccount() {
        let store = Self.makeStore()
        store.setVisibility(false, forSectionID: "category.movies", libraries: Self.libraries, serverID: "s1", userID: "u1")

        let other = store.resolvedSections(libraries: Self.libraries, serverID: "s2", userID: "u2")
        #expect(other.first { $0.id == "category.movies" }?.isVisible == true)
    }
}
