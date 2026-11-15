import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@Suite("Downloaded library")
struct DownloadedLibraryTests {
    @Test("download playback projects its recorded source and never guesses missing source metadata")
    func downloadedSourceProjection() {
        let sources = [MediaSource(id: "default", mediaStreams: [MediaStreamInfo(index: 2, language: "eng", type: .audio)], runTimeTicks: 10_000_000), MediaSource(id: "alternate", mediaStreams: [MediaStreamInfo(index: 9, language: "fra", type: .audio)], runTimeTicks: 40_000_000)]
        let item = MediaItem(id: "projection", mediaSources: sources, runTimeTicks: 10_000_000, type: .movie, userData: MediaUserData(playbackPositionTicks: 5_000_000))
        var downloaded = record(item)
        downloaded.mediaSourceID = "alternate"
        #expect(downloaded.playbackRequest.streamSelection.mediaSourceID == "alternate")
        #expect(downloaded.playbackItem.mediaSources.map(\.id) == ["alternate"])
        #expect(downloaded.playbackItem.runTimeTicks == 40_000_000)
        #expect(downloaded.playbackItem.userData?.playbackPositionTicks == nil)
        downloaded.mediaSourceID = "missing-source"
        #expect(downloaded.playbackRequest.streamSelection.mediaSourceID == "missing-source")
        #expect(downloaded.playbackItem.mediaSources.isEmpty)
        #expect(downloaded.playbackItem.runTimeTicks == nil)
        downloaded.mediaSourceID = nil
        #expect(downloaded.playbackRequest.streamSelection.mediaSourceID == nil)
        #expect(downloaded.playbackItem.mediaSources.isEmpty)
        #expect(downloaded.playbackItem.runTimeTicks == nil)
        #expect(downloaded.item.mediaSources == sources)
        #expect(downloaded.item.userData?.playbackPositionTicks == 5_000_000)
    }

    @Test("converted downloads never expose original track indexes or defaults as local choices")
    @MainActor
    func convertedDownloadCatalog() {
        let source = MediaSource(
            id: "alternate",
            mediaStreams: [MediaStreamInfo(index: 2, language: "eng", type: .audio), MediaStreamInfo(index: 9, language: "fra", type: .audio), MediaStreamInfo(index: 11, language: "eng", type: .subtitle)],
            defaultAudioStreamIndex: 2,
            defaultSubtitleStreamIndex: 11,
            runTimeTicks: 40_000_000
        )
        var downloaded = record(MediaItem(mediaSources: [source], runTimeTicks: 40_000_000))
        downloaded.mediaSourceID = "alternate"
        let explicitRequest = PlaybackRequest(item: downloaded.item, streamSelection: PlaybackStreamSelection(audioStreamIndex: 9, subtitleStreamIndex: 11, mediaSourceID: "alternate"))
        for operation in [DownloadActivity.SourceOperation.remuxed, .transcoded] {
            downloaded.activity = DownloadActivity(phase: .complete, sourceOperation: operation)
            let projected = downloaded.playbackItem.mediaSources.first
            #expect(downloaded.playbackRequest.streamSelection.mediaSourceID == "alternate")
            #expect(downloaded.playbackItem.runTimeTicks == 40_000_000)
            #expect(projected?.mediaStreams.isEmpty == true)
            #expect(projected?.defaultAudioStreamIndex == nil)
            #expect(projected?.defaultSubtitleStreamIndex == nil)
            #expect(downloaded.playbackSelection(for: explicitRequest).audioStreamIndex == nil)
            #expect(downloaded.playbackSelection(for: explicitRequest).subtitleStreamIndex == nil)
            #expect(PlaybackTrackMenuSelection.audio(for: explicitRequest, source: projected) == nil)
            #expect(PlaybackMediaSelectionMatcher.candidatePosition(forStreamIndex: 9, kind: .audio, streams: projected?.mediaStreams ?? [], candidates: [MediaSelectionCandidate(position: 0, languageTag: "fra")]) == nil)
        }
        downloaded.activity = DownloadActivity(phase: .complete, sourceOperation: .original)
        #expect(downloaded.playbackItem.mediaSources.first == source)
        #expect(downloaded.playbackSelection(for: explicitRequest).audioStreamIndex == 9)
        #expect(downloaded.playbackSelection(for: explicitRequest).subtitleStreamIndex == 11)
        #expect(downloaded.item.mediaSources.first == source)
    }

