import Foundation
@testable import Gus
import Testing

@Suite("Shortcut automation actions") @MainActor
struct AutomationActionsTests {
    @Test("Remote shortcuts require exactly one active session for a stable device")
    func distinctPlayers() {
        let sessions = [
            player(session: "session1", device: "a"), player(session: "session2", device: "b"),
            player(session: "session3", device: "a"), player(session: "session4", device: nil),
            player(session: "session5", device: ""),
        ]
        #expect(GusRemotePlayerQuery.distinctDevices(sessions).map(\.id) == ["session2"])
    }

    @Test("Shortcut outputs preserve unconfirmed, queued, and failed states")
    func outcomes() throws {
        #expect(try GusActionStatus(.accepted) == .accepted)
        #expect(try GusActionStatus(.confirmed) == .confirmed)
        #expect(try GusActionStatus(.uncertain) == .uncertain)
        #expect(try GusActionStatus(.queued) == .queued)
        #expect(throws: GusError.forbidden) { try GusActionStatus(.failed(.forbidden)) }
    }

    @Test("Concurrent invocations cannot send a second command to the same device")
    func concurrentCommand() async throws {
        let key = UUID().uuidString
        var innerSent = false
        try await GusAutomationWrite.perform(key: key) {
            do {
                try await GusAutomationWrite.perform(key: key) { innerSent = true }
                Issue.record("Conflicting command was accepted.")
            } catch {
                #expect(!innerSent)
            }
        }
        try await GusAutomationWrite.perform(key: key) { innerSent = true }
        #expect(innerSent)
    }

