import AVFoundation
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
    @Test(arguments: [false, true]) func cancelledInitialSeekPreservesPriorProgress(localOnly: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let scope = AccountScope(serverID: "seek-cancellation", userID: "user")
        let item = MediaItem(id: "movie", officialRating: "G", type: .movie, userData: MediaUserData(playbackPositionTicks: 10_000_000, isWatched: true))
        let fixture = try RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov")
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in item }
        provider.playbackHandler = { PlaybackSourceResolution(url: fixture, playSessionID: nil, mediaSourceID: nil, playMethod: .directPlay, stereoLayout: .none, stereoFallbackReason: nil) }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: StoredUser(id: scope.userID, name: "User", serverID: scope.serverID), server: ServerConnection(id: scope.serverID, name: "Server", url: url), mediaProvider: provider)
        let files = OfflineDownloadFileStore(directory: folder.appendingPathComponent("downloads"))
        if localOnly {
            let source = folder.appendingPathComponent("fixture.mov")
            try FileManager.default.copyItem(at: fixture, to: source)
            _ = try files.persistDownloadedFile(source, item: item, serverID: scope.serverID, userID: scope.userID)
        }
        let downloads = OfflineDownloadStore(fileStore: files, coordinator: PlaylistFixtureDownloadCoordinator())
        downloads.load(serverID: scope.serverID, userID: scope.userID)
        let progress = OfflinePlaybackProgressStore(directory: folder.appendingPathComponent("progress"))
        progress.checkpoint(itemID: "movie", positionTicks: 10_000_000, scope: scope, item: item)
        let previous = progress.pendingCheckpoints(scope: scope)
        var seek: CheckedContinuation<Void, Never>?
        let player = PlaybackStore(item: item, session: session, playbackRefresh: PlaybackRefreshStore(), downloads: downloads, localOnly: localOnly, localProgress: progress, initialSeek: { _, _ in await withCheckedContinuation { seek = $0 } })
        let preparation = Task { await player.prepare(startTimeTicks: 0) }
        // Offline preparation loads AVFoundation metadata asynchronously. A fixed
        // number of executor yields can expire before file I/O finishes on CI.
        let seekDeadline = ContinuousClock.now + .seconds(10)
        while seek == nil, ContinuousClock.now < seekDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(seek != nil)
        #expect(player.player != nil)
        preparation.cancel()
        player.teardown()
        seek?.resume()
        await preparation.value
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(progress.pendingCheckpoints(scope: scope) == previous)
        #expect(provider.playbackReportCallCount == 0)
        #expect(player.item.userData?.isWatched == true)
    }

    @Test func failedPlaylistRestartKeepsCursorAndRetryIntent() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let scope = AccountScope(serverID: "failed-playlist-restart", userID: "user")
        let id = UUID(), first = UUID(), later = UUID()
        let item = MediaItem(id: "movie", officialRating: "G", type: .movie)
        let native = ServerMediaList(id: id, name: "Duplicates", kind: .playlist, entries: [ServerMediaListEntry(id: first, item: item), ServerMediaListEntry(id: later, item: item)], canEdit: true, entriesLoaded: true)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.mediaListHandler = { _, _ in native }
        provider.itemHandler = { _ in item }
        provider.playbackHandler = { throw GusError.notFound }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: StoredUser(id: scope.userID, name: "User", serverID: scope.serverID), server: ServerConnection(id: scope.serverID, name: "Server", url: url), mediaProvider: provider)
        let lists = ServerMediaListsStore(directory: folder.appendingPathComponent("native"))
        await lists.refresh(id: id, kind: .playlist, session: session)
        let supplemental = VideoPlaylistsStore(directory: folder.appendingPathComponent("supplemental"), syncEnabled: false)
        supplemental.registerServerPlaylist(id: id, scope: scope)
        supplemental.setCursor(id: id, entryID: later, positionTicks: 50_000_000, finished: false, scope: scope)
        let old = supplemental.serverPlaylistState(id: id, scope: scope).cursor
        let downloads = OfflineDownloadStore(fileStore: OfflineDownloadFileStore(directory: folder.appendingPathComponent("downloads")), coordinator: PlaylistFixtureDownloadCoordinator())
        let player = PlaybackStore(item: item, session: session, playbackRefresh: PlaybackRefreshStore())
        let coordinator = VideoPlaylistPlaybackCoordinator(playlistID: id, entryID: first, fromBeginning: true, playlists: supplemental, session: session, downloads: downloads, serverLists: lists)
        await coordinator.start(player)
        #expect(supplemental.serverPlaylistState(id: id, scope: scope).cursor == old)
        await coordinator.retry(player)
        #expect(provider.playbackRequestedStartTicks == [0, 0])
        coordinator.stop(player)
        #expect(supplemental.serverPlaylistState(id: id, scope: scope).cursor == old)
    }

    @Test func mixedCachedPlaylistRejectsOrderedVideoBeforeProviderRequests() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let scope = AccountScope(serverID: "mixed-playlist-server", userID: "user")
        let id = UUID(), videoEntryID = UUID()
        let video = MediaItem(id: UUID().uuidString, name: "Movie", officialRating: "G", type: .movie)
        let audio = MediaItem(id: UUID().uuidString, name: "Song", officialRating: "G", type: .audio)
        let native = ServerMediaList(id: id, name: "Mixed queue", kind: .playlist, entries: [
            ServerMediaListEntry(id: videoEntryID, item: video),
            ServerMediaListEntry(id: UUID(), item: audio),
        ], canEdit: true, entriesLoaded: true)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.mediaListHandler = { _, _ in native }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: StoredUser(id: scope.userID, name: "User", serverID: scope.serverID), server: ServerConnection(id: scope.serverID, name: "Server", url: url), mediaProvider: provider)
        let directory = folder.appendingPathComponent("native")
        let initial = ServerMediaListsStore(directory: directory)
        await initial.refresh(id: id, kind: .playlist, session: session)
        let cached = ServerMediaListsStore(directory: directory)
        cached.load(scope: scope)
        var itemRequests = 0
        provider.itemHandler = { _ in itemRequests += 1; throw URLError(.notConnectedToInternet) }
        let supplemental = VideoPlaylistsStore(directory: folder.appendingPathComponent("supplemental"), syncEnabled: false)
        let downloads = OfflineDownloadStore(fileStore: OfflineDownloadFileStore(directory: folder.appendingPathComponent("downloads")), coordinator: PlaylistFixtureDownloadCoordinator())
        let player = PlaybackStore(item: video, session: session, playbackRefresh: PlaybackRefreshStore(), downloads: downloads)
        let coordinator = VideoPlaylistPlaybackCoordinator(playlistID: id, entryID: videoEntryID, fromBeginning: true, playlists: supplemental, session: session, downloads: downloads, serverLists: cached)
        defer { coordinator.stop(player) }
        await coordinator.start(player)
        #expect(coordinator.errorMessage == String(localized: "Play mixed media individually. Ordered video playback supports movies and episodes."))
        #expect(player.state == .idle)
        #expect(player.player == nil)
        #expect(itemRequests == 0)
        #expect(provider.playbackResolutionCallCount == 0)
        #expect(provider.playbackReportCallCount == 0)
        #expect(supplemental.serverPlaylistState(id: id, scope: scope).cursor == nil)
    }

    @Test func initialCursorSaveFailureStopsPreparationBeforeProviderRequests() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let scope = AccountScope(serverID: "playlist-save-failure-server", userID: "user")
        let id = UUID(), entryID = UUID()
        let item = MediaItem(id: UUID().uuidString, name: "Movie", officialRating: "G", type: .movie)
        let native = ServerMediaList(id: id, name: "Queue", kind: .playlist, entries: [ServerMediaListEntry(id: entryID, item: item)], canEdit: true, entriesLoaded: true)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.mediaListHandler = { _, _ in native }
        var itemRequests = 0
        provider.itemHandler = { _ in itemRequests += 1; throw URLError(.notConnectedToInternet) }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: StoredUser(id: scope.userID, name: "User", serverID: scope.serverID), server: ServerConnection(id: scope.serverID, name: "Server", url: url), mediaProvider: provider)
        let serverLists = ServerMediaListsStore(directory: folder.appendingPathComponent("native"))
        await serverLists.refresh(id: id, kind: .playlist, session: session)
        let directory = folder.appendingPathComponent("supplemental")
        let supplemental = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        #expect(supplemental.registerServerPlaylist(id: id, scope: scope))
        // A file replacing the storage directory makes the atomic cursor write fail.
        try FileManager.default.removeItem(at: directory)
        try Data("unwritable directory".utf8).write(to: directory)
        let downloads = OfflineDownloadStore(fileStore: OfflineDownloadFileStore(directory: folder.appendingPathComponent("downloads")), coordinator: PlaylistFixtureDownloadCoordinator())
        let player = PlaybackStore(item: item, session: session, playbackRefresh: PlaybackRefreshStore(), downloads: downloads)
        let coordinator = VideoPlaylistPlaybackCoordinator(playlistID: id, entryID: entryID, fromBeginning: true, playlists: supplemental, session: session, downloads: downloads, serverLists: serverLists)
        defer { coordinator.stop(player) }
        await coordinator.start(player)
        #expect(supplemental.errorMessage != nil)
        #expect(coordinator.errorMessage == supplemental.errorMessage)
        #expect(player.state == .idle)
        #expect(player.player == nil)
        #expect(itemRequests == 0)
        #expect(provider.playbackResolutionCallCount == 0)
        #expect(provider.playbackReportCallCount == 0)
        #expect(supplemental.serverPlaylistState(id: id, scope: scope).cursor == nil)
    }

    @Test func cachedNativePlaylistPlaysDownloadedVideoWithoutProviderRequests() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let scope = AccountScope(serverID: "native-offline-server", userID: "user")
        let mediaID = UUID(), playlistID = UUID()
        let item = MediaItem(id: ServerMediaListID.string(mediaID), name: "Downloaded movie", officialRating: "G", type: .movie)
        let entry = ServerMediaListEntry(id: mediaID, item: item)
        let native = ServerMediaList(id: playlistID, name: "Offline queue", kind: .playlist, entries: [entry], canEdit: true, entriesLoaded: true)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.mediaListHandler = { _, _ in native }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(
            client: JellyfinClientFactory.makeClient(url: url),
            user: StoredUser(id: scope.userID, name: "User", serverID: scope.serverID),
            server: ServerConnection(id: scope.serverID, name: "Server", url: url),
            mediaProvider: provider
        )
        let nativeDirectory = folder.appendingPathComponent("native")
        let initial = ServerMediaListsStore(directory: nativeDirectory)
        await initial.refresh(id: playlistID, kind: .playlist, session: session)

        let fileStore = OfflineDownloadFileStore(directory: folder.appendingPathComponent("downloads"))
        let source = folder.appendingPathComponent("offline-fixture.mov")
        let fixture = try RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov")
        try FileManager.default.copyItem(at: fixture, to: source)
        _ = try fileStore.persistDownloadedFile(source, item: item, serverID: scope.serverID, userID: scope.userID)
        let downloads = OfflineDownloadStore(fileStore: fileStore, coordinator: PlaylistFixtureDownloadCoordinator())
        downloads.load(serverID: scope.serverID, userID: scope.userID)
        let localURL = try #require(downloads.localFileURL(for: item, serverID: scope.serverID, userID: scope.userID))

        // Restart from durable native metadata with every provider endpoint offline.
        var remoteItemRequests = 0, remoteListRequests = 0
        provider.itemHandler = { _ in remoteItemRequests += 1; throw URLError(.notConnectedToInternet) }
        provider.mediaListsHandler = { _ in remoteListRequests += 1; throw URLError(.notConnectedToInternet) }
        provider.mediaListHandler = { _, _ in remoteListRequests += 1; throw URLError(.notConnectedToInternet) }
        provider.playbackHandler = { throw URLError(.notConnectedToInternet) }
        let cached = ServerMediaListsStore(directory: nativeDirectory)
        cached.load(scope: scope)
        let supplementalDirectory = folder.appendingPathComponent("supplemental")
        let supplemental = VideoPlaylistsStore(directory: supplementalDirectory, syncEnabled: false)
        let player = PlaybackStore(
            item: item,
            session: session,
            playbackRefresh: PlaybackRefreshStore(),
            downloads: downloads,
            localProgress: OfflinePlaybackProgressStore(directory: folder.appendingPathComponent("progress"))
        )
        let coordinator = VideoPlaylistPlaybackCoordinator(
            playlistID: playlistID,
            entryID: mediaID,
            fromBeginning: true,
            playlists: supplemental,
            session: session,
            downloads: downloads,
            serverLists: cached
        )
        defer { coordinator.stop(player) }
        await coordinator.start(player)
        #expect(coordinator.errorMessage == nil)
        #expect(player.state == .ready)
        let actualPlayer = try #require(player.player)
        actualPlayer.pause()
        let currentItem = try #require(actualPlayer.currentItem)
        let asset = try #require(currentItem.asset as? AVURLAsset)
        #expect(asset.url == localURL)
        #expect(try await asset.load(.isPlayable))
        for _ in 0 ..< 500 {
            if currentItem.status != .unknown {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(currentItem.status == .readyToPlay)
        await actualPlayer.seek(to: CMTime(seconds: 1, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        coordinator.checkpoint(player)
        let restored = VideoPlaylistsStore(directory: supplementalDirectory, syncEnabled: false)
        restored.load(scope: scope)
        let cursor = try #require(restored.serverPlaylistState(id: playlistID, scope: scope).cursor)
        #expect(cursor.entryID == mediaID)
        let ticks = try #require(cursor.positionTicks)
        #expect((9_900_000 ... 10_100_000).contains(ticks))
        #expect(!cursor.finished)
        coordinator.stop(player)
        await Task.yield()
        #expect(remoteItemRequests == 0)
        #expect(remoteListRequests == 0)
        #expect(provider.playbackResolutionCallCount == 0)
        #expect(provider.playbackReportCallCount == 0)
        #expect(provider.nextUpCallCount == 0)
        #expect(provider.artworkCallCount == 0)
    }

    @Test func removalWhileResolvingExposesRecovery() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let scope = AccountScope(serverID: "playlist-resolution-server", userID: "user")
        let playlists = VideoPlaylistsStore(directory: folder, syncEnabled: false)
        let id = UUID()
        let item = MediaItem(id: "removal-test-movie", name: "Movie", type: .movie)
        let entry = ServerMediaListEntry(id: UUID(), item: item)
        var nativeList = ServerMediaList(id: id, name: "Queue", kind: .playlist, entries: [entry], canEdit: true, entriesLoaded: true)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.mediaListHandler = { _, _ in nativeList }
        provider.removeFromMediaListHandler = { _, _, ids in nativeList.entries.removeAll { ids.contains($0.id) } }
        let serverLists = ServerMediaListsStore(directory: folder.appendingPathComponent("native"))
        var continuation: CheckedContinuation<MediaItem, Never>?
        provider.itemHandler = { _ in await withCheckedContinuation { continuation = $0 } }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: StoredUser(id: scope.userID, name: "User", serverID: scope.serverID), server: ServerConnection(id: scope.serverID, name: "Server", url: url), mediaProvider: provider)
        await serverLists.refresh(id: id, kind: .playlist, session: session)
        let player = PlaybackStore(item: item, session: session, playbackRefresh: PlaybackRefreshStore())
        let coordinator = VideoPlaylistPlaybackCoordinator(playlistID: id, entryID: entry.id, fromBeginning: true, playlists: playlists, session: session, downloads: .shared, serverLists: serverLists)
        let preparation = Task { await coordinator.start(player) }
        for _ in 0 ..< 1000 {
            if continuation != nil {
                break
            }; await Task.yield()
        }
        #expect(continuation != nil)
        _ = await serverLists.remove(entryID: entry.id, from: id, kind: .playlist, session: session)
        continuation?.resume(returning: item)
        await preparation.value
        #expect(coordinator.errorMessage != nil)
        #expect(player.state == .idle)
        #expect(provider.playbackResolutionCallCount == 0)
        coordinator.stop(player)
    }
}

private final class PlaylistFixtureDownloadCoordinator: DownloadSessionCoordinating {
    func setEventHandler(_ eventHandler: DownloadSessionCoordinatorEventHandler?) {}
    func startDownload(from url: URL, recordID: String) {}
    func resumeDownload(with resumeData: Data, recordID: String) {}
    func pause(recordID: String, completion: @escaping (Data?) -> Void) {
        completion(nil)
    }

    func cancel(recordID: String) {}
    func reconnectActiveTasks() {}
}