    private func record(_ item: MediaItem, status: DownloadStatus = .complete) -> OfflineDownloadRecord {
        OfflineDownloadRecord(
            id: item.id ?? "unknown",
            item: item,
            filePath: "file.mp4",
            byteCount: 1,
            serverID: "s",
            userID: "u",
            downloadedAt: Date(),
            status: status
        )
    }

    @Test("Only EPUB and PDF use in-app readers; other original formats use sharing")
    func originalBookFormats() {
        #expect(DownloadedBookFormat(fileExtension: "epub") == .epub)
        #expect(DownloadedBookFormat(fileExtension: "EPUB") == .epub)
        #expect(DownloadedBookFormat(fileExtension: "pdf") == .pdf)
        for fileExtension in ["mobi", "azw3", "cbz", "cbr", "", "unknown"] {
            #expect(DownloadedBookFormat(fileExtension: fileExtension) == .externalReader)
        }
    }

    @Test("Incomplete downloads and restricted items cannot enter the library")
    func excludesIncompleteAndRestricted() {
        let records = [
            record(MediaItem(id: "good", name: "Good", officialRating: "G", type: .movie)),
            record(MediaItem(id: "restricted", name: "Restricted", officialRating: "R", type: .movie)),
            record(MediaItem(id: "paused", name: "Paused", type: .movie), status: .paused),
            record(MediaItem(id: "queued", name: "Queued", type: .movie), status: .queued),
        ]
        let sections = DownloadedLibrary.sections(records: records, filter: .all, search: "") {
            ContentRatingGate.admits($0, limit: .general, hideUnrated: true)
        }
        #expect(sections.flatMap(\.records).map(\.id) == ["good"])
    }

    @Test("Episode grouping preserves series, orders seasons and sorts episode numbers numerically")
    func groupsEpisodes() {
        let records = [
            record(MediaItem(id: "e10", indexNumber: 10, name: "Episode ten", parentIndexNumber: 2, seriesID: "a", seriesName: "A", type: .episode)),
            record(MediaItem(id: "e2", indexNumber: 2, name: "Episode two", parentIndexNumber: 2, seriesID: "a", seriesName: "A", type: .episode)),
            record(MediaItem(id: "e1", indexNumber: 1, name: "First", parentIndexNumber: 1, seriesID: "a", seriesName: "A", type: .episode)),
            record(MediaItem(id: "other", indexNumber: 1, name: "Other", parentIndexNumber: 1, seriesID: "b", seriesName: "B", type: .episode)),
        ]
        let sections = DownloadedLibrary.sections(records: records, filter: .shows, search: "", admits: { _ in true })
        #expect(sections.count == 3)
        #expect(sections.map { $0.records.map(\.id) } == [["e1"], ["e2", "e10"], ["other"]])
        #expect(DownloadedLibrary.episodeLabel(records[1].item) == "S02 E02")
        #expect(DownloadedLibrary.sections(records: records, filter: .all, search: "S02 E02", admits: { _ in true }).flatMap(\.records).map(\.id) == ["e2"])
    }

    @Test("Local search matches series and artists, while filters distinguish media kinds")
    func searchesSavedMetadata() {
        let records = [
            record(MediaItem(artists: ["Pineapple"], id: "audio", name: "Song", type: .audio)),
            record(MediaItem(id: "episode", name: "Pilot", seriesName: "Psych", type: .episode)),
            record(MediaItem(id: "book", name: "Psych", type: .book)),
        ]
        #expect(DownloadedLibrary.sections(records: records, filter: .audio, search: "pineapple", admits: { _ in true }).flatMap(\.records).map(\.id) == ["audio"])
        #expect(DownloadedLibrary.sections(records: records, filter: .shows, search: "psych", admits: { _ in true }).flatMap(\.records).map(\.id) == ["episode"])
        #expect(DownloadedLibrary.sections(records: records, filter: .books, search: "Psych", admits: { _ in true }).flatMap(\.records).map(\.id) == ["book"])
    }