    @Test("DVR attempts survive relaunch, expire after airing and never cross accounts")
    func recordingJournal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = AccountScope(serverID: "server", userID: "user")
        let other = AccountScope(serverID: "server", userID: "other")
        let now = Date()
        let end = now.addingTimeInterval(900)
        try GusRecordingJournal(scope: account, directory: directory).set("guide-id", expires: end, now: now)
        let reopened = GusRecordingJournal(scope: account, directory: directory)
        #expect(try reopened.contains("guide-id", now: now))
        #expect(try !GusRecordingJournal(scope: other, directory: directory).contains("guide-id", now: now))
        #expect(try !reopened.contains("guide-id", now: end))
        try reopened.set("guide-id", expires: nil, now: now)
        #expect(try !reopened.contains("guide-id", now: now))
    }

    @Test("Chapter commands preserve one-based numbering and never seek beyond either end")
    func chapterSelection() {
        let targets = [
            PlaybackChapter(id: 0, title: "Opening", startPositionTicks: 0),
            PlaybackChapter(id: 1, title: "Middle", startPositionTicks: PlaybackTime.ticks(fromSeconds: 30)),
        ]
        #expect(GusChapterAction.numbered.target(in: targets, at: 2, number: 2)?.title == "Middle")
        #expect(GusChapterAction.numbered.target(in: targets, at: 2, number: 0) == nil)
        #expect(GusChapterAction.next.target(in: targets, at: 0, number: nil)?.title == "Middle")
        #expect(GusChapterAction.next.target(in: targets, at: 40, number: nil) == nil)
        #expect(GusChapterAction.previous.target(in: targets, at: 30, number: nil)?.title == "Opening")
    }

    @Test("Numbered chapters on a single cut retain their position even when titles repeat")
    func numberedChapterSource() throws {
        let item = MediaItem(
            chapters: [.init(name: "Scene", startPositionTicks: 0), .init(name: "Scene", startPositionTicks: 300)],
            id: "film", mediaSources: [.init(id: "primary")], type: .movie
        )
        let request = try PlayGusChapterIntent.request(for: item, number: 2)
        #expect(request.streamSelection.mediaSourceID == "primary")
        #expect(request.requestedStartTicks == 300)
        #expect(throws: GusError.notFound) { try PlayGusChapterIntent.request(for: item, number: 3) }
    }

    @Test("Chapter starts require a uniquely identified first cut")
    func unidentifiedChapterSource() {
        let sources: [[MediaSource]] = [
            [], [.init()], [.init(id: " ")], [.init(), .init(id: "alternate")], [.init(id: "same"), .init(id: "same")],
        ]
        for mediaSources in sources {
            let item = MediaItem(chapters: [.init(name: "Opening", startPositionTicks: 0)], id: "film", mediaSources: mediaSources, type: .movie)
            #expect(throws: GusError.notFound) { try PlayGusChapterIntent.request(for: item, number: 1) }
            #expect(throws: GusError.self) {
                try GusPlaybackChoices.request(item: item, version: nil, audio: nil, subtitle: nil, subtitlesOff: false, chapter: "Opening", startOver: false, position: nil)
            }
        }
    }

    @Test("An audiobook chapter skips a downloaded alternate and retains its source during a metadata refresh")
    func chapterWithAlternateDownload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let downloads = OfflineDownloadStore(fileStore: files, coordinator: FakeDownloadSessionCoordinator())
        let item = MediaItem(
            chapters: [.init(name: "Middle", startPositionTicks: 300)], id: "book",
            mediaSources: [.init(id: "original"), .init(id: "abridged")], officialRating: "G", type: .audioBook
        )
        let provider = FakeMediaProviderSession(capabilities: .init())
        let session = SessionStore.makeTestSession(mediaProvider: provider)
        let record = files.prepareDownloadRecord(
            item: item, serverID: session.server.id, userID: session.user.id, fileExtension: "m4a",
            status: .complete, progress: 1, mediaSourceID: "abridged"
        )
        try Data([1]).write(to: URL(fileURLWithPath: record.filePath))
        #expect(downloads.localFileURL(for: item, serverID: session.server.id, userID: session.user.id) != nil)
        var refreshed = item
        refreshed.mediaSources = []
        provider.itemHandler = { _ in refreshed }
        provider.audioHandler = { throw GusError.notFound }

        let request = try PlayGusChapterIntent.request(for: item, number: 1)
        let player = AudioPlayerStore(session: session, tracks: [item], request: request, downloads: downloads, activateAudioSession: { _ in })
        defer { player.teardown() }
        await player.start()
        #expect(provider.playbackRequestedSelections.map(\.mediaSourceID) == ["original"])
    }

    @Test("Changing an active audiobook or video cut retires the primary chapter timeline")
    func activeChapterEditionChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let progress = OfflinePlaybackProgressStore(directory: directory)
        let provider = FakeMediaProviderSession(capabilities: .init())
        let session = SessionStore.makeTestSession(mediaProvider: provider)
        let fixture = try RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov")
        let book = MediaItem(
            chapters: [.init(name: "Middle", startPositionTicks: PlaybackTime.ticks(fromSeconds: 2))], id: "chapter-book",
            mediaSources: [.init(id: "primary"), .init(id: "alternate")], officialRating: "G", type: .audioBook
        )
        var movie = book
        movie.id = "chapter-movie"
        movie.type = .movie
        provider.itemHandler = { $0 == movie.id ? movie : book }
        var resolution = PlaybackSourceResolution(url: fixture, playSessionID: nil, mediaSourceID: "primary", playMethod: .directPlay, stereoLayout: .none, stereoFallbackReason: nil, mediaSource: .init(id: "primary"))
        provider.audioHandler = { resolution }
        provider.playbackHandler = { resolution }

        let audio = AudioPlayerStore(session: session, tracks: [book], localProgress: progress, activateAudioSession: { _ in })
        defer { audio.teardown() }
        await audio.start()
        audio.playPause()
        let chapter = try #require(audio.chapterTargets.first)
        // Begin the native seek on the main actor, then replace its preparation before it can report success.
        let oldSeek = Task.immediate { await audio.seek(to: chapter) }
        resolution.mediaSourceID = "alternate"
        resolution.mediaSource = .init(id: "alternate")
        await audio.selectMediaSource(id: "alternate", fromBeginning: true)
        #expect(await oldSeek.value == false)
        #expect(audio.state == .loaded)
        #expect(audio.currentTrack?.mediaSources.first?.id == "alternate")
        #expect(audio.chapterTargets.isEmpty)
        #expect(await audio.seek(to: chapter) == false)
        // The requested primary ID is not sufficient without a negotiated identity.
        resolution.mediaSourceID = nil
        resolution.mediaSource = nil
        await audio.selectMediaSource(id: "primary", fromBeginning: true)
        #expect(audio.state == .loaded)
        #expect(audio.chapterTargets.isEmpty)

        resolution.mediaSource = .init(id: "primary")
        let video = PlaybackStore(request: PlaybackRequest(item: movie), session: session, playbackRefresh: PlaybackRefreshStore(), localProgress: progress, activateAudioSession: { _ in })
        defer { video.teardown() }
        video.setPresentationActive(false)
        await video.prepare()
        #expect(video.chapterTargets == [chapter])
        #expect(await video.seek(to: chapter))
        resolution.mediaSourceID = "alternate"
        resolution.mediaSource = .init(id: "alternate")
        await video.selectMediaSource(id: "alternate", fromBeginning: true)
        #expect(video.state == .ready)
        #expect(video.item.mediaSources.first?.id == "alternate")
        #expect(video.chapterTargets.isEmpty)
        #expect(await video.seek(to: chapter) == false)
    }

    @Test("Downloaded chapters require the recorded cut to own the original timeline")
    func downloadedChapterOwner() {
        let book = MediaItem(
            chapters: [.init(name: "Opening", startPositionTicks: 0)], id: "book",
            mediaSources: [.init(id: "primary"), .init(id: "alternate")], type: .audioBook
        )
        func chapters(_ item: MediaItem, savedSource: String?) -> [MediaChapterInfo] {
            OfflineDownloadRecord(id: "record", item: item, filePath: "", byteCount: 1, serverID: "server", userID: "user", downloadedAt: .now, mediaSourceID: savedSource).playbackItem.chapters
        }
        #expect(chapters(book, savedSource: "primary") == book.chapters)
        #expect(chapters(book, savedSource: "alternate").isEmpty)
        var single = book
        single.mediaSources = [.init(id: "primary")]
        #expect(chapters(single, savedSource: nil).isEmpty)
        #expect(chapters(single, savedSource: "unlisted").isEmpty)
        single.mediaSources = []
        #expect(chapters(single, savedSource: nil).isEmpty)
    }

    @Test("A saved slideshow directive never leaves the device through a playback URL")
    func slideshowSharing() {
        var request = PlaybackRequest(item: MediaItem(id: "photo", parentID: "album", type: .photo))
        request.slideshowAlbumID = "album"
        #expect(request.sharingIntent.slideshowAlbumID == nil)
    }

    @Test("A moved airing requires review even if the program identifier is unchanged")
    func changedGuideAiring() {
        let start = Date(), end = start.addingTimeInterval(900)
        let a = LiveTVGuideProgram(id: "program", channelID: "channel", channelName: nil, name: "Example", rating: nil, start: start, end: end, timerID: nil)
        let b = LiveTVGuideProgram(id: "program", channelID: "channel", channelName: nil, name: "Example", rating: nil, start: end, end: end.addingTimeInterval(900), timerID: nil)
        #expect(!a.isSameAiring(as: b))
    }

    private func player(session: String, device: String?) -> RemoteSession {
        RemoteSession(
            id: session,
            deviceID: device,
            deviceName: "Living Room",
            client: "Gus",
            userName: nil,
            nowPlaying: nil,
            positionTicks: nil,
            isPaused: false,
            volumeLevel: nil,
            isMuted: false,
            supportsMediaControl: true,
            canSeek: false,
            supportedCommands: [],
            playableMediaTypes: ["Audio"],
            mediaSourceID: nil,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
    }
}
