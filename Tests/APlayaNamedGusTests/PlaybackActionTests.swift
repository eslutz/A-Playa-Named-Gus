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

    @Test func nativeWindowIdentityIgnoresRestartAndOccurrenceCommands() throws {
        let normal = ItemRef(item: MediaItem(id: "movie", type: .movie), serverID: "server", userID: "user")
        var restart = normal
        restart.playbackRequest = PlaybackRequest(item: restart.item, start: .fromBeginning)
        #expect(PlayerWindowRef(normal) == PlayerWindowRef(restart))
        let playlist = UUID()
        var first = normal
        first.playlistID = playlist; first.playlistEntryID = UUID(); first.playlistFromBeginning = true
        var later = first
        later.playlistEntryID = UUID()
        #expect(PlayerWindowRef(first) == PlayerWindowRef(later))
        var other = restart
        other.serverID = "another-server"
        #expect(PlayerWindowRef(other) != PlayerWindowRef(normal))
        other = restart; other.localOnly = true
        #expect(PlayerWindowRef(other) != PlayerWindowRef(normal))
        let restored = try JSONDecoder().decode(PlayerWindowRef.self, from: JSONEncoder().encode(PlayerWindowRef(first)))
        #expect(restored.fallback.resolvedPlaybackRequest.start == .automatic)
        #expect(restored.fallback.playlistEntryID == nil)
        #expect(restored.fallback.playlistFromBeginning == nil)
    }

    @Test func restartWindowIntentRoundTripsAndIsNotEqualToResume() throws {
        let item = MediaItem(id: "movie", type: .movie)
        let normal = ItemRef(item: item)
        var restart = normal
        restart.playbackRequest = PlaybackRequest(item: restart.item, start: .fromBeginning)
        #expect(restart != normal)
        let restored = try JSONDecoder().decode(ItemRef.self, from: JSONEncoder().encode(restart))
        #expect(restored.resolvedPlaybackRequest.start == .fromBeginning)
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
struct PlaybackStartOverrideTests {
    @Test("only a same-account/item/source player checkpoint consumes a retained start", arguments: [false, true])
    func scopedConsumption(fromBeginning: Bool) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let progress = OfflinePlaybackProgressStore(directory: directory)
        let session = makeSession()
        let source = MediaSource(id: "B", mediaStreams: [.init(index: 7, language: "eng", title: "Commentary", type: .audio)], runTimeTicks: 450_000_000)
        let item = MediaItem(id: "movie", mediaSources: [MediaSource(id: "A", runTimeTicks: 300_000_000), source], runTimeTicks: 300_000_000, type: .movie)
        let base = PlaybackRequest(item: item, streamSelection: .init(audioStreamIndex: 7, subtitleStreamIndex: -1, mediaSourceID: "B"), audioTrack: source.mediaStreams.first, subtitleIntent: .off, presentation: .twoD)
        let scope = session.references.scope
        progress.checkpoint(itemID: "movie", positionTicks: 100, scope: scope, mediaSourceID: "B")
        let ticks = fromBeginning ? 0 : 200
        let pending = PlaybackStartOverride(request: base, ticks: ticks, fromBeginning: fromBeginning, session: session, progress: progress)
        let frozen = pending.applying(to: base, session: session, progress: progress)
        let identity = PlaybackPresentationIdentity(request: frozen, sessionGeneration: session.lease.generation)
        progress.checkpoint(itemID: "movie", positionTicks: 1, scope: scope, mediaSourceID: "A")
        progress.checkpoint(itemID: "other", positionTicks: 1, scope: scope, mediaSourceID: "B")
        progress.checkpoint(itemID: "movie", positionTicks: 1, scope: AccountScope(serverID: "other", userID: scope.userID), mediaSourceID: "B")
        #expect(pending.applying(to: base, session: session, progress: progress).requestedStartTicks == ticks)
        // A same-position checkpoint still proves actual playback occurred.
        progress.checkpoint(itemID: "movie", positionTicks: ticks, scope: scope, mediaSourceID: "B")
        let next = pending.applying(to: base, session: session, progress: progress)
        #expect(next.start == .automatic && next.startPositionTicks == nil)
        #expect(next.streamSelection == base.streamSelection)
        #expect(next.audioTrack == base.audioTrack && next.subtitleIntent == .off && next.presentation == .twoD)
        #expect(frozen.requestedStartTicks == ticks)
        #expect(PlaybackPresentationIdentity(request: frozen, sessionGeneration: session.lease.generation) == identity)
        let fresh = PlaybackStartOverride(request: base, ticks: 0, fromBeginning: true, session: session, progress: progress)
        #expect(fresh.applying(to: base, session: session, progress: progress).start == .fromBeginning)
    }

    @Test("reference and sync mutations are not playback receipts")
    func metadataDoesNotConsume() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let progress = OfflinePlaybackProgressStore(directory: directory)
        let session = makeSession()
        let base = PlaybackRequest(item: MediaItem(id: "movie", mediaSources: [.init(id: "B")]), streamSelection: .init(mediaSourceID: "B"))
        let scope = session.references.scope
        progress.checkpoint(itemID: "movie", positionTicks: 60, scope: scope, mediaSourceID: "B")
        let pending = PlaybackStartOverride(request: base, ticks: 0, fromBeginning: true, session: session, progress: progress)
        await progress.sync(scope: scope, isCurrentScope: { true }) { _ in }
        #expect(pending.applying(to: base, session: session, progress: progress).start == .fromBeginning)
        progress.checkpoint(itemID: "movie", positionTicks: 60, scope: scope, mediaSourceID: "B")
        let refreshed = PlaybackStartOverride(request: base, ticks: 0, fromBeginning: true, session: session, progress: progress)
        progress.offerTransfer(from: "movie", to: MediaItem(id: "replacement"), scope: scope, mediaSourceID: "B")
        progress.resetCheckpoint(itemID: "movie", scope: scope)
        #expect(refreshed.applying(to: base, session: session, progress: progress).start == .fromBeginning)
        #expect(pending.applying(to: base, session: session, progress: progress).start == .automatic)
    }

    @Test("purge, retired lease and unknown source cannot reactivate or falsely consume a start")
    func invalidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let progress = OfflinePlaybackProgressStore(directory: directory)
        let session = makeSession()
        let base = PlaybackRequest(item: MediaItem(id: "movie", mediaSources: [.init(id: "B")]), streamSelection: .init(mediaSourceID: "B"))
        let scope = session.references.scope
        let pending = PlaybackStartOverride(request: base, ticks: 0, fromBeginning: true, session: session, progress: progress)
        let oldWriter = progress.writerToken(for: scope)
        progress.checkpoint(itemID: "movie", positionTicks: 5, scope: scope, mediaSourceID: "B")
        #expect(pending.applying(to: base, session: session, progress: progress).requestedStartTicks == nil)
        progress.deleteCheckpoints(scope: scope)
        progress.checkpoint(itemID: "movie", positionTicks: 9, scope: scope, writerToken: oldWriter, mediaSourceID: "B")
        #expect(progress.playbackGeneration(forItemID: "movie", scope: scope, mediaSourceID: "B") == nil)
        #expect(pending.applying(to: base, session: session, progress: progress).requestedStartTicks == nil)
        let unknown = PlaybackRequest(item: MediaItem(id: "unknown"))
        let unknownStart = PlaybackStartOverride(request: unknown, ticks: 0, fromBeginning: true, session: session, progress: progress)
        progress.checkpoint(itemID: "unknown", positionTicks: 10, scope: scope, mediaSourceID: "different")
        #expect(unknownStart.applying(to: unknown, session: session, progress: progress).start == .fromBeginning)
        let otherLease = makeSession()
        #expect(unknownStart.applying(to: unknown, session: otherLease, progress: progress).start == .automatic)
        session.invalidate()
        #expect(unknownStart.applying(to: unknown, session: session, progress: progress).start == .automatic)
        let restored = OfflinePlaybackProgressStore(directory: directory)
        #expect(restored.playbackGeneration(forItemID: "unknown", scope: scope, mediaSourceID: "different") == nil)
        let json = try String(contentsOf: directory.appendingPathComponent("offline-playback-progress.json"), encoding: .utf8)
        #expect(!json.contains("playbackGeneration"))
    }

    @Test("online source checkpoints use the selected duration and shared resume bounds")
    func selectedSourcePosition() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let progress = OfflinePlaybackProgressStore(directory: directory)
        let session = makeSession()
        let item = MediaItem(id: "movie", mediaSources: [.init(id: "A", runTimeTicks: 300_000_000), .init(id: "B", runTimeTicks: 450_000_000), .init(id: "unknown-duration")], runTimeTicks: 300_000_000, userData: MediaUserData(playbackPositionTicks: 331_980_000))
        progress.checkpoint(itemID: "movie", positionTicks: 331_980_000, scope: session.references.scope, mediaSourceID: "B")
        progress.checkpoint(itemID: "movie", positionTicks: 331_980_000, scope: session.references.scope, mediaSourceID: "unknown-duration")
        #expect(PlaybackChoicePosition.ticks(for: PlaybackRequest(item: item, streamSelection: .init(mediaSourceID: "B")), session: session, progress: progress) == 331_980_000)
        #expect(PlaybackChoicePosition.ticks(for: PlaybackRequest(item: item, streamSelection: .init(mediaSourceID: "A")), session: session, progress: progress) == 0)
        #expect(PlaybackChoicePosition.ticks(for: PlaybackRequest(item: item, streamSelection: .init(mediaSourceID: "unknown-duration")), session: session, progress: progress) == 331_980_000)
        #expect(PlaybackChoicePosition.ticks(for: PlaybackRequest(item: item), session: session, progress: progress) == 0)
        #expect(!PlaybackActionPosition.canResume(at: 331_980_000, durationTicks: 300_000_000))
        #expect(PlaybackActionPosition.canResume(at: 331_980_000, durationTicks: 450_000_000))
        #expect(PlaybackActionPosition.canResume(at: 331_980_000, durationTicks: nil))
        #expect(PlaybackActionPosition.canResume(at: 331_980_000, durationTicks: 0))
        #expect(!PlaybackActionPosition.canResume(at: -1, durationTicks: nil))
    }

    private func makeSession() -> SessionStore {
        let url = URL(string: "https://example.invalid")!
        return SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: StoredUser(id: "u", name: "User", serverID: "s"), server: ServerConnection(id: "s", name: "Server", url: url))
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
        let base = PlaybackRequest(item: item)
        let pending = PlaybackStartOverride(request: base, ticks: 0, fromBeginning: true, session: session, progress: progress)
        let player = PlaybackStore(request: pending.applying(to: base, session: session, progress: progress), session: session, playbackRefresh: PlaybackRefreshStore(), localOnly: localOnly, localProgress: progress)
        defer { player.teardown() }
        await player.prepare(startTimeTicks: PlaybackStartIntent.fromBeginning.startTimeTicks)
        #expect(provider.playbackRequestedStartTicks == (localOnly ? [] : [0]))
        #expect(player.player == nil)
        #expect(player.state != .ready)
        #expect(progress.pendingCheckpoints(scope: scope) == checkpoint)
        #expect(player.item.userData?.isWatched == localOnly)
        #expect(player.item.userData?.playbackPositionTicks == 40_000_000)
        #expect(pending.applying(to: base, session: session, progress: progress).start == .fromBeginning)
    }
}