    @Test("Offline next episode requires the immediate downloaded episode in the same series")
    func localNextEpisode() {
        let current = MediaItem(id: "one", indexNumber: 1, parentIndexNumber: 1, seriesID: "show", type: .episode)
        let next = MediaItem(id: "two", indexNumber: 2, parentIndexNumber: 1, seriesID: "show", type: .episode)
        let gap = MediaItem(id: "three", indexNumber: 3, parentIndexNumber: 1, seriesID: "show", type: .episode)
        #expect(DownloadedLibrary.nextEpisode(after: current, records: [record(gap)]) == nil)
        #expect(DownloadedLibrary.nextEpisode(after: current, records: [record(next)])?.id == "two")
    }
}

@MainActor
@Suite("Offline playback progress")
struct OfflinePlaybackProgressTests {
    private let scope = AccountScope(serverID: "server", userID: "user")
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gus-offline-progress-\(UUID().uuidString)")
    }

    @Test("Newest positions survive process restoration and stay isolated per raw account identity")
    func persistenceAndScope() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OfflinePlaybackProgressStore(directory: directory)
        store.checkpoint(itemID: "movie", positionTicks: 100, scope: scope)
        store.checkpoint(itemID: "movie", positionTicks: 200, scope: scope)
        store.checkpoint(itemID: "movie", positionTicks: 300, scope: AccountScope(serverID: "server", userID: "other"))
        let restored = OfflinePlaybackProgressStore(directory: directory)
        #expect(restored.positionTicks(forItemID: "movie", scope: scope) == 200)
        #expect(restored.pendingCheckpoints(scope: scope).count == 1)
        #expect(restored.positionTicks(forItemID: "movie", scope: AccountScope(serverID: "server", userID: "other")) == 300)
        // Unlike sanitized filesystem keys, these raw account ids must not alias.
        store.checkpoint(itemID: "x", positionTicks: 1, scope: AccountScope(serverID: "a/b", userID: "u"))
        #expect(store.positionTicks(forItemID: "x", scope: AccountScope(serverID: "a_b", userID: "u")) == nil)
    }

    @Test("A successful sync clears only the exact uploaded version and keeps local resume")
    func replacementDuringUpload() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OfflinePlaybackProgressStore(directory: directory)
        store.checkpoint(itemID: "movie", positionTicks: 100, scope: scope)
        await store.sync(scope: scope, isCurrentScope: { true }) { entry in
            #expect(entry.positionTicks == 100)
            store.checkpoint(itemID: "movie", positionTicks: 200, scope: scope)
        }
        #expect(store.pendingCheckpoints(scope: scope).first?.positionTicks == 200)
        await store.sync(scope: scope, isCurrentScope: { true }) { entry in #expect(entry.positionTicks == 200) }
        #expect(store.pendingCheckpoints(scope: scope).isEmpty)
        #expect(store.positionTicks(forItemID: "movie", scope: scope) == 200)
    }

    @Test("Different cuts retain separate positions and only the latest cut uploads item progress")
    func sourceSpecificCheckpoints() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OfflinePlaybackProgressStore(directory: directory)
        store.checkpoint(itemID: "movie", positionTicks: 10, scope: scope)
        store.checkpoint(itemID: "movie", positionTicks: 100, scope: scope, mediaSourceID: "theatrical")
        store.checkpoint(itemID: "movie", positionTicks: 250, scope: scope, mediaSourceID: "extended")
        let restored = OfflinePlaybackProgressStore(directory: directory)
        #expect(restored.positionTicks(forItemID: "movie", scope: scope) == 10)
        #expect(restored.positionTicks(forItemID: "movie", scope: scope, mediaSourceID: "theatrical") == 100)
        #expect(restored.positionTicks(forItemID: "movie", scope: scope, mediaSourceID: "extended") == 250)
        #expect(restored.positionTicks(forItemID: "movie", scope: scope, mediaSourceID: "unknown") == nil)
        #expect(restored.pendingCheckpoints(scope: scope).map(\.mediaSourceID) == ["extended"])
        await restored.sync(scope: scope, isCurrentScope: { true }) { entry in
            #expect(entry.mediaSourceID == "extended")
            restored.checkpoint(itemID: "movie", positionTicks: 125, scope: scope, mediaSourceID: "theatrical")
        }
        #expect(restored.pendingCheckpoints(scope: scope).map(\.mediaSourceID) == ["theatrical"])
        restored.resetCheckpoint(itemID: "movie", scope: scope)
        #expect(restored.positionTicks(forItemID: "movie", scope: scope, mediaSourceID: "extended") == 0)
        #expect(restored.positionTicks(forItemID: "movie", scope: scope, mediaSourceID: "theatrical") == 0)
        #expect(restored.pendingCheckpoints(scope: scope).isEmpty)
    }

    @Test("Purging an account rejects writes from existing players but admits a new writer")
    func purgeInvalidatesWriters() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OfflinePlaybackProgressStore(directory: directory)
        let oldToken = store.writerToken(for: scope)
        store.checkpoint(itemID: "movie", positionTicks: 100, scope: scope, writerToken: oldToken)
        store.deleteCheckpoints(scope: scope)
        store.checkpoint(itemID: "movie", positionTicks: 200, scope: scope, writerToken: oldToken)
        #expect(store.positionTicks(forItemID: "movie", scope: scope) == nil)
        let newToken = store.writerToken(for: scope)
        #expect(newToken != oldToken)
        store.checkpoint(itemID: "movie", positionTicks: 300, scope: scope, writerToken: newToken)
        #expect(store.positionTicks(forItemID: "movie", scope: scope) == 300)
    }

    @Test("Failures and account changes keep checkpoints pending")
    func retryAndAccountSwitch() async {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OfflinePlaybackProgressStore(directory: directory)
        store.checkpoint(itemID: "a", positionTicks: 100, scope: scope)
        store.checkpoint(itemID: "b", positionTicks: 200, scope: scope)
        var attempts = 0
        await store.sync(scope: scope, isCurrentScope: { true }) { _ in
            attempts += 1
            throw GusError.offline
        }
        #expect(attempts == 1)
        #expect(store.pendingCheckpoints(scope: scope).count == 2)
        var current = true
        await store.sync(scope: scope, isCurrentScope: { current }) { _ in current = false }
        #expect(store.pendingCheckpoints(scope: scope).count == 2)
        await store.sync(scope: scope, isCurrentScope: { false }) { _ in Issue.record("Inactive account must never upload") }
    }
}

