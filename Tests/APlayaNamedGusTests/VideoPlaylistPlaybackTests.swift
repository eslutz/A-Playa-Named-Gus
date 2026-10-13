import Foundation
@testable import Gus
import Testing

struct VideoPlaylistPlaybackTests {
    @Test func orderedDuplicatesAdvanceOnlyOnce() {
        let a = UUID(), b = UUID(), c = UUID()
        var sequence = PlaylistPlaybackSequence(entryIDs: [a, b, c], startID: a)
        #expect(sequence.currentID == a)
        #expect(sequence.advance(after: a, surviving: [a, b, c]) == b)
        #expect(sequence.advance(after: a, surviving: [a, b, c]) == b)
        #expect(sequence.advance(after: b, surviving: [a, b, c]) == c)
        #expect(sequence.advance(after: c, surviving: [a, b, c]) == nil)
    }

    @Test func removalsAreHonoredAndNewEntriesWaitForNextSession() {
        let a = UUID(), b = UUID(), c = UUID(), added = UUID()
        var sequence = PlaylistPlaybackSequence(entryIDs: [a, b, c], startID: a)
        #expect(sequence.advance(after: a, surviving: [c, added]) == c)
        #expect(sequence.advance(after: c, surviving: [c, added]) == nil)
    }

    @Test func playFromHereKeepsSelectedEntry() {
        let ids = [UUID(), UUID(), UUID()]
        let sequence = PlaylistPlaybackSequence(entryIDs: ids, startID: ids[1])
        #expect(sequence.currentID == ids[1])
        #expect(sequence.remainingIDs == Array(ids.suffix(2)))
    }
}

struct VideoPlaylistNavigationTests {
    @Test func playlistWindowIdentitySurvivesRoundTripAndPreservesDuplicates() throws {
        let playlist = UUID(), firstEntry = UUID(), repeatedEntry = UUID()
        let item = MediaItem(id: "same-episode", type: .episode)
        let first = ItemRef(item: item, serverID: "server", userID: "user", playlistID: playlist, playlistEntryID: firstEntry, playlistFromBeginning: true)
        let repeated = ItemRef(item: item, serverID: "server", userID: "user", playlistID: playlist, playlistEntryID: repeatedEntry, playlistFromBeginning: true)
        #expect(first != repeated)
        let restored = try JSONDecoder().decode(ItemRef.self, from: JSONEncoder().encode(first))
        #expect(restored == first)
        #expect(restored.playlistID == playlist)
        #expect(restored.playlistFromBeginning == true)
    }

    @MainActor @Test func playlistsAreRequiredAndCannotBeHidden() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let preferences = NavigationPreferencesStore(directory: folder)
        let sections = preferences.resolvedSections(libraries: [], serverID: "server", userID: "user")
        #expect(sections.contains { $0.id == NavigationSectionPreference.playlistsID && $0.isVisible && !$0.canHide })
        preferences.setVisibility(false, forSectionID: NavigationSectionPreference.playlistsID, libraries: [], serverID: "server", userID: "user")
        #expect(preferences.visibleSections(libraries: [], serverID: "server", userID: "user").contains { $0.id == NavigationSectionPreference.playlistsID })
    }
}

@MainActor
struct VideoPlaylistPreparationTests {
    @Test func removalWhileResolvingExposesRecovery() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let scope = AccountScope(serverID: "playlist-resolution-server", userID: "user")
        let playlists = VideoPlaylistsStore(directory: folder, syncEnabled: false)
        let id = try #require(playlists.create(name: "Queue", scope: scope))
        let item = MediaItem(id: "removal-test-movie", name: "Movie", type: .movie)
        #expect(playlists.add(item: item, to: id, scope: scope))
        let entry = try #require(playlists.playlist(id: id, scope: scope)?.entries.first)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var continuation: CheckedContinuation<MediaItem, Never>?
        provider.itemHandler = { _ in await withCheckedContinuation { continuation = $0 } }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: StoredUser(id: scope.userID, name: "User", serverID: scope.serverID), server: ServerConnection(id: scope.serverID, name: "Server", url: url), mediaProvider: provider)
        let player = PlaybackStore(item: item, session: session, playbackRefresh: PlaybackRefreshStore())
        let coordinator = VideoPlaylistPlaybackCoordinator(playlistID: id, entryID: entry.id, fromBeginning: true, playlists: playlists, session: session, downloads: .shared)
        let preparation = Task { await coordinator.start(player) }
        while continuation == nil {
            await Task.yield()
        }
        playlists.remove(entryID: entry.id, from: id, scope: scope)
        continuation?.resume(returning: item)
        await preparation.value
        #expect(coordinator.errorMessage != nil)
        #expect(player.state == .idle)
        #expect(provider.playbackResolutionCallCount == 0)
        coordinator.stop(player)
    }
}
