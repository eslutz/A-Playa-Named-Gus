import AVFoundation
import Foundation
@testable import Gus
import JellyfinAPI
import SwiftUI
import Testing

@MainActor @Suite("UI remediation regressions", .serialized)
struct UIRemediationTests {
    @Test("cancelled detail load resets and can be entered again")
    func cancelledDetailCanReload() async {
        let p = provider()
        var calls = 0
        p.itemHandler = { _ in
            calls += 1
            if calls == 1 {
                throw CancellationError()
            }
            return MediaItem(id: "item", name: "Loaded")
        }
        let store = ItemDetailStore(item: MediaItem(id: "item"), session: session(p))
        await store.load()
        #expect(store.state == .idle)
        await store.load()
        #expect(calls == 2)
        #expect(store.state == .loaded && store.item.name == "Loaded")
    }

    @Test("cancelled successful detail response cannot publish")
    func cancelledDetailSuccessDoesNotPublish() async {
        let p = provider()
        let pending = PendingPage()
        p.itemHandler = { _ in
            _ = try await pending.value()
            return MediaItem(id: "item", name: "Late")
        }
        let store = ItemDetailStore(item: MediaItem(id: "item", name: "Original"), session: session(p))
        let task = Task { await store.load() }
        await waitFor { pending.isWaiting }
        task.cancel()
        pending.succeed([])
        await task.value
        #expect(store.state == .idle)
        #expect(store.item.name == "Original")
    }