@MainActor
@Suite("Downloaded navigation")
struct DownloadedNavigationTests {
    @Test("Scoped player refs distinguish accounts and retain local-only intent through Codable")
    func scopedPlayerRef() throws {
        let item = MediaItem(id: "same-id", type: .movie)
        let a = ItemRef(item: item, localOnly: true, serverID: "s", userID: "a")
        let b = ItemRef(item: item, localOnly: true, serverID: "s", userID: "b")
        #expect(a != b)
        #expect(Set([a, b]).count == 2)
        let restored = try JSONDecoder().decode(ItemRef.self, from: JSONEncoder().encode(a))
        #expect(restored == a)
        let decoded = try JSONDecoder().decode(ItemRef.self, from: JSONEncoder().encode(ItemRef(item: item)))
        #expect(decoded.localOnly == nil)
    }

    @Test("Downloaded defaults after Home on supported platforms, can move and cannot hide")
    func requiredDestination() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gus-downloaded-nav-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NavigationPreferencesStore(directory: directory)
        let sections = store.visibleSections(libraries: [], serverID: "s", userID: "u")
        if DownloadsAvailability.isSupported {
            #expect(sections[1].id == "downloaded")
            #expect(sections[1].canMove)
            #expect(!sections[1].canHide)
            store.setVisibility(false, forSectionID: "downloaded", libraries: [], serverID: "s", userID: "u")
            store.move(sectionID: "downloaded", by: 1, libraries: [], serverID: "s", userID: "u")
            #expect(store.visibleSections(libraries: [], serverID: "s", userID: "u").filter { $0.id != "playlists" }.map(\.id) == ["home", "libraries", "downloaded", "discover", "settings"])
        } else {
            #expect(!sections.contains { $0.id == "downloaded" })
        }
        #expect(try AppRoute(url: #require(URL(string: "gus://downloaded"))) == .downloaded)
    }
}

