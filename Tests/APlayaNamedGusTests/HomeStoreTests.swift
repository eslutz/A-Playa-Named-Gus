import Foundation
@testable import Gus
import Testing

@Suite("Home store helpers")
struct HomeStoreTests {
    @Test("a delayed Shared with You batch cannot overwrite newer links")
    @MainActor func sharedLinksSupersedeOlderBatch() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var pending: CheckedContinuation<MediaItem, Never>?
        provider.itemHandler = { id in
            if id == "a" {
                return await withCheckedContinuation { pending = $0 }
            }
            return .init(id: id, officialRating: "G", type: .movie)
        }
        defer { pending?.resume(returning: .init(id: "a", officialRating: "G", type: .movie)) }
        let store = try makeHome(provider)
        let older = Task { await store.loadSharedWithYou(links: [.item(id: "a", serverID: "s", provider: .jellyfin)], title: "Older") }
        try await waitUntil { pending != nil }
        await store.loadSharedWithYou(links: [.item(id: "b", serverID: "s", provider: .jellyfin)], title: "Newer")
        #expect(store.sharedWithYouItems.compactMap(\.id) == ["b"])
        pending?.resume(returning: .init(id: "a", officialRating: "G", type: .movie)); pending = nil
        await older.value
        #expect(store.sharedWithYouItems.compactMap(\.id) == ["b"])
        #expect(store.sharedWithYouTitle == "Newer")
    }

    @Test("clearing Shared with You invalidates an in-flight batch")
    @MainActor func clearingSharedLinksSupersedesBatch() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var pending: CheckedContinuation<MediaItem, Never>?
        provider.itemHandler = { id in
            if id == "a" {
                return await withCheckedContinuation { pending = $0 }
            }
            return .init(id: id, officialRating: "G", type: .movie)
        }
        defer { pending?.resume(returning: .init(id: "a", officialRating: "G", type: .movie)) }
        let store = try makeHome(provider)
        await store.loadSharedWithYou(links: [.item(id: "existing", serverID: "s", provider: .jellyfin)], title: "Existing")
        #expect(!store.sharedWithYouItems.isEmpty)
        let older = Task { await store.loadSharedWithYou(links: [.item(id: "a", serverID: "s", provider: .jellyfin)], title: "Loading") }
        try await waitUntil { pending != nil }
        await store.loadSharedWithYou(links: [], title: "Cleared")
        pending?.resume(returning: .init(id: "a", officialRating: "G", type: .movie)); pending = nil
        await older.value
        #expect(store.sharedWithYouItems.isEmpty)
        #expect(store.sharedWithYouTitle == "Cleared")
    }

    @MainActor private func makeHome(_ provider: FakeMediaProviderSession) throws -> HomeStore {
        let url = try #require(URL(string: "https://example.invalid"))
        return HomeStore(session: SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: .init(id: "u", name: "User", serverID: "s"), server: .init(id: "s", name: "Server", url: url), mediaProvider: provider))
    }

    @MainActor private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0 ..< 2000 {
            if predicate() {
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(predicate(), "Timed out awaiting delayed provider request")
    }

    @Test("maps latest episodes to unique series display items with posters")
    func mapsLatestEpisodesToUniqueSeriesDisplayItems() {
        let episodes = [
            MediaItem(
                id: "episode-1",
                imageTags: [:],
                name: "Pilot",
                seriesID: "series-1",
                seriesName: "Psych",
                seriesPrimaryImageTag: "poster-1",
                type: .episode
            ),
            MediaItem(
                id: "episode-2",
                imageTags: [:],
                name: "Spellingg Bee",
                seriesID: "series-1",
                seriesName: "Psych",
                seriesPrimaryImageTag: "poster-1",
                type: .episode
            ),
            MediaItem(
                id: "episode-3",
                imageTags: [:],
                name: "The Kidnapping",
                seriesID: "series-2",
                seriesName: "Monk",
                seriesPrimaryImageTag: "poster-2",
                type: .episode
            ),
        ]

        let displayItems = LatestMediaDisplayMapper.displayItems(from: episodes, libraryCollectionType: .tvshows)

        #expect(displayItems.map(\.id) == ["series-1", "series-2"])
        #expect(displayItems.map(\.name) == ["Psych", "Monk"])
        #expect(displayItems.map(\.type) == [.series, .series])
        #expect(displayItems.first?.imageTags[MediaImageKind.primary.rawValue] == "poster-1")
    }
}

@MainActor
@Suite("Browse snapshot retention")
struct BrowseSnapshotTests {
    private let scope = AccountScope(serverID: "browse-server", userID: "viewer")

    private func session(_ provider: FakeMediaProviderSession, cache: BrowseSnapshotCache) -> SessionStore {
        let url = URL(string: "https://example.invalid")!
        return SessionStore(
            client: JellyfinClientFactory.makeClient(url: url),
            user: .init(id: scope.userID, name: "Viewer", serverID: scope.serverID),
            server: .init(id: scope.serverID, name: "Server", url: url),
            mediaProvider: provider,
            browseCache: cache
        )
    }