    private func session(_ provider: FakeMediaProviderSession) -> SessionStore {
        SessionStore(
            client: JellyfinClient(configuration: .init(
                url: URL(string: "https://example.invalid")!,
                accessToken: "test",
                client: "Tests",
                deviceName: "Tests",
                deviceID: "tests",
                version: "1.0.0"
            )),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: URL(string: "https://example.invalid")!),
            mediaProvider: provider
        )
    }

    private func provider() -> FakeMediaProviderSession {
        FakeMediaProviderSession(capabilities: ProviderCapabilities())
    }

    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0 ..< 1000 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(condition())
    }

    @Test("late search pagination cannot append to a replacement query")
    func staleSearchPage() async {
        let p = provider()
        let delayed = PendingPage()
        p.itemsHandler = { query in
            if query.searchTerm == "A", query.startIndex > 0 {
                return try await delayed.value()
            }
            return MediaItemPage(items: [MediaItem(id: query.searchTerm, name: query.searchTerm)], totalRecordCount: query.searchTerm == "A" ? 2 : 1)
        }
        let store = SearchStore(session: session(p), limit: 1, admits: { _ in true })
        await store.search("A")
        let pagination = Task { await store.loadMoreIfNeeded(currentItem: store.results[0]) }
        await waitFor { delayed.isWaiting }
        await store.search("B")
        delayed.succeed([MediaItem(id: "late-A")])
        await pagination.value
        #expect(store.results.map(\.id) == ["B"])
        #expect(store.query == "B")
        #expect(!store.isLoadingNextPage)
    }

    @Test("stale search failure cannot fail a replacement query")
    func staleSearchFailure() async {
        let p = provider(), delayed = PendingPage()
        p.itemsHandler = { query in
            if query.searchTerm == "A" {
                return try await delayed.value()
            }
            return MediaItemPage(items: [MediaItem(id: "B")], totalRecordCount: 1)
        }
        let store = SearchStore(session: session(p), admits: { _ in true })
        let a = Task { await store.search("A") }
        await waitFor { delayed.isWaiting }
        await store.search("B")
        delayed.fail()
        await a.value
        #expect(store.state == .loaded)
        #expect(store.results.first?.id == "B")
    }

    @Test("filtered search pages use raw offsets and stop after three pages")
    func filteredSearch() async {
        let p = provider()
        var offsets: [Int] = []
        p.itemsHandler = { query in
            offsets.append(query.startIndex)
            return MediaItemPage(items: [MediaItem(id: String(query.startIndex))], totalRecordCount: 5)
        }
        let store = SearchStore(session: session(p), limit: 1, admits: { $0.id == "4" })
        await store.search("test")
        #expect(offsets == [0, 1, 2])
        #expect(store.results.isEmpty && store.canLoadMore && store.state == .loaded)
        await store.continueSearching()
        #expect(offsets == [0, 1, 2, 3, 4])
        #expect(store.results.first?.id == "4")
        #expect(!store.canLoadMore)
    }

    @Test("filtered library scans later pages without a visible cell")
    func filteredLibrary() async {
        let p = provider()
        var offsets: [Int] = []
        p.itemsHandler = { query in
            offsets.append(query.startIndex)
            return MediaItemPage(items: [MediaItem(id: String(query.startIndex))], totalRecordCount: 4)
        }
        let store = LibraryStore(scope: .category(.movies), session: session(p), admits: { $0.id == "3" })
        await store.load()
        #expect(offsets == [0, 1, 2])
        #expect(store.items.isEmpty && store.canLoadMore)
        await store.continueSearching()
        #expect(store.items.first?.id == "3")
        #expect(!store.canLoadMore)
    }

    @Test("empty server pages terminate even with an inconsistent total")
    func emptyPagesTerminate() async {
        let p = provider()
        var calls = 0
        p.itemsHandler = { _ in calls += 1; return MediaItemPage(items: [], totalRecordCount: 100) }
        let store = SearchStore(session: session(p), admits: { _ in true })
        await store.search("empty")
        #expect(calls == 1 && !store.canLoadMore)
    }

    @Test("reversed season responses cannot overwrite selected episodes")
    func staleSeasons() async {
        let p = provider(), delayed = PendingPage()
        p.episodesHandler = { id in
            if id == "A" {
                return try await delayed.value()
            }
            return MediaItemPage(items: [MediaItem(id: "B-episode")], totalRecordCount: 1)
        }
        let store = SeriesDetailStore(series: MediaItem(id: "show"), session: session(p))
        let a = Task { await store.selectSeason(id: "A") }
        await waitFor { delayed.isWaiting }
        await store.selectSeason(id: "B")
        delayed.succeed([MediaItem(id: "A-episode")])
        await a.value
        #expect(store.selectedSeasonID == "B")
        #expect(store.episodes.map(\.id) == ["B-episode"])
    }

    @Test("selected season can retry after failure")
    func retrySeason() async {
        let p = provider()
        var calls = 0
        p.episodesHandler = { _ in
            calls += 1
            if calls == 1 {
                throw URLError(.badServerResponse)
            }
            return MediaItemPage(items: [MediaItem(id: "episode")], totalRecordCount: 1)
        }
        let store = SeriesDetailStore(series: MediaItem(id: "show"), session: session(p))
        await store.selectSeason(id: "A")
        await store.retryEpisodes()
        #expect(calls == 2 && store.episodesState == .loaded)
        #expect(store.episodes.first?.id == "episode")
    }

    @Test("late season failure does not fail the current season")
    func staleSeasonFailure() async {
        let p = provider(), delayed = PendingPage()
        p.episodesHandler = { id in
            if id == "A" {
                return try await delayed.value()
            }
            return MediaItemPage(items: [MediaItem(id: "B")], totalRecordCount: 1)
        }
        let store = SeriesDetailStore(series: MediaItem(id: "show"), session: session(p))
        let a = Task { await store.selectSeason(id: "A") }
        await waitFor { delayed.isWaiting }
        await store.selectSeason(id: "B")
        delayed.fail()
        await a.value
        #expect(store.episodesState == .loaded && store.selectedSeasonID == "B")
    }

    @Test("successful mutation with failed refresh cannot toggle twice")
    func reconcileMutation() async {
        let p = provider()
        var mutations = 0, refreshes = 0
        p.watchedHandler = { mutations += 1 }
        p.itemHandler = { id in
            refreshes += 1
            if refreshes == 1 {
                throw URLError(.badServerResponse)
            }
            return MediaItem(id: id)
        }
        let store = ItemDetailStore(item: MediaItem(id: "item"), session: session(p))
        await store.toggleWatched()
        #expect(store.needsUserDataRefresh && store.actionError != nil)
        await store.toggleWatched()
        #expect(mutations == 1 && refreshes == 2)
        #expect(!store.needsUserDataRefresh && store.actionError == nil)
    }

    @Test("concurrent detail mutations serialize and failures remain visible")
    func serializedMutations() async {
        let p = provider(), delayed = PendingPage()
        var favorites = 0
        p.watchedHandler = { _ = try await delayed.value() }
        p.favoriteHandler = { favorites += 1 }
        let store = ItemDetailStore(item: MediaItem(id: "item"), session: session(p))
        let watched = Task { await store.toggleWatched() }
        await waitFor { delayed.isWaiting }
        await store.toggleFavorite()
        delayed.fail()
        await watched.value
        #expect(favorites == 0 && store.actionError != nil)
        #expect(!store.isUpdatingUserData && !store.needsUserDataRefresh)
    }

    @Test("opened photo survives an unrelated first page and is deduplicated")
    func selectedPhoto() {
        let opened = MediaItem(id: "501", name: "Opened", type: .photo)
        let first = MediaItem(id: "1", name: "First", type: .photo)
        #expect(PhotoSelection.includingOpened(opened, in: [first, opened, first]).map(\.id) == ["501", "1"])
    }

    @Test("section navigation, stores, and search survive layout ownership changes")
    func sharedNavigation() {
        let activeSession = session(provider())
        let state = RootNavigationState()
        state.selectedSectionID = "category.movies"
        state.paths["category.movies", default: NavigationPath()].append(AppScreen.downloads)
        let search = state.searchState(for: "category.movies", session: activeSession)
        search.text = "Psych"
        let same = state.searchState(for: "category.movies", session: activeSession)
        #expect(same === search && same.text == "Psych")
        #expect(state.paths["category.movies"]?.count == 1)
        #expect(state.libraryStore(for: .category(.movies), session: activeSession) === state.libraryStore(for: .category(.movies), session: activeSession))
        #expect(RootNavigationState.directSectionIDs(["a", "b", "c", "d", "e", "f"]) == ["a", "b", "c", "d"])
        #expect(RootNavigationState.directSectionIDs(["a", "b", "c", "d", "e"]).count == 5)
        let otherAccount = RootNavigationState()
        #expect(otherAccount.paths.isEmpty && otherAccount !== state)
    }

    @Test("audio closing and reopening preserve the same queue and local-only intent")
    func audioCloseReopen() async {
        let p = provider()
        let audio = AudioPlaybackCoordinator()
        // localOnly ensures the fake resolver is never used even without a local file.
        audio.play(tracks: [MediaItem(id: "audio", type: .audio)], localOnly: true, session: session(p), downloads: .shared)
        let original = audio.store
        await waitFor {
            if case .failed = original?.state {
                return true
            }; return false
        }
        audio.close()
        audio.reopen()
        #expect(audio.store === original && audio.isPresented)
        #expect(audio.store?.currentTrack?.id == "audio" && p.audioResolutionCallCount == 0)
        audio.stop()
        #expect(audio.store == nil && !audio.isPresented)
    }

    @Test("cancelled video preparation cannot install a late player")
    func cancelledVideo() async {
        let p = provider(), delayed = PendingResolution()
        p.playbackHandler = { try await delayed.value() }
        let store = PlaybackStore(item: MediaItem(id: "video", type: .movie), session: session(p), playbackRefresh: PlaybackRefreshStore())
        let task = Task { await store.prepare() }
        await waitFor { delayed.isWaiting }
        task.cancel()
        store.teardown()
        delayed.succeed()
        await task.value
        #expect(store.player == nil && store.state != .ready)
    }

    @Test("video teardown rejects late preparation without canceling its caller")
    func tornDownVideoPreparation() async {
        let p = provider(), delayed = PendingResolution()
        p.playbackHandler = { try await delayed.value() }
        let store = PlaybackStore(item: MediaItem(id: "video", type: .movie), session: session(p), playbackRefresh: PlaybackRefreshStore())
        let task = Task { await store.prepare() }
        await waitFor { delayed.isWaiting }
        store.teardown()
        delayed.succeed()
        await task.value
        #expect(!task.isCancelled)
        #expect(store.player == nil && store.state == .idle)
    }

    @Test("video teardown cancels an already queued automatic next episode")
    func tornDownQueuedAutoplay() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let downloads = OfflineDownloadStore(fileStore: files, coordinator: RemediationDownloadCoordinator())
        let first = MediaItem(id: "first", indexNumber: 1, parentIndexNumber: 1, seriesID: "show", type: .episode)
        let second = MediaItem(id: "second", indexNumber: 2, parentIndexNumber: 1, seriesID: "show", type: .episode)
        for item in [first, second] {
            let source = directory.appendingPathComponent(UUID().uuidString)
            try Data("playback lifecycle fixture".utf8).write(to: source)
            try files.persistDownloadedFile(source, item: item, serverID: "s", userID: "u", fileExtension: "mp4")
        }
        downloads.load(serverID: "s", userID: "u")
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: PlaybackPreferences.autoPlayNextEpisodeKey)
        defaults.set(true, forKey: PlaybackPreferences.autoPlayNextEpisodeKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: PlaybackPreferences.autoPlayNextEpisodeKey)
            } else {
                defaults.removeObject(forKey: PlaybackPreferences.autoPlayNextEpisodeKey)
            }
        }
        let store = PlaybackStore(item: first, session: session(provider()), playbackRefresh: PlaybackRefreshStore(), downloads: downloads)
        await store.prepare()
        let endedItem = try #require(store.player?.currentItem)
        #expect(store.nextUpItem?.id == second.id)
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: endedItem)
        #expect(!store.didFinishPlayback)
        store.teardown()
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(store.state == .idle && store.player == nil)
        #expect(store.item.id == first.id && store.nextUpItem == nil)
    }

    @Test("closing audio during preparation prevents a late playback start")
    func cancelledAudio() async {
        let p = provider(), delayed = PendingResolution()
        p.audioHandler = { try await delayed.value() }
        let audio = AudioPlaybackCoordinator()
        audio.play(tracks: [MediaItem(id: "audio", type: .audio)], session: session(p), downloads: .shared)
        await waitFor { delayed.isWaiting }
        let original = audio.store
        audio.close()
        delayed.succeed()
        await waitFor { original?.state == .idle }
        #expect(audio.store == nil && !audio.isPresented && original?.isPlaying == false)
    }

    @Test("an explicit repeated Home route still issues a navigation request")
    func repeatedFixedRoute() {
        let navigation = AppNavigationModel()
        navigation.open(.home)
        let first = navigation.routeRequest
        navigation.open(.home)
        #expect(navigation.route == .home && navigation.routeRequest == first + 1)
    }

    @Test("a re-mounted search surface does not restart its pending query")
    func searchRemount() async {
        let p = provider(), delayed = PendingPage()
        var calls = 0
        p.itemsHandler = { _ in calls += 1; return try await delayed.value() }
        let store = SearchStore(session: session(p), admits: { _ in true })
        let search = SectionSearchState(store: store)
        search.text = "Psych"
        search.updateQuery()
        await waitFor { delayed.isWaiting }
        search.updateQuery()
        delayed.succeed([MediaItem(id: "result")])
        await waitFor { store.state == .loaded }
        #expect(calls == 1 && store.results.first?.id == "result")
    }
}

