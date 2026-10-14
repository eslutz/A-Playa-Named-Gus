import Foundation
@testable import Gus
import Testing

struct PlaybackActionTests {
    @Test func localZeroOverridesServerResumeAndCompletionRestarts() {
        let item = MediaItem(id: "movie", runTimeTicks: 100, userData: MediaUserData(playbackPositionTicks: 40))
        #expect(PlaybackActionPosition.ticks(for: item, localTicks: 0) == 0)
        #expect(PlaybackActionPosition.ticks(for: item, localTicks: 25) == 25)
        #expect(PlaybackActionPosition.ticks(for: item, localTicks: nil) == 40)
        #expect(PlaybackActionPosition.ticks(for: item, localTicks: 100) == 0)
        #expect(PlaybackActionPosition.ticks(for: item, localTicks: -1) == 0)
        #expect(PlaybackActionPosition.ticks(for: MediaItem(userData: MediaUserData(playbackPositionTicks: 0)), localTicks: nil) == nil)
    }

    @Test func playlistProgressUsesOccurrenceAndFinishedCursor() {
        let a = UUID(), b = UUID()
        let item = MediaItem(id: "same-movie", type: .movie)
        var playlist = VideoPlaylist(id: UUID(), name: "Queue", scope: AccountScope(serverID: "server", userID: "user"), entries: [
            VideoPlaylistEntry(id: a, reference: MediaReference(item: item, scope: AccountScope(serverID: "server", userID: "user"))),
            VideoPlaylistEntry(id: b, reference: MediaReference(item: item, scope: AccountScope(serverID: "server", userID: "user"))),
        ], cursor: nil, queued: false)
        #expect(playlist.playbackAction.hasProgress == false)
        #expect(playlist.playbackAction.entryID == a)
        playlist.cursor = PlaylistCursor(entryID: a, positionTicks: 0, finished: false)
        #expect(playlist.playbackAction.hasProgress == false)
        playlist.cursor = PlaylistCursor(entryID: a, positionTicks: 20, finished: false)
        #expect(playlist.playbackAction.hasProgress)
        playlist.cursor = PlaylistCursor(entryID: b, positionTicks: 0, finished: false)
        #expect(playlist.playbackAction.hasProgress)
        #expect(playlist.playbackAction.entryID == b)
        playlist.cursor = PlaylistCursor(entryID: b, positionTicks: 20, finished: true)
        #expect(playlist.playbackAction.hasProgress == false)
        #expect(playlist.playbackAction.entryID == a)
        playlist.cursor = PlaylistCursor(entryID: UUID(), positionTicks: 20, finished: false)
        #expect(playlist.playbackAction.isUnavailable)
        #expect(playlist.playbackAction.entryID == nil)
    }

    @Test func restartWindowIntentRoundTripsAndIsNotEqualToResume() throws {
        let item = MediaItem(id: "movie", type: .movie)
        let normal = ItemRef(item: item)
        var restart = normal
        restart.playbackStart = .fromBeginning
        #expect(restart != normal)
        let restored = try JSONDecoder().decode(ItemRef.self, from: JSONEncoder().encode(restart))
        #expect(restored.playbackStart == .fromBeginning)
        #expect(restored == restart)
    }

    @Test func reorderRejectsForeignScopeAndMovesOnlyTheSelectedOccurrence() {
        let scope = AccountScope(serverID: "s", userID: "u")
        let id = UUID(), a = UUID(), b = UUID(), c = UUID()
        let payload = PlaylistItemDrag(scope: scope, playlistID: id, entryID: a)
        #expect(payload.destination(in: [a, b, c], scope: scope, playlistID: id, before: c)?.before == c)
        #expect(payload.destination(in: [a, b, c], scope: AccountScope(serverID: "other", userID: "u"), playlistID: id, before: c) == nil)
        #expect(payload.destination(in: [a, b, c], scope: scope, playlistID: UUID(), before: c) == nil)
        #expect(payload.destination(in: [a, b, c], scope: scope, playlistID: id, before: b) == nil)
        #expect(payload.destination(in: [b, c], scope: scope, playlistID: id, before: c) == nil)
        #expect(payload.destination(in: [a, b, c], scope: scope, playlistID: id, before: nil)?.entryID == a)
    }
}

@MainActor
struct ItemRestartPreparationTests {
    @Test(arguments: [false, true]) func failedRestartPreservesCheckpointAndWatchedState(localOnly: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "restart-server", userID: "user")
        let item = MediaItem(id: "movie", name: "Movie", officialRating: "G", runTimeTicks: 100_000_000, type: .movie, userData: MediaUserData(playbackPositionTicks: 40_000_000, isWatched: localOnly))
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in item }
        provider.playbackHandler = { throw GusError.notFound }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: StoredUser(id: scope.userID, name: "User", serverID: scope.serverID), server: ServerConnection(id: scope.serverID, name: "Server", url: url), mediaProvider: provider)
        let progress = OfflinePlaybackProgressStore(directory: directory)
        progress.checkpoint(itemID: "movie", positionTicks: 60_000_000, scope: scope, item: item)
        let checkpoint = progress.pendingCheckpoints(scope: scope)
        let player = PlaybackStore(item: item, session: session, playbackRefresh: PlaybackRefreshStore(), localOnly: localOnly, localProgress: progress)
        defer { player.teardown() }
        await player.prepare(startTimeTicks: PlaybackStartIntent.fromBeginning.startTimeTicks)
        #expect(provider.playbackRequestedStartTicks == (localOnly ? [] : [0]))
        #expect(player.player == nil)
        #expect(player.state != .ready)
        #expect(progress.pendingCheckpoints(scope: scope) == checkpoint)
        #expect(player.item.userData?.isWatched == localOnly)
        #expect(player.item.userData?.playbackPositionTicks == 40_000_000)
    }
}
