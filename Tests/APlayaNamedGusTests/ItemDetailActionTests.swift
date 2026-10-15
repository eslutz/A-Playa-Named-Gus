import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@Suite("Item detail actions")
struct ItemDetailActionTests {
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