extension PlaybackIntegrationTests {
    @MainActor
    @Suite("Local playback routing")
    struct LocalPlaybackRoutingTests {
        @Test("alternate downloaded video and audio retain source duration, catalogs and source checkpoint")
        func alternateDownloadedSourcePlayback() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gus-local-source-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let fileStore = OfflineDownloadFileStore(directory: directory)
            let sources = [MediaSource(id: "default", mediaStreams: [MediaStreamInfo(index: 2, language: "eng", type: .audio)], runTimeTicks: 10_000_000), MediaSource(id: "alternate", mediaStreams: [MediaStreamInfo(index: 9, language: "fra", type: .audio)], runTimeTicks: 40_000_000)]
            let movie = MediaItem(id: "alternate-video", mediaSources: sources, officialRating: "G", runTimeTicks: 10_000_000, type: .movie)
            let song = MediaItem(id: "alternate-audio", mediaSources: sources, officialRating: "G", runTimeTicks: 10_000_000, type: .audio)
            for item in [movie, song] {
                let source = directory.appendingPathComponent("\(item.id!).mov")
                try FileManager.default.copyItem(at: RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov"), to: source)
                _ = try fileStore.persistDownloadedFile(source, item: item, serverID: "s", userID: "u", fileExtension: "mov", mediaSourceID: "alternate")
            }
            let downloads = OfflineDownloadStore(fileStore: fileStore, coordinator: LocalRoutingDownloadCoordinator())
            downloads.load(serverID: "s", userID: "u")
            let progress = OfflinePlaybackProgressStore(directory: directory.appendingPathComponent("progress"))
            let scope = AccountScope(serverID: "s", userID: "u")
            for item in [movie, song] {
                try progress.checkpoint(itemID: #require(item.id), positionTicks: 20_000_000, scope: scope, mediaSourceID: "alternate")
            }
            let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
            let session = makeSession(provider: provider)
            var videoSeek: Int?
            // Intentionally use an item-only caller too: the local resolver must
            // recover B before clamping its2s checkpoint against default A's1s.
            let video = PlaybackStore(request: PlaybackRequest(item: movie), session: session, playbackRefresh: PlaybackRefreshStore(), downloads: downloads, localOnly: true, localProgress: progress, initialSeek: { _, ticks in videoSeek = ticks })
            defer { video.teardown() }
            video.setPresentationActive(false)
            await video.prepare()
            #expect(video.state == .ready)
            #expect(videoSeek == 20_000_000)
            #expect(video.request.streamSelection.mediaSourceID == "alternate")
            #expect(video.item.runTimeTicks == 40_000_000)
            #expect(video.audioOptions.map(\.id) == [9])
            let audio = AudioPlayerStore(session: session, tracks: [song], downloads: downloads, localOnly: true, localProgress: progress)
            defer { audio.teardown() }
            await audio.start()
            #expect(audio.state == .loaded)
            #expect(audio.request?.streamSelection.mediaSourceID == "alternate")
            #expect(audio.duration == 4)
            #expect(audio.currentTime >= 2)
            #expect(audio.audioOptions.map(\.id) == [9])
            #expect(provider.playbackResolutionCallCount == 0)
            #expect(provider.audioResolutionCallCount == 0)
            #expect(try fileStore.record(forItemID: #require(movie.id), serverID: "s", userID: "u")?.item.mediaSources.map(\.id) == ["default", "alternate"])
        }

        @Test("Missing local-only files fail without resolving a server URL")
        func missingFileNeverStreams() async {
            let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
            let session = makeSession(provider: provider)
            let video = PlaybackStore(
                request: PlaybackRequest(item: MediaItem(id: "missing-video", type: .movie)),
                session: session,
                playbackRefresh: PlaybackRefreshStore(),
                localOnly: true
            )
            await video.prepare()
            if case .failed = video.state {} else {
                Issue.record("Missing file must fail")
            }
            let audio = AudioPlayerStore(session: session, tracks: [MediaItem(id: "missing-audio", type: .audio)], localOnly: true)
            await audio.start()
            if case .failed = audio.state {} else {
                Issue.record("Missing file must fail")
            }
            #expect(provider.playbackResolutionCallCount == 0)
            #expect(provider.audioResolutionCallCount == 0)
            #expect(provider.playbackReportCallCount == 0)
            video.teardown()
            audio.teardown()
        }

        @Test("Local prepare and teardown do not resolve, fetch next-up, request artwork or report sessions")
        func localPlaybackDoesNotUseServer() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gus-local-player-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let fileStore = OfflineDownloadFileStore(directory: directory)
            let item = MediaItem(id: "local", indexNumber: 1, name: "Local episode", officialRating: "G", parentIndexNumber: 1, seriesID: "show", type: .episode)
            let source = directory.appendingPathComponent("source.mov")
            try FileManager.default.copyItem(at: RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov"), to: source)
            _ = try fileStore.persistDownloadedFile(source, item: item, serverID: "s", userID: "u", fileExtension: "mov")
            let downloads = OfflineDownloadStore(fileStore: fileStore, coordinator: LocalRoutingDownloadCoordinator())
            downloads.load(serverID: "s", userID: "u")
            let progress = OfflinePlaybackProgressStore(directory: directory)
            let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
            let store = PlaybackStore(
                request: PlaybackRequest(item: item),
                session: makeSession(provider: provider),
                playbackRefresh: PlaybackRefreshStore(),
                downloads: downloads,
                localOnly: true,
                localProgress: progress
            )
            await store.prepare()
            // Native readiness must precede success; a real renderer start owns progress.
            let deadline = ContinuousClock.now + .seconds(45)
            while !store.hasStartedPlayback, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(store.hasStartedPlayback)
            #expect(store.player != nil)
            #expect(provider.playbackResolutionCallCount == 0)
            #expect(provider.nextUpCallCount == 0)
            #expect(provider.artworkCallCount == 0)
            let scope = AccountScope(serverID: "s", userID: "u")
            #expect(progress.positionTicks(forItemID: "local", scope: scope) != nil)
            // Explicit sign-out purges before SwiftUI dismisses the old player.
            progress.deleteCheckpoints(scope: scope)
            store.teardown()
            await Task.yield()
            #expect(provider.playbackReportCallCount == 0)
            #expect(progress.positionTicks(forItemID: "local", scope: scope) == nil)
        }

        private func makeSession(provider: any MediaProviderSession) -> SessionStore {
            SessionStore(
                client: JellyfinClient(configuration: .init(
                    url: URL(string: "https://example.invalid")!,
                    accessToken: "test",
                    client: "GusTests",
                    deviceName: "Tests",
                    deviceID: "test",
                    version: "1"
                )),
                user: StoredUser(id: "u", name: "User", serverID: "s"),
                server: ServerConnection(id: "s", name: "Server", url: URL(string: "https://example.invalid")!),
                mediaProvider: provider
            )
        }
    }
}

private final class LocalRoutingDownloadCoordinator: DownloadSessionCoordinating {
    func setEventHandler(_ eventHandler: DownloadSessionCoordinatorEventHandler?) {}
    func startDownload(from url: URL, recordID: String) {}
    func resumeDownload(with resumeData: Data, recordID: String) {}
    func pause(recordID: String, completion: @escaping (Data?) -> Void) {
        completion(nil)
    }

