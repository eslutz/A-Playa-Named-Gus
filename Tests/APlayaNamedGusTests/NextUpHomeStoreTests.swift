import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("Next Up Home loading")
struct NextUpHomeStoreTests {
    private func activityStore() -> NextUpActivityStore {
        NextUpActivityStore(persistence: NextUpActivityPersistence(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }

    private func home(_ provider: FakeMediaProviderSession, activity: NextUpActivityStore) -> HomeStore {
        let session = SessionStore(
            client: JellyfinClientFactory.makeClient(url: URL(string: "https://example.invalid")!),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: URL(string: "https://example.invalid")!),
            mediaProvider: provider
        )
        return HomeStore(session: session, activity: activity)
    }

    @Test("dismissed Next Up identities survive persistence without changing playback data")
    func dismissalPersistence() throws {
        let data = Data(#"{"activity":{},"firstSeenIDs":[],"dismissedIDs":["media:jellyfin:movie"]}"#.utf8)
        let snapshot = try JSONDecoder().decode(NextUpActivityPersistence.Snapshot.self, from: data)
        let encoded = try JSONEncoder().encode(snapshot)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["dismissedIDs"] as? [String] == ["media:jellyfin:movie"])
    }

    @Test("dismissal survives reload and refresh, stays account scoped, and playback restores the item")
    func dismissedAutomaticItem() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = NextUpActivityPersistence(directory: directory)
        let first = NextUpActivityStore(persistence: persistence)
        let scope = AccountScope(serverID: "s", userID: "u")
        let item = MediaItem(id: "movie", type: .movie, userData: MediaUserData(playbackPositionTicks: 30))
        #expect(first.setDismissed("media:jellyfin:movie", dismissed: true, scope: scope))
        let reloaded = NextUpActivityStore(persistence: persistence)
        #expect(!reloaded.isDismissed("media:jellyfin:movie", scope: AccountScope(serverID: "s", userID: "other")))
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.resumePageHandler = { _, _ in MediaItemPage(items: [item], totalRecordCount: 1) }
        let store = home(provider, activity: reloaded)
        await store.load()
        #expect(store.unifiedNextUp.isEmpty)
        await store.refresh()
        #expect(store.unifiedNextUp.isEmpty)
        #expect(store.resumeItems.first?.userData?.playbackPositionTicks == 30)
        reloaded.recordPlayback(item: item, scope: scope)
        await store.refresh()
        #expect(store.unifiedNextUp.map(\.id) == ["media:jellyfin:movie"])
    }