    @Test("home restores fresh rails, refreshes each feed on schedule and drops expired offline cards")
    func homeFreshness() async {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var now = Date()
        let cache = BrowseSnapshotCache(scope: scope, root: root, now: { now })
        let provider = FakeMediaProviderSession(capabilities: .init())
        var movies = 0, resume = 0
        var offline = false
        provider.itemsHandler = { query in
            if offline {
                throw GusError.offline
            }
            let movie = query.includeTypes == [.movie]
            if movie {
                movies += 1
            }
            return .init(items: movie ? [.init(id: "movie", name: "Cached movie", officialRating: "G", type: .movie)] : [], totalRecordCount: movie ? 1 : 0)
        }
        provider.resumePageHandler = { _, _ in
            resume += 1
            if offline {
                throw GusError.offline
            }
            return .init(items: [], totalRecordCount: 0)
        }
        let signedIn = session(provider, cache: cache)
        let initial = HomeStore(session: signedIn)
        async let open: Void = initial.loadIfNeeded()
        async let active: Void = initial.loadIfNeeded()
        _ = await(open, active)
        #expect(movies == 1 && resume == 1)
        let reopened = HomeStore(session: signedIn)
        await reopened.loadIfNeeded()
        #expect(movies == 1 && resume == 1)
        #expect(reopened.latestSections.first?.items.first?.id == "movie")
        now.addTimeInterval(61)
        await reopened.loadIfNeeded()
        #expect(movies == 1 && resume == 2)
        await reopened.refreshAfterPlayback(revision: 1)
        await reopened.refreshAfterPlayback(revision: 1)
        #expect(movies == 1 && resume == 3)
        now.addTimeInterval(300)
        offline = true
        await reopened.loadIfNeeded()
        #expect(reopened.latestSections.first?.items.first?.id == "movie")
        #expect(reopened.errorMessage != nil)
        now.addTimeInterval(BrowseSnapshotCache.lifetime)
        await reopened.loadIfNeeded()
        #expect(reopened.latestSections.isEmpty)
        #expect(!reopened.isPending(.movies))
    }

    @Test("only missing shelves enter loading, and a confirmed empty reply removes its placeholder")
    func partialCache() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = BrowseSnapshotCache(scope: scope, root: root)
        cache.write([MediaItem(id: "movie", officialRating: "G", type: .movie)], key: "latest:movies")
        let provider = FakeMediaProviderSession(capabilities: .init())
        var delayed: CheckedContinuation<MediaItemPage, Never>?
        provider.itemsHandler = { query in
            if query.includeTypes == [.book] {
                return await withCheckedContinuation { delayed = $0 }
            }
            return .init(items: [], totalRecordCount: 0)
        }
        let store = HomeStore(session: session(provider, cache: cache))
        store.restoreSnapshots()
        #expect(!store.isPending(.movies) && store.isPending(.books))
        let refresh = Task { await store.loadIfNeeded() }
        defer { delayed?.resume(returning: .init(items: [], totalRecordCount: 0)) }
        for _ in 0 ..< 1000 where delayed == nil {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(delayed != nil)
        #expect(store.latestSections.first?.items.first?.id == "movie")
        #expect(store.isPending(.books))
        delayed?.resume(returning: .init(items: [], totalRecordCount: 0))
        delayed = nil
        await refresh.value
        #expect(!store.isPending(.books) && store.latestSections.map(\.kind) == [.movies])
    }

    @Test("grid previews retain raw paging, deep refresh and permission invalidation")
    func gridPages() async {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var now = Date()
        let cache = BrowseSnapshotCache(scope: scope, root: root, now: { now })
        let provider = FakeMediaProviderSession(capabilities: .init())
        var offsets: [Int] = []
        provider.itemsHandler = { query in
            offsets.append(query.startIndex)
            let items: [MediaItem] = (query.startIndex ..< min(query.startIndex + query.limit, 95)).map { .init(id: String($0), officialRating: "G", type: .movie) }
            return .init(items: items, totalRecordCount: 95)
        }
        let signedIn = session(provider, cache: cache)
        let grid = LibraryStore(scope: .category(.movies), session: signedIn)
        await grid.loadIfNeeded()
        await grid.continueSearching()
        #expect(grid.items.count == 95)
        now.addTimeInterval(301)
        await grid.loadIfNeeded()
        #expect(grid.items.count == 95)
        #expect(offsets == [0, 60, 0, 60])
        let reopened = LibraryStore(scope: .category(.movies), session: signedIn)
        await reopened.loadIfNeeded()
        #expect(reopened.items.count == 60 && reopened.canLoadMore)
        await reopened.continueSearching()
        #expect(offsets == [0, 60, 0, 60, 60])
        #expect(reopened.items.count == 95)
        provider.itemsHandler = { _ in throw GusError.forbidden }
        await reopened.load()
        #expect(reopened.items.isEmpty)
        #expect(reopened.state == .failed(GusError.forbidden.localizedDescription))
        let third = LibraryStore(scope: .category(.movies), session: signedIn)
        await third.loadIfNeeded()
        #expect(third.items.isEmpty)
    }

    @Test("cache bounds grid entries, isolates accounts and omits transport metadata")
    func retention() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = BrowseSnapshotCache(scope: scope, root: root)
        let other = BrowseSnapshotCache(scope: .init(serverID: scope.serverID, userID: "other"), root: root)
        for index in 0 ..< 8 {
            cache.write([index], key: "grid:\(index)")
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: cache.directory.path)
        #expect(files.count == 6)
        let media = MediaItem(id: "movie", name: "Movie", overview: "PRIVATE SYNOPSIS", type: .movie)
        cache.write([media.browseSnapshotItem], key: "shelf")
        let saved = try #require(cache.read("shelf", as: [MediaItem].self))
        #expect(saved.value.first?.overview == nil && saved.value.first?.id == "movie")
        #expect(other.read("shelf", as: [MediaItem].self) == nil)
        cache.purge()
        #expect(cache.read("shelf", as: [MediaItem].self) == nil)
    }
}