    func cancel(recordID: String) {}
    func reconnectActiveTasks() {}
}

@MainActor
@Suite("Offline PDF page resume")
struct OfflinePDFPageResumeTests {
    @Test("Page locators round-trip and clamp after a document changes")
    func pagePosition() {
        let position = OfflinePDFPagePosition(pdfPage: 12)
        #expect(OfflinePDFPagePosition.decode(position.json) == position)
        #expect(position.boundedPage(pageCount: 5) == 4)
        #expect(position.boundedPage(pageCount: 0) == 0)
        #expect(OfflinePDFPagePosition(pdfPage: -1).boundedPage(pageCount: 5) == 0)
        #expect(OfflinePDFPagePosition.decode("{\"href\":\"chapter.xhtml\"}") == nil)
    }

    @Test("PDF page locators remain separate across users")
    func scopedLocator() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gus-pdf-resume-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BookProgressStore(directory: directory)
        let scope = AccountScope(serverID: "s", userID: "a")
        try store.save(locatorJSON: #require(OfflinePDFPagePosition(pdfPage: 3).json), forItemID: "book", scope: scope)
        store.flush()
        let restored = BookProgressStore(directory: directory)
        #expect(OfflinePDFPagePosition.decode(restored.locatorJSON(forItemID: "book", scope: scope))?.pdfPage == 3)
        #expect(restored.locatorJSON(forItemID: "book", scope: AccountScope(serverID: "s", userID: "b")) == nil)
    }
}
