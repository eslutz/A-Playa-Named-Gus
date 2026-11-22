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
    func convertedDownloadCatalog() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = PlaybackTrackMemory(defaults: defaults)
        let scope = AccountScope(serverID: "s", userID: "u")
        let source = MediaSource(
            id: "alternate",
            mediaStreams: [MediaStreamInfo(index: 2, language: "eng", type: .audio), MediaStreamInfo(index: 9, language: "fra", type: .audio), MediaStreamInfo(index: 11, language: "eng", type: .subtitle)],
            defaultAudioStreamIndex: 2,
            defaultSubtitleStreamIndex: 11,
            runTimeTicks: 40_000_000
        )
        var downloaded = record(MediaItem(id: "second", mediaSources: [source], runTimeTicks: 40_000_000, seriesID: "series", type: .episode))
        downloaded.mediaSourceID = "alternate"
        memory.setEnabled(true, scope: scope)
        memory.remember(item: MediaItem(id: "first", seriesID: "series", type: .episode), source: source, selection: .init(audioStreamIndex: 9, subtitleStreamIndex: 11), scope: scope)
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
            let request = downloaded.playbackRequest
            let tracks = memory.resolve(request: request, item: request.item, source: projected, baseSelection: downloaded.playbackSelection(for: request), scope: scope)
            #expect(tracks.selection.audioStreamIndex == nil)
            #expect(tracks.selection.subtitleStreamIndex == nil)
            #expect(tracks.selection.mediaSourceID == "alternate")
            #expect(tracks.hasUnavailableSelection)
        }
        downloaded.activity = DownloadActivity(phase: .complete, sourceOperation: .original)
        #expect(downloaded.playbackItem.mediaSources.first == source)
        #expect(downloaded.playbackSelection(for: explicitRequest).audioStreamIndex == 9)
        #expect(downloaded.playbackSelection(for: explicitRequest).subtitleStreamIndex == 11)
        #expect(downloaded.item.mediaSources.first == source)
        for sourceID in ["missing-source", nil] {
            downloaded.mediaSourceID = sourceID
            let unknown = downloaded.playbackRequest
            let unknownTracks = memory.resolve(request: unknown, item: unknown.item, source: unknown.item.mediaSources.first, baseSelection: downloaded.playbackSelection(for: unknown), scope: scope)
            #expect(unknown.item.mediaSources.isEmpty)
            #expect(unknownTracks.selection.audioStreamIndex == nil)
            #expect(unknownTracks.selection.subtitleStreamIndex == nil)
            #expect(unknownTracks.selection.mediaSourceID == sourceID)
            #expect(unknownTracks.hasUnavailableSelection)
        }
    }

    @Test("original downloads expose embedded tracks, not external sidecars or their defaults")
    @MainActor
    func originalDownloadTrackAvailability() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = PlaybackTrackMemory(defaults: defaults)
        let scope = AccountScope(serverID: "s", userID: "u")
        let source = MediaSource(
            id: "source",
            mediaStreams: [
                MediaStreamInfo(index: 0, language: "eng", title: "External SDH", type: .subtitle, isHearingImpaired: true, isExternal: true),
                MediaStreamInfo(index: 3, language: "eng", title: "Main", type: .audio),
                MediaStreamInfo(index: 5, language: "eng", title: "Embedded SDH", type: .subtitle, isHearingImpaired: true),
                MediaStreamInfo(index: 10, language: "eng", title: "Commentary", type: .audio, isExternal: true),
            ],
            defaultAudioStreamIndex: 10,
            defaultSubtitleStreamIndex: 0,
            runTimeTicks: 450_000_000
        )
        let previous = MediaItem(id: "first", seriesID: "series", type: .episode)
        var downloaded = record(MediaItem(id: "second", mediaSources: [source], seriesID: "series", type: .episode))
        downloaded.mediaSourceID = "source"
        downloaded.activity = DownloadActivity(phase: .complete, sourceOperation: .original)
        let request = downloaded.playbackRequest
        let projected = try #require(request.item.mediaSources.first)
        #expect(projected.mediaStreams.compactMap(\.index) == [3, 5])
        #expect(projected.defaultAudioStreamIndex == nil)
        #expect(projected.defaultSubtitleStreamIndex == nil)
        #expect(request.item.runTimeTicks == 450_000_000)
        #expect(request.streamSelection.mediaSourceID == "source")
        #expect(downloaded.item.mediaSources.first == source)
        memory.setEnabled(true, scope: scope)
        memory.remember(item: previous, source: source, selection: .init(audioStreamIndex: 10, subtitleStreamIndex: 0), scope: scope)
        let missing = memory.resolve(request: request, item: request.item, source: projected, baseSelection: downloaded.playbackSelection(for: request), scope: scope)
        #expect(missing.selection.audioStreamIndex == nil)
        #expect(missing.selection.subtitleStreamIndex == nil)
        #expect(missing.hasUnavailableSelection)
        memory.remember(item: previous, source: source, selection: .init(audioStreamIndex: 3, subtitleStreamIndex: 5), scope: scope)
        let embedded = memory.resolve(request: request, item: request.item, source: projected, baseSelection: downloaded.playbackSelection(for: request), scope: scope)
        #expect(embedded.selection.audioStreamIndex == 3)
        #expect(embedded.selection.subtitleStreamIndex == 5)
        #expect(!embedded.hasUnavailableSelection)
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

    @Test("A newer restricted server rating also hides a previously downloaded title")
    func updatedDownloadRating() {
        var cached = record(MediaItem(id: "movie", officialRating: "PG", type: .movie))
        let policy = ContentRatingGate.Policy(manual: .off, hideUnrated: false, ageCeiling: .teen)
        #expect(cached.isAdmitted(by: policy.admits))
        cached.remoteReference = MediaReference(
            item: MediaItem(id: "movie", officialRating: "GB-18", type: .movie),
            scope: AccountScope(serverID: "s", userID: "u")
        )
        #expect(!cached.isAdmitted(by: policy.admits))
        #expect(DownloadedLibrary.sections(records: [cached], filter: .all, search: "", admits: policy.admits).isEmpty)
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
        @Test("Shortcuts uses the downloaded cut’s duration and honors completion for online and offline lookups")
        func shortcutCompletionPercentage() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let files = OfflineDownloadFileStore(directory: directory)
            let progress = OfflinePlaybackProgressStore(directory: directory)
            let downloads = OfflineDownloadStore(fileStore: files, coordinator: LocalRoutingDownloadCoordinator())
            let session = makeSession(provider: FakeMediaProviderSession(capabilities: ProviderCapabilities()))
            let scope = session.references.scope
            let primary = MediaSource(id: "primary", runTimeTicks: 50)
            let source = MediaSource(id: "downloaded", runTimeTicks: 100)
            let untimed = MediaSource(id: "untimed")
            func save(_ id: String, watched: Bool, sourceID: String?) throws -> OfflineDownloadRecord {
                let item = MediaItem(
                    id: id,
                    mediaSources: [primary, source, untimed],
                    officialRating: "G",
                    runTimeTicks: primary.runTimeTicks,
                    type: .movie,
                    userData: MediaUserData(playedPercentage: 25, isWatched: watched)
                )
                let file = directory.appendingPathComponent("\(id).mov")
                try Data([0]).write(to: file)
                return try files.persistDownloadedFile(
                    file,
                    item: item,
                    serverID: scope.serverID,
                    userID: scope.userID,
                    fileExtension: "mov",
                    mediaSourceID: sourceID
                )
            }
            let finished = try save("finished", watched: true, sourceID: source.id)
            let unwatched = try save("unwatched", watched: false, sourceID: source.id)
            let unknownDuration = try save("unknown-duration", watched: false, sourceID: untimed.id)
            let legacy = try save("legacy", watched: false, sourceID: nil)
            let legacyFinished = try save("legacy-finished", watched: true, sourceID: nil)
            downloads.load(serverID: scope.serverID, userID: scope.userID)
            func percentage(_ item: MediaItem) -> Double {
                GetGusProgressIntent.playbackPercentage(for: item, session: session, progress: progress, downloads: downloads)
            }

            #expect(percentage(finished.playbackItem) == 100)
            progress.checkpoint(itemID: "finished", positionTicks: 0, scope: scope, mediaSourceID: source.id)
            #expect(percentage(finished.playbackItem) == 100)
            progress.checkpoint(itemID: "finished", positionTicks: 40, scope: scope, mediaSourceID: source.id)
            #expect(percentage(finished.playbackItem) == 100)
            #expect(percentage(finished.item) == 100)
            #expect(percentage(unwatched.playbackItem) == 0)
            progress.checkpoint(itemID: "unwatched", positionTicks: 40, scope: scope, mediaSourceID: source.id)
            #expect(percentage(unwatched.playbackItem) == 40)
            // Online resolution returns the full item, whose primary duration would give 80%.
            #expect(percentage(unwatched.item) == 40)
            var revised = unwatched.item
            revised.mediaSources[1].runTimeTicks = 160
            #expect(percentage(revised) == 40)

            // A duration the server later adds cannot establish the length of the file already on disk.
            progress.checkpoint(itemID: "unknown-duration", positionTicks: 40, scope: scope, mediaSourceID: untimed.id)
            var newlyTimed = unknownDuration.item
            newlyTimed.mediaSources[2].runTimeTicks = 200
            #expect(percentage(unknownDuration.playbackItem) == 25)
            #expect(percentage(newlyTimed) == 25)

            // Older downloads have no source runtime, so their saved percentage is the fallback.
            progress.checkpoint(itemID: "legacy", positionTicks: 40, scope: scope)
            #expect(legacy.playbackItem.runTimeTicks == nil)
            #expect(percentage(legacy.playbackItem) == 25)
            #expect(percentage(legacy.item) == 25)
            #expect(percentage(legacyFinished.playbackItem) == 100)
            #expect(percentage(legacyFinished.item) == 100)
        }

        @Test("local direct, next and playlist preparation rematch opted-in episode tracks", arguments: ["direct", "next", "playlist"])
        func downloadedEpisodeTrackMemory(entry: String) async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gus-local-tracks-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let scope = AccountScope(serverID: "local-tracks-\(UUID().uuidString)", userID: "user")
            let seriesID = UUID().uuidString
            let firstSource = MediaSource(id: "first-source", mediaStreams: [
                MediaStreamInfo(index: 3, language: "eng", title: "Main", type: .audio),
                MediaStreamInfo(index: 4, language: "eng", title: "Commentary", type: .audio),
                MediaStreamInfo(index: 7, language: "eng", title: "SDH", type: .subtitle, isHearingImpaired: true),
            ])
            let secondSource = MediaSource(id: "second-source", mediaStreams: [
                MediaStreamInfo(index: 3, language: "eng", title: "Commentary", type: .audio),
                MediaStreamInfo(index: 4, language: "eng", title: "Main", type: .audio),
                MediaStreamInfo(index: 5, language: "eng", title: "SDH", type: .subtitle, isHearingImpaired: true),
            ])
            let first = MediaItem(id: "first", indexNumber: 1, mediaSources: [firstSource], officialRating: "G", parentIndexNumber: 1, seriesID: seriesID, type: .episode)
            let second = MediaItem(id: "second", indexNumber: 2, mediaSources: [secondSource], officialRating: "G", parentIndexNumber: 1, seriesID: seriesID, type: .episode)
            let files = OfflineDownloadFileStore(directory: directory)
            var records: [OfflineDownloadRecord] = []
            for item in [first, second] {
                let sourceFile = directory.appendingPathComponent("\(item.id!).mov")
                try FileManager.default.copyItem(at: RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov"), to: sourceFile)
                try records.append(files.persistDownloadedFile(sourceFile, item: item, serverID: scope.serverID, userID: scope.userID, fileExtension: "mov", mediaSourceID: item.mediaSources.first?.id, activity: DownloadActivity(phase: .complete, sourceOperation: .original)))
            }
            let downloads = OfflineDownloadStore(fileStore: files, coordinator: LocalRoutingDownloadCoordinator())
            downloads.load(serverID: scope.serverID, userID: scope.userID)
            PlaybackTrackMemory.shared.setEnabled(true, scope: scope)
            defer { PlaybackTrackMemory.shared.setEnabled(false, scope: scope) }
            PlaybackTrackMemory.shared.remember(item: first, source: firstSource, selection: .init(audioStreamIndex: 4, subtitleStreamIndex: 7), scope: scope)
            let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
            let probe = LocalTrackPreparationProbe()
            let initial = entry == "direct" ? records[1].playbackRequest : records[0].playbackRequest
            let store = PlaybackStore(request: initial, session: makeSession(provider: provider, scope: scope), playbackRefresh: PlaybackRefreshStore(), downloads: downloads, localOnly: true, localProgress: OfflinePlaybackProgressStore(directory: directory.appendingPathComponent("progress")), initialSeek: { _, _ in
                if let owner = probe.store {
                    probe.record(owner)
                }
            })
            probe.store = store
            defer { store.teardown() }
            store.setPresentationActive(false)
            await store.prepare(startTimeTicks: 0)
            if entry == "next" {
                #expect(store.nextUpItem?.id == second.id)
                await store.playNextUp()
            } else if entry == "playlist" {
                await store.playPlaylistItem(second, startTimeTicks: 0)
            }
            #expect(store.state == .ready)
            let observed = try #require(probe.observations.last)
            #expect(observed.itemID == second.id)
            #expect(observed.sourceID == "second-source")
            #expect(observed.audioIndex == 3)
            #expect(observed.subtitleIndex == 5)
            #expect(!observed.hasNotice)
            #expect(store.request.audioTrack == nil)
            #expect(store.request.subtitleIntent == .automatic)
            #expect(store.audioMenuSelection == .automatic)
            #expect(store.subtitleMenuSelection == .automatic)
            #expect(provider.playbackResolutionCallCount == 0)
            #expect(provider.nextUpCallCount == 0)
            #expect(provider.artworkCallCount == 0)
            #expect(provider.playbackReportCallCount == 0)
        }

        /// The fixture drives real local preparation; this records the policy passed
        /// into native finishing, not a synthetic claim about AVMediaSelection output.
        @MainActor private final class LocalTrackPreparationProbe {
            struct Observation {
                let itemID: String?
                let sourceID: String?
                let audioIndex: Int?
                let subtitleIndex: Int?
                let hasNotice: Bool
            }

            weak var store: PlaybackStore?
            var observations: [Observation] = []

            func record(_ store: PlaybackStore) {
                observations.append(Observation(itemID: store.item.id, sourceID: store.selectedMediaSourceID, audioIndex: store.selectedAudioStreamIndex, subtitleIndex: store.selectedSubtitleStreamIndex, hasNotice: store.trackSelectionNotice != nil))
            }
        }

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
            #expect(PlaybackChoicePosition.ticks(for: PlaybackRequest(item: movie), session: session, progress: progress, downloads: downloads) == 20_000_000)
            #expect(PlaybackChoicePosition.ticks(for: PlaybackRequest(item: song), session: session, progress: progress, downloads: downloads) == 20_000_000)
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

        private func makeSession(provider: any MediaProviderSession, scope: AccountScope = AccountScope(serverID: "s", userID: "u")) -> SessionStore {
            SessionStore(
                client: JellyfinClient(configuration: .init(
                    url: URL(string: "https://example.invalid")!,
                    accessToken: "test",
                    client: "GusTests",
                    deviceName: "Tests",
                    deviceID: "test",
                    version: "1"
                )),
                user: StoredUser(id: scope.userID, name: "User", serverID: scope.serverID),
                server: ServerConnection(id: scope.serverID, name: "Server", url: URL(string: "https://example.invalid")!),
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
