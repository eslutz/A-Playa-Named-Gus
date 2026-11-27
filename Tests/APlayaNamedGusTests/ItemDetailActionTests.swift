import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@Suite("Item detail actions")
struct ItemDetailActionTests {
    @Test("a failed related shelf refresh retains its content and can retry independently")
    @MainActor
    func relatedContentRefresh() async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let item = MediaItem(id: "movie", type: .movie)
        provider.itemHandler = { _ in item }
        provider.similarItemsHandler = { _ in [MediaItem(id: "similar", type: .movie)] }
        provider.specialFeaturesHandler = { _ in [MediaItem(id: "feature", type: .video)] }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(
            client: JellyfinClientFactory.makeClient(url: url),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: url),
            mediaProvider: provider
        )
        let store = ItemDetailStore(item: item, session: session)
        await store.load()
        provider.similarItemsHandler = { _ in throw GusError.offline }
        provider.specialFeaturesHandler = { _ in [MediaItem(id: "new-feature", type: .video)] }
        await store.load()
        #expect(store.state == .loaded)
        #expect(store.similarItems.map(\.id) == ["similar"])
        #expect(store.specialFeatures.map(\.id) == ["new-feature"])
        #expect(store.relatedContentError != nil)
        provider.similarItemsHandler = { _ in [MediaItem(id: "new-similar", type: .movie)] }
        await store.retryRelatedContent()
        #expect(store.relatedContentError == nil)
        #expect(store.similarItems.map(\.id) == ["new-similar"])
    }

    @Test("ambiguous favorite writes reconcile without repeating a toggle", arguments: [true, false])
    @MainActor
    func uncertainFavoriteWrite(serverApplied: Bool) async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var remote = MediaItem(id: "movie", type: .movie, userData: MediaUserData(isFavorite: false))
        var writes = 0
        provider.itemHandler = { _ in remote }
        provider.favoriteHandler = {
            writes += 1
            if serverApplied {
                remote.userData?.isFavorite = true
            }
            throw GusError.timeout
        }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(
            client: JellyfinClientFactory.makeClient(url: url),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: url),
            mediaProvider: provider
        )
        let store = ItemDetailStore(item: remote, session: session)
        await store.toggleFavorite()
        #expect(store.actionOutcome == .uncertain)
        #expect(store.needsUserDataRefresh)
        await store.toggleFavorite()
        #expect(writes == 1)
        if serverApplied {
            #expect(store.actionOutcome == .confirmed)
            #expect(!store.needsUserDataRefresh)
        } else {
            #expect(store.needsUserDataRefresh)
            #expect(store.canKeepCurrentUserData)
            store.keepCurrentUserData()
            #expect(!store.needsUserDataRefresh)
            #expect(store.actionOutcome == nil)
            #expect(writes == 1)
        }
    }

    @Test("a metadata refresh cannot invert the watched or favorite action the user selected", arguments: [true, false])
    @MainActor
    func togglesPreserveDisplayedIntent(displayedStatus: Bool) async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let displayed = MediaItem(id: "movie", type: .movie, userData: MediaUserData(isWatched: displayedStatus, isFavorite: displayedStatus))
        var remote = MediaItem(id: "movie", type: .movie, userData: MediaUserData(isWatched: !displayedStatus, isFavorite: !displayedStatus))
        provider.itemHandler = { _ in remote }
        provider.favoriteHandler = {
            remote.userData?.isFavorite = !(provider.favoriteRequests.last?.currentlyFavorite ?? !displayedStatus)
        }
        provider.watchedHandler = {
            remote.userData?.isWatched = !(provider.watchedRequests.last?.currentlyWatched ?? !displayedStatus)
        }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(
            client: JellyfinClientFactory.makeClient(url: url),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: url),
            mediaProvider: provider
        )
        let favoriteStore = ItemDetailStore(item: displayed, session: session)
        await favoriteStore.toggleFavorite()
        #expect(provider.favoriteRequests.count == 1)
        #expect(provider.favoriteRequests.first?.currentlyFavorite == displayedStatus)
        #expect(favoriteStore.item.userData?.isFavorite == !displayedStatus)
        #expect(favoriteStore.actionOutcome == .confirmed)

        let watchedStore = ItemDetailStore(item: displayed, session: session)
        await watchedStore.toggleWatched()
        #expect(provider.watchedRequests.count == 1)
        #expect(provider.watchedRequests.first?.currentlyWatched == displayedStatus)
        #expect(watchedStore.item.userData?.isWatched == !displayedStatus)
        #expect(watchedStore.actionOutcome == .confirmed)
    }

    @Test("explicit watched actions reset resume data and select the requested endpoint despite stale metadata", arguments: [true, false])
    @MainActor
    func explicitWatchedAction(watched: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let progress = OfflinePlaybackProgressStore(directory: directory)
        let scope = AccountScope(serverID: "s", userID: "u")
        progress.checkpoint(itemID: "movie", positionTicks: 99, scope: scope)
        progress.checkpoint(itemID: "other", positionTicks: 50, scope: scope)
        var remote = MediaItem(id: "movie", type: .movie, userData: MediaUserData(playbackPositionTicks: 99, isWatched: watched))
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in remote }
        provider.progressHandler = { id, ticks in
            #expect(id == "movie")
            #expect(ticks == 0)
            remote.userData?.playbackPositionTicks = ticks
        }
        provider.watchedHandler = {
            remote.userData?.isWatched = !(provider.watchedRequests.last?.currentlyWatched ?? watched)
        }
        let session = try SessionStore(
            client: JellyfinClientFactory.makeClient(url: #require(URL(string: "https://example.invalid"))),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: #require(URL(string: "https://example.invalid"))),
            mediaProvider: provider
        )
        let store = ItemDetailStore(item: MediaItem(id: "movie", type: .movie, userData: MediaUserData(isWatched: !watched)), session: session)
        await store.setWatched(watched, localProgress: progress)
        #expect(store.actionError == nil)
        #expect(store.item.userData?.isWatched == watched)
        #expect(store.item.userData?.playbackPositionTicks == 0)
        #expect(provider.watchedRequests.count == 1)
        #expect(provider.watchedRequests.first?.currentlyWatched == !watched)
        #expect(progress.positionTicks(forItemID: "movie", scope: scope) == 0)
        #expect(!progress.pendingCheckpoints(scope: scope).contains { $0.itemID == "movie" })
        #expect(progress.positionTicks(forItemID: "other", scope: scope) == 50)
    }

    @Test("failed progress reset preserves offline progress and never marks the item")
    @MainActor
    func failedWatchedAction() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let progress = OfflinePlaybackProgressStore(directory: directory)
        let scope = AccountScope(serverID: "s", userID: "u")
        progress.checkpoint(itemID: "movie", positionTicks: 99, scope: scope)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { id in MediaItem(id: id, type: .movie) }
        provider.progressHandler = { _, _ in throw GusError.offline }
        let session = try SessionStore(
            client: JellyfinClientFactory.makeClient(url: #require(URL(string: "https://example.invalid"))),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: #require(URL(string: "https://example.invalid"))),
            mediaProvider: provider
        )
        let store = ItemDetailStore(item: MediaItem(id: "movie", type: .movie), session: session)
        await store.setWatched(true, localProgress: progress)
        #expect(store.actionError != nil)
        #expect(provider.watchedRequests.isEmpty)
        #expect(progress.positionTicks(forItemID: "movie", scope: scope) == 99)
    }

    @Test("marking a book unread clears its precise location after the server accepts the reset")
    @MainActor
    func markBookUnreadClearsLocator() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bookProgress = BookProgressStore(directory: directory)
        let progress = OfflinePlaybackProgressStore(directory: directory)
        let scope = AccountScope(serverID: "s", userID: "u")
        let locator = #"{"locations":{"totalProgression":0.4}}"#
        bookProgress.save(locatorJSON: locator, forItemID: "book", scope: scope)
        bookProgress.save(locatorJSON: locator, forItemID: "another", scope: scope)
        progress.checkpoint(itemID: "book", positionTicks: 4_000_000, scope: scope)
        var remote = MediaItem(id: "book", type: .book, userData: MediaUserData(playbackPositionTicks: 4_000_000, isWatched: true))
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in remote }
        provider.progressHandler = { _, ticks in remote.userData?.playbackPositionTicks = ticks }
        provider.watchedHandler = { remote.userData?.isWatched = false }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(
            client: JellyfinClientFactory.makeClient(url: url),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: url),
            mediaProvider: provider
        )
        let store = ItemDetailStore(item: remote, session: session)
        await store.setWatched(false, localProgress: progress, bookProgress: bookProgress)
        #expect(store.actionOutcome == .confirmed)
        #expect(remote.userData?.playbackPositionTicks == 0)
        let reloaded = BookProgressStore(directory: directory)
        #expect(reloaded.locatorJSON(forItemID: "book", scope: scope) == nil)
        #expect(reloaded.locatorJSON(forItemID: "another", scope: scope) == locator)
        #expect(BookDetailProgress.reading(locator: nil, localTicks: progress.positionTicks(forItemID: "book", scope: scope), data: remote.userData) == nil)
    }

    @Test(
        "book status actions reset all sources from any starting state",
        arguments: [MediaItemType.book, .audioBook],
        [0, 1, 2]
    )
    @MainActor
    func bookStatusActions(type: MediaItemType, startingState: Int) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let progress = OfflinePlaybackProgressStore(directory: directory)
        let bookProgress = BookProgressStore(directory: directory)
        let scope = AccountScope(serverID: "s", userID: "u")
        let otherScope = AccountScope(serverID: "s", userID: "other")
        let url = try #require(URL(string: "https://example.invalid"))
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let session = SessionStore(
            client: JellyfinClientFactory.makeClient(url: url),
            user: StoredUser(id: scope.userID, name: "User", serverID: scope.serverID),
            server: ServerConnection(id: scope.serverID, name: "Server", url: url),
            mediaProvider: provider
        )
        let initialTicks = startingState == 1 ? 40 : 0
        var remote = MediaItem(id: "title", type: type, userData: MediaUserData(playbackPositionTicks: initialTicks, isWatched: startingState == 2))
        provider.itemHandler = { _ in remote }
        provider.progressHandler = { _, ticks in remote.userData?.playbackPositionTicks = ticks }
        provider.watchedHandler = {
            remote.userData?.isWatched = provider.watchedRequests.last?.currentlyWatched == false
        }

        for complete in [false, true] {
            remote.userData?.isWatched = startingState == 2
            remote.userData?.playbackPositionTicks = initialTicks
            let locator = #"{"locations":{"totalProgression":0.4}}"#
            if initialTicks > 0 {
                progress.checkpoint(itemID: "title", positionTicks: initialTicks, scope: scope, mediaSourceID: "alternate")
                if type == .book {
                    bookProgress.save(locatorJSON: locator, forItemID: "title", scope: scope)
                }
            }
            progress.checkpoint(itemID: "title", positionTicks: 60, scope: otherScope)

            let store = ItemDetailStore(item: remote, session: session)
            await store.setWatched(complete, localProgress: progress, bookProgress: bookProgress)
            #expect(store.actionOutcome == .confirmed)
            #expect(remote.userData?.isWatched == complete)
            #expect(remote.userData?.playbackPositionTicks == 0)
            #expect(bookProgress.locatorJSON(forItemID: "title", scope: scope) == nil)
            #expect(progress.pendingCheckpoints(scope: scope).isEmpty)
            #expect(progress.hasResetCheckpoint(itemID: "title", scope: scope))
            if initialTicks > 0 {
                #expect(progress.hasResetCheckpoint(itemID: "title", scope: scope, mediaSourceID: "alternate"))
            }
            #expect(progress.positionTicks(forItemID: "title", scope: otherScope) == 60)
        }
    }

    @Test("a rejected watched write after a saved progress reset requires readback before another action")
    @MainActor
    func partiallyAcceptedWatchedAction() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let progress = OfflinePlaybackProgressStore(directory: directory)
        let scope = AccountScope(serverID: "s", userID: "u")
        progress.checkpoint(itemID: "movie", positionTicks: 99, scope: scope)
        var remote = MediaItem(id: "movie", type: .movie, userData: MediaUserData(playbackPositionTicks: 99, isWatched: false))
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in remote }
        provider.progressHandler = { _, ticks in remote.userData?.playbackPositionTicks = ticks }
        provider.watchedHandler = { throw GusError.forbidden }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(
            client: JellyfinClientFactory.makeClient(url: url),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: url),
            mediaProvider: provider
        )
        let store = ItemDetailStore(item: remote, session: session)
        await store.setWatched(true, localProgress: progress)
        #expect(session.isActive)
        #expect(store.actionOutcome == .uncertain)
        #expect(store.needsUserDataRefresh)
        #expect(store.actionError != nil)
        #expect(progress.positionTicks(forItemID: "movie", scope: scope) == 0)

        await store.setWatched(true, localProgress: progress)
        #expect(provider.watchedRequests.count == 1)
        #expect(store.item.userData?.playbackPositionTicks == 0)
        #expect(store.item.userData?.isWatched == false)
        #expect(store.needsUserDataRefresh)
        #expect(store.canKeepCurrentUserData)
        store.keepCurrentUserData()
        #expect(!store.needsUserDataRefresh)
        #expect(store.actionOutcome == nil)
    }

    @Test("authoritative replacement metadata clears a cached missing-item failure")
    @MainActor
    func replacementClearsCachedFailure() async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in throw GusError.notFound }
        let session = try SessionStore(
            client: JellyfinClientFactory.makeClient(url: #require(URL(string: "https://example.invalid"))),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: #require(URL(string: "https://example.invalid"))),
            mediaProvider: provider
        )
        let store = ItemDetailStore(item: MediaItem(id: "old", type: .movie), session: session)
        await store.load()
        store.acceptResolvedMetadata(MediaItem(id: "new", name: "Current", type: .movie))
        #expect(store.item.id == "new")
        #expect(store.state == .loaded)
    }

    @Test("adopting a replacement reloads related media and the episode browser")
    @MainActor
    func replacementReloadsRelatedContent() async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { id in MediaItem(id: id, type: .series) }
        provider.similarItemsHandler = { id in [MediaItem(id: "similar-\(id)", type: .movie)] }
        provider.specialFeaturesHandler = { id in [MediaItem(id: "special-\(id)", type: .movie)] }
        provider.seasonsHandler = { [MediaItem(id: "old-season", indexNumber: 1, type: .season)] }
        provider.episodesHandler = { id in MediaItemPage(items: [MediaItem(id: "episode-\(id)", type: .episode)], totalRecordCount: 1) }
        let session = try SessionStore(
            client: JellyfinClientFactory.makeClient(url: #require(URL(string: "https://example.invalid"))),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: #require(URL(string: "https://example.invalid"))),
            mediaProvider: provider
        )
        let store = ItemDetailStore(item: MediaItem(id: "old", type: .series), session: session)
        await store.load()
        #expect(store.seriesStore?.episodes.map(\.id) == ["episode-old-season"])
        provider.seasonsHandler = { [MediaItem(id: "new-season", indexNumber: 1, type: .season)] }
        store.acceptResolvedMetadata(MediaItem(id: "new", type: .series))
        for _ in 0 ..< 1000 {
            if store.seriesStore?.episodesState == .loaded {
                break
            }
            await Task.yield()
        }
        #expect(store.similarItems.map(\.id) == ["similar-new"])
        #expect(store.specialFeatures.map(\.id) == ["special-new"])
        #expect(store.seriesStore?.series.id == "new")
        #expect(store.seriesStore?.seasons.map(\.id) == ["new-season"])
        #expect(store.seriesStore?.episodes.map(\.id) == ["episode-new-season"])
    }

    @Test("late related responses from a previous replacement cannot overwrite the newest one")
    @MainActor
    func replacementRejectsLateRelatedContent() async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var continuation: CheckedContinuation<[MediaItem], Never>?
        provider.similarItemsHandler = { id in
            if id == "intermediate" {
                return await withCheckedContinuation { continuation = $0 }
            }
            return [MediaItem(id: "similar-\(id)", type: .movie)]
        }
        let session = try SessionStore(
            client: JellyfinClientFactory.makeClient(url: #require(URL(string: "https://example.invalid"))),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: #require(URL(string: "https://example.invalid"))),
            mediaProvider: provider
        )
        let store = ItemDetailStore(item: MediaItem(id: "old", type: .movie), session: session)
        store.acceptResolvedMetadata(MediaItem(id: "intermediate", type: .movie))
        for _ in 0 ..< 1000 {
            if continuation != nil {
                break
            }
            await Task.yield()
        }
        #expect(continuation != nil)
        store.acceptResolvedMetadata(MediaItem(id: "new", type: .movie))
        continuation?.resume(returning: [MediaItem(id: "stale", type: .movie)])
        for _ in 0 ..< 1000 {
            if store.similarItems.first?.id == "similar-new" {
                break
            }
            await Task.yield()
        }
        #expect(store.item.id == "new")
        #expect(store.similarItems.map(\.id) == ["similar-new"])
    }

    @Test("next up cards use a fixed widescreen frame")
    func nextUpCardsUseWidescreenFrame() {
        #expect(abs(MediaRailMetrics.aspectRatio(for: .backdrop) - (16.0 / 9.0)) < 0.000_001)
    }
}
