import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("Next Up removal contract")
struct NextUpRemovalTests {
    private func session(_ provider: FakeMediaProviderSession) -> SessionStore {
        SessionStore(client: JellyfinClientFactory.makeClient(url: URL(string: "https://example.invalid")!), user: StoredUser(id: "u", name: "User", serverID: "s"), server: ServerConnection(id: "s", name: "Server", url: URL(string: "https://example.invalid")!), mediaProvider: provider)
    }

    @Test("removal resets remote and offline resume, preserves watched state, and survives relaunch until playback or Add")
    func removalPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = UpNextPersistence(directory: directory.appendingPathComponent("queue"))
        let activityPersistence = NextUpActivityPersistence(directory: directory.appendingPathComponent("activity"))
        let queue = UpNextStore(persistence: persistence)
        let activity = NextUpActivityStore(persistence: activityPersistence)
        let progress = OfflinePlaybackProgressStore(directory: directory)
        let scope = AccountScope(serverID: "s", userID: "u")
        let item = MediaItem(id: "movie", type: .movie, userData: MediaUserData(playbackPositionTicks: 99, isWatched: false))
        queue.toggle(item, serverID: "s", userID: "u")
        progress.checkpoint(itemID: "movie", positionTicks: 99, scope: scope)
        var position = 99
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.progressHandler = { id, ticks in #expect(id == "movie"); position = ticks }
        try await queue.removeFromNextUp(item, session: session(provider), activity: activity, progress: progress)
        #expect(position == 0)
        #expect(provider.watchedRequests.isEmpty)
        #expect(progress.positionTicks(forItemID: "movie", scope: scope) == 0)
        #expect(progress.pendingCheckpoints(scope: scope).isEmpty)
        let reloaded = UpNextStore(persistence: persistence)
        let reloadedActivity = NextUpActivityStore(persistence: activityPersistence)
        #expect(!reloaded.contains(item, serverID: "s", userID: "u"))
        #expect(reloadedActivity.isDismissed("media:jellyfin:movie", scope: scope))
        reloadedActivity.recordPlayback(item: item, scope: scope)
        #expect(!reloadedActivity.isDismissed("media:jellyfin:movie", scope: scope))
        #expect(reloadedActivity.setDismissed("media:jellyfin:movie", dismissed: true, scope: scope))
        reloaded.toggle(item, serverID: "s", userID: "u")
        #expect(reloadedActivity.setDismissed("media:jellyfin:movie", dismissed: false, scope: scope))
        #expect(reloaded.contains(item, serverID: "s", userID: "u"))
        #expect(!reloadedActivity.isDismissed("media:jellyfin:movie", scope: scope))
    }

    @Test("failed remote reset leaves the saved entry, dismissal and offline checkpoint untouched")
    func removalFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = UpNextStore(persistence: UpNextPersistence(directory: directory.appendingPathComponent("queue")))
        let activity = NextUpActivityStore(persistence: NextUpActivityPersistence(directory: directory.appendingPathComponent("activity")))
        let progress = OfflinePlaybackProgressStore(directory: directory)
        let item = MediaItem(id: "movie", type: .movie)
        let scope = AccountScope(serverID: "s", userID: "u")
        queue.toggle(item, serverID: "s", userID: "u")
        progress.checkpoint(itemID: "movie", positionTicks: 99, scope: scope)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.progressHandler = { _, _ in throw GusError.offline }
        await #expect(throws: GusError.offline) {
            try await queue.removeFromNextUp(item, session: session(provider), activity: activity, progress: progress)
        }
        #expect(queue.contains(item, serverID: "s", userID: "u"))
        #expect(!activity.isDismissed("media:jellyfin:movie", scope: scope))
        #expect(progress.positionTicks(forItemID: "movie", scope: scope) == 99)
    }

    @Test("Mark Watched removes saved intent and Mark Unwatched cannot resurrect it")
    func watchedThenUnwatched() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = UpNextStore(persistence: UpNextPersistence(directory: directory.appendingPathComponent("queue")))
        let activity = NextUpActivityStore(persistence: NextUpActivityPersistence(directory: directory.appendingPathComponent("activity")))
        let progress = OfflinePlaybackProgressStore(directory: directory)
        var item = MediaItem(id: "episode", seriesID: "series", type: .episode, userData: MediaUserData(playbackPositionTicks: 10, isWatched: false))
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in item }
        provider.progressHandler = { _, ticks in item.userData?.playbackPositionTicks = ticks }
        provider.watchedHandler = { item.userData?.isWatched = !(provider.watchedRequests.last?.currentlyWatched ?? true) }
        queue.toggle(item, serverID: "s", userID: "u")
        let store = ItemDetailStore(item: item, session: session(provider))
        let scope = AccountScope(serverID: "s", userID: "u")
        for watched in [true, false] {
            await store.setWatched(watched, localProgress: progress, nextUp: queue, activity: activity)
            #expect(store.actionError == nil)
            #expect(store.item.userData?.isWatched == watched)
            #expect(store.item.userData?.playbackPositionTicks == 0)
            #expect(!queue.contains(item, serverID: "s", userID: "u"))
            #expect(activity.isDismissed("media:jellyfin:episode", scope: scope))
        }
    }

    @Test("removing a saved show clears only its resumable episodes across pages; playback restores it")
    func seriesRemovalAndCompletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = UpNextStore(persistence: UpNextPersistence(directory: directory.appendingPathComponent("queue")))
        let activity = NextUpActivityStore(persistence: NextUpActivityPersistence(directory: directory.appendingPathComponent("activity")))
        let progress = OfflinePlaybackProgressStore(directory: directory)
        let scope = AccountScope(serverID: "s", userID: "u")
        let show = MediaItem(id: "show", type: .series)
        let episode = MediaItem(id: "one", seriesID: "show", type: .episode)
        let resumes = [episode, MediaItem(id: "other", seriesID: "different", type: .episode), MediaItem(id: "two", seriesID: "show", type: .episode)]
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var offsets: [Int] = []
        var cleared: [String] = []
        provider.resumePageHandler = { start, _ in
            offsets.append(start)
            return MediaItemPage(items: Array(resumes.dropFirst(start).prefix(1)), totalRecordCount: resumes.count)
        }
        provider.progressHandler = { id, ticks in #expect(ticks == 0); cleared.append(id) }
        progress.checkpoint(itemID: "two", positionTicks: 99, scope: scope)
        progress.checkpoint(itemID: "other", positionTicks: 50, scope: scope)
        try await queue.removeFromNextUp(show, session: session(provider), activity: activity, progress: progress)
        #expect(offsets == [0, 1, 2])
        #expect(Set(cleared) == ["show", "one", "two"])
        #expect(progress.positionTicks(forItemID: "two", scope: scope) == 0)
        #expect(progress.positionTicks(forItemID: "other", scope: scope) == 50)
        #expect(activity.isDismissed(episode, scope: scope))
        activity.recordPlayback(item: episode, scope: scope)
        #expect(!activity.isDismissed(episode, scope: scope))
        activity.recordCompletion(item: episode, scope: scope)
        #expect(activity.isDismissed(episode, scope: scope))
        activity.recordPlayback(item: episode, scope: scope)
        #expect(!activity.isDismissed(episode, scope: scope))
    }
}