@MainActor struct PlayerWindowRequestTests {
    @Test func sameItemSourceAndTimestampCommandsReplaceTheActiveWindowPlayer() throws {
        let requests = PlayerWindowRequests()
        var ref = ItemRef(item: MediaItem(id: "movie", type: .movie), serverID: "s", userID: "u")
        let window = requests.request(ref)
        requests.activate(window)
        let original = try #require(requests.requests[window]?.id)
        ref.playbackRequest = PlaybackRequest(item: ref.item, streamSelection: .init(audioStreamIndex: nil, subtitleStreamIndex: nil, mediaSourceID: "alternate"), startPositionTicks: 90_000_000)
        #expect(requests.request(ref) == window)
        let sourceChange = try #require(requests.requests[window])
        #expect(sourceChange.id != original)
        #expect(sourceChange.ref.resolvedPlaybackRequest.streamSelection.mediaSourceID == "alternate")
        #expect(sourceChange.ref.resolvedPlaybackRequest.requestedStartTicks == 90_000_000)
        _ = requests.request(ref)
        #expect(requests.requests[window]?.id == sourceChange.id)
        ref.playbackRequest?.startPositionTicks = 120_000_000
        _ = requests.request(ref)
        #expect(requests.requests[window]?.id != sourceChange.id)
    }