private final class RemediationDownloadCoordinator: DownloadSessionCoordinating {
    func setEventHandler(_ eventHandler: DownloadSessionCoordinatorEventHandler?) {}
    func startDownload(from url: URL, recordID: String) {}
    func resumeDownload(with resumeData: Data, recordID: String) {}
    func pause(recordID: String, completion: @escaping (Data?) -> Void) {
        completion(nil)
    }

    func cancel(recordID: String) {}
    func reconnectActiveTasks() {}
}

@MainActor private final class PendingPage {
    private var continuation: CheckedContinuation<MediaItemPage, Error>?
    var isWaiting: Bool {
        continuation != nil
    }

    func value() async throws -> MediaItemPage {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func succeed(_ items: [MediaItem]) {
        continuation?.resume(returning: MediaItemPage(items: items, totalRecordCount: items.count)); continuation = nil
    }

    func fail() {
        continuation?.resume(throwing: URLError(.badServerResponse)); continuation = nil
    }
}

@MainActor private final class PendingResolution {
    private var continuation: CheckedContinuation<PlaybackSourceResolution, Error>?
    var isWaiting: Bool {
        continuation != nil
    }

    func value() async throws -> PlaybackSourceResolution {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func succeed() {
        continuation?.resume(returning: PlaybackSourceResolution(url: URL(string: "https://example.invalid/video.mp4")!, playSessionID: nil, mediaSourceID: nil, playMethod: .directPlay, stereoLayout: .none, stereoFallbackReason: nil))
        continuation = nil
    }
}