    @Test("legacy activity snapshots remain readable after adding dismissals")
    func legacyActivitySnapshot() throws {
        let snapshot = try JSONDecoder().decode(NextUpActivityPersistence.Snapshot.self, from: Data(#"{"activity":{},"firstSeenIDs":["media:jellyfin:legacy"]}"#.utf8))
        #expect(snapshot.firstSeenIDs == ["media:jellyfin:legacy"])
        #expect(snapshot.dismissedIDs == nil)
    }

    @Test("a failed automatic source preserves successful and local saved content")
    func partialSourceFailure() async {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.resumePageHandler = { _, _ in throw GusError.offline }
        provider.nextPageHandler = { _, _ in MediaItemPage(items: [MediaItem(id: "next", seriesID: "series", type: .episode)], totalRecordCount: 1) }
        let store = home(provider, activity: activityStore())
        let intent = UpNextEntry(id: UUID(), reference: MediaReference(item: MediaItem(id: "saved", type: .movie), scope: AccountScope(serverID: "s", userID: "u")))
        store.updateNextUp(saved: [intent], playlists: [])
        await store.load()
        #expect(Set(store.unifiedNextUp.compactMap { $0.item?.id }) == ["next", "saved"])
        #expect(store.errorMessage != nil)
        provider.nextPageHandler = { _, _ in throw GusError.offline }
        await store.refresh()
        #expect(Set(store.unifiedNextUp.compactMap { $0.item?.id }) == ["next", "saved"])
    }

    @Test("Show All incrementally loads beyond two hundred records and stops at the provider total")
    func incrementalPagination() async {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var offsets: [Int] = []
        provider.nextPageHandler = { start, limit in
            offsets.append(start)
            return MediaItemPage(items: (start ..< min(start + limit, 251)).map { MediaItem(id: "e\($0)", seriesID: "s\($0)", type: .episode) }, totalRecordCount: 251)
        }
        let store = home(provider, activity: activityStore())
        await store.load()
        #expect(store.unifiedNextUp.count == 50)
        #expect(store.hasMoreNextUp)
        for _ in 0 ..< 5 {
            await store.loadMoreNextUp()
        }
        #expect(offsets == [0, 50, 100, 150, 200, 250])
        #expect(store.unifiedNextUp.count == 251)
        #expect(!store.hasMoreNextUp)
        #expect(store.unifiedNextUp.allSatisfy { $0.activityAt == nil })
    }

    @Test("a failed next page keeps existing cards and retries the same provider offset")
    func pageFailureRetry() async {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var fail = true
        var offsets: [Int] = []
        provider.nextPageHandler = { start, limit in
            offsets.append(start)
            if start > 0, fail {
                throw GusError.offline
            }
            return MediaItemPage(items: (start ..< min(start + limit, 51)).map { MediaItem(id: "e\($0)", seriesID: "s\($0)", type: .episode) }, totalRecordCount: 51)
        }
        let store = home(provider, activity: activityStore())
        await store.load()
        await store.loadMoreNextUp()
        #expect(store.unifiedNextUp.count == 50)
        #expect(store.hasMoreNextUp)
        fail = false
        await store.loadMoreNextUp()
        #expect(offsets == [0, 50, 50])
        #expect(store.unifiedNextUp.count == 51)
    }

    @Test("a failed latest rail keeps its cache while another rail refreshes")
    func latestRailsFailIndependently() async {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.userViewsHandler = { [MediaItem(id: "a"), MediaItem(id: "b")] }
        provider.itemsHandler = { query in
            if query.includeTypes == [.movie] { return MediaItemPage(items: [MediaItem(id: "a0", type: .movie)], totalRecordCount: 1) }
            if query.includeTypes == [.book] { return MediaItemPage(items: [MediaItem(id: "b0", type: .book)], totalRecordCount: 1) }
            return MediaItemPage(items: [], totalRecordCount: 0)
        }
        let store = home(provider, activity: activityStore())
        await store.load()
        provider.itemsHandler = { query in
            if query.includeTypes == [.movie] { throw GusError.offline }
            if query.includeTypes == [.book] { return MediaItemPage(items: [MediaItem(id: "b1", type: .book)], totalRecordCount: 1) }
            return MediaItemPage(items: [], totalRecordCount: 0)
        }
        await store.refresh()
        #expect(store.latestSections.flatMap(\.items).compactMap(\.id) == ["a0", "b1"])
        #expect(store.errorMessage != nil)
    }

    @Test("explicit playback activity persists per account while discovery preserves unknown dates")
    func persistedActivityAndDiscovery() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = NextUpActivityPersistence(directory: directory)
        let first = NextUpActivityStore(persistence: persistence)
        let scope = AccountScope(serverID: "s", userID: "u")
        let other = AccountScope(serverID: "s", userID: "other")
        first.remember(["media:jellyfin:a", "media:jellyfin:b"], scope: scope)
        #expect(first.snapshot(scope: scope).isEmpty)
        first.recordPlayback(item: MediaItem(id: "a"), scope: scope, at: Date(timeIntervalSince1970: 10))
        let reloaded = NextUpActivityStore(persistence: persistence)
        #expect(reloaded.snapshot(scope: scope)["media:jellyfin:a"] == Date(timeIntervalSince1970: 10))
        #expect(reloaded.snapshot(scope: other).isEmpty)
        #expect(reloaded.firstSeenIDs(scope: scope) == ["media:jellyfin:a", "media:jellyfin:b"])
        reloaded.remember(["media:jellyfin:b", "media:jellyfin:a"], scope: scope)
        #expect(reloaded.firstSeenIDs(scope: scope) == ["media:jellyfin:a", "media:jellyfin:b"])
    }

    @Test("new next episode inherits real preceding playback activity while other saved episodes remain undated")
    func nextEpisodeInheritsSeriesActivity() {
        let activity = activityStore()
        let scope = AccountScope(serverID: "s", userID: "u")
        let date = Date(timeIntervalSince1970: 20)
        let completed = MediaItem(id: "completed", seriesID: "series", type: .episode, userData: MediaUserData(isWatched: true))
        activity.recordPlayback(item: completed, scope: scope, at: date)
        let next = MediaItem(id: "next", seriesID: "series", type: .episode)
        let other = UpNextEntry(id: UUID(), reference: MediaReference(item: MediaItem(id: "other", seriesID: "series", type: .episode), scope: scope))
        let first = NextUpBuilder.build(resume: [completed], nextEpisodes: [next], saved: [other], activity: activity.snapshot(scope: scope))
        #expect(first.first?.item?.id == "next")
        #expect(first.first?.reasons == [.nextEpisode])
        #expect(first.first?.activityAt == date)
        #expect(first.first { $0.item?.id == "other" }?.activityAt == nil)
        activity.remember(first.map(\.id), scope: scope)
        let refreshed = NextUpBuilder.build(resume: [], nextEpisodes: [next], saved: [other], activity: activity.snapshot(scope: scope), firstSeenIDs: activity.firstSeenIDs(scope: scope))
        #expect(refreshed == first)
        #expect(activity.snapshot(scope: scope)["media:jellyfin:series"] == date)
    }
}