    @Test func presentationIdentityChangesForIncomingIntentAndCredentialLease() {
        let item = MediaItem(id: "same-item", type: .movie)
        let lease = UUID()
        let initial = PlaybackPresentationIdentity(request: PlaybackRequest(item: item), sessionGeneration: lease)
        var changed = initial.request
        changed.streamSelection.mediaSourceID = "other-cut"
        #expect(initial != PlaybackPresentationIdentity(request: changed, sessionGeneration: lease))
        changed = initial.request
        changed.startPositionTicks = 300_000_000
        #expect(initial != PlaybackPresentationIdentity(request: changed, sessionGeneration: lease))
        #expect(initial != PlaybackPresentationIdentity(request: initial.request, sessionGeneration: UUID()))
        #expect(initial == PlaybackPresentationIdentity(request: initial.request, sessionGeneration: lease))
    }

    @Test func repeatedRestartIssuesFreshCommandsWhileNormalOpenFocusesActiveWindow() throws {
        let requests = PlayerWindowRequests()
        var ref = ItemRef(item: MediaItem(id: "movie", type: .movie), serverID: "s", userID: "u")
        ref.playbackRequest = PlaybackRequest(item: ref.item, start: .fromBeginning)
        let window = requests.request(ref)
        let first = try #require(requests.requests[window])
        requests.activate(window)
        #expect(requests.request(ref) == window)
        let second = try #require(requests.requests[window])
        #expect(first.id != second.id)
        #expect(second.ref.resolvedPlaybackRequest.start == .fromBeginning)
        ref.playbackRequest = PlaybackRequest(item: ref.item)
        #expect(requests.request(ref) == window)
        #expect(requests.requests[window]?.id == second.id)
        requests.deactivate(window)
        #expect(requests.requests[window] == nil)
        _ = requests.request(ref)
        #expect(requests.requests[window]?.id != second.id)
    }
}
