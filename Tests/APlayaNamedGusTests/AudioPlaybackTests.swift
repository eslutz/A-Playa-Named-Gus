import AVFoundation
import Foundation
@testable import Gus
import JellyfinAPI
import MediaPlayer
import Testing

@Suite("Audio playback")
struct AudioPlaybackTests {
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    private static func tracks(_ count: Int) -> [MediaItem] {
        (0 ..< count).map { MediaItem(id: "track-\($0)", name: "Track \($0)", type: .audio) }
    }

    @Test("queue advances forward and stops at the end without repeat")
    func queueAdvancesAndStops() {
        var queue = AudioQueue(tracks: Self.tracks(3))

        #expect(queue.currentTrack?.id == "track-0")
        #expect(queue.advance(automatic: true)?.id == "track-1")
        #expect(queue.advance(automatic: true)?.id == "track-2")
        #expect(queue.advance(automatic: true) == nil)
    }

    @Test("repeat one loops on automatic completion but not on user skip")
    func repeatOneLoopsOnlyAutomatically() {
        var queue = AudioQueue(tracks: Self.tracks(3))
        queue.repeatMode = .one

        #expect(queue.advance(automatic: true)?.id == "track-0")
        #expect(queue.advance(automatic: false)?.id == "track-1")
        #expect(queue.advance(automatic: true)?.id == "track-1")
    }

    @Test("repeat all wraps to the first track")
    func repeatAllWraps() {
        var queue = AudioQueue(tracks: Self.tracks(2), startIndex: 1)
        queue.repeatMode = .all

        #expect(queue.currentTrack?.id == "track-1")
        #expect(queue.advance(automatic: true)?.id == "track-0")
    }

    @Test("go back steps to the previous track and floors at the head")
    func goBackFloorsAtHead() {
        var queue = AudioQueue(tracks: Self.tracks(3), startIndex: 1)

        #expect(queue.goBack()?.id == "track-0")
        #expect(queue.goBack()?.id == "track-0")
    }

    @Test("jump selects a track by id")
    func jumpSelectsTrack() {
        var queue = AudioQueue(tracks: Self.tracks(4))

        #expect(queue.jump(toTrackID: "track-2")?.id == "track-2")
        #expect(queue.advance(automatic: true)?.id == "track-3")
        #expect(queue.jump(toTrackID: "missing") == nil)
    }

    @Test("shuffle keeps the current track first and unshuffle restores order")
    func shuffleKeepsCurrentFirst() {
        var queue = AudioQueue(tracks: Self.tracks(6), startIndex: 2)
        var generator = SeededGenerator(state: 42)
        queue.shuffle(using: &generator)

        #expect(queue.isShuffled)
        #expect(queue.currentTrack?.id == "track-2")
        #expect(Set(queue.order) == Set(0 ..< 6))

        queue.unshuffle()
        #expect(!queue.isShuffled)
        #expect(queue.currentTrack?.id == "track-2")
        #expect(queue.order == Array(0 ..< 6))
    }

    @Test("Jellyfin mapper preserves music types and artist fields")
    func mapperPreservesMusicFields() {
        let album = BaseItemDto(
            albumArtist: "HoliznaCC0",
            artists: ["HoliznaCC0"],
            id: "album-1",
            name: "Public Domain Lofi",
            type: .musicAlbum
        )
        let song = BaseItemDto(
            album: "Public Domain Lofi",
            albumArtist: "HoliznaCC0",
            artists: ["HoliznaCC0", "Guest"],
            id: "song-1",
            name: "Tranquil Mindscape",
            type: .audio
        )
        let artist = BaseItemDto(id: "artist-1", name: "HoliznaCC0", type: .musicArtist)
        let book = BaseItemDto(id: "book-1", name: "Dracula", type: .book)
        let audiobook = BaseItemDto(id: "ab-1", name: "Dracula (Audio)", type: .audioBook)

        #expect(JellyfinMediaItemMapper.mediaItem(from: album).type == .musicAlbum)
        #expect(JellyfinMediaItemMapper.mediaItem(from: artist).type == .musicArtist)
        #expect(JellyfinMediaItemMapper.mediaItem(from: book).type == .book)
        #expect(JellyfinMediaItemMapper.mediaItem(from: audiobook).type == .audioBook)

        let mappedSong = JellyfinMediaItemMapper.mediaItem(from: song)
        #expect(mappedSong.type == .audio)
        #expect(mappedSong.album == "Public Domain Lofi")
        #expect(mappedSong.albumArtist == "HoliznaCC0")
        #expect(mappedSong.artists == ["HoliznaCC0", "Guest"])
        #expect(mappedSong.isAudioPlayable)
        #expect(!JellyfinMediaItemMapper.mediaItem(from: book).isAudioPlayable)
    }

    @MainActor
    @Test("Now Playing treats audiobooks as audio media")
    func nowPlayingTreatsAudiobooksAsAudio() {
        let audiobook = MediaItem(id: "ab-1", name: "Dracula", type: .audioBook)
        let movie = MediaItem(id: "movie-1", name: "Psych: The Movie", type: .movie)

        #expect(NowPlayingController.mediaType(for: audiobook) == .audio)
        #expect(NowPlayingController.mediaType(for: movie) == .video)
    }

    @Test("audio playback start reporting uses resumed position")
    func audioStartReportingUsesResumedPosition() {
        let audiobook = MediaItem(
            id: "ab-1",
            name: "Dracula",
            type: .audioBook,
            userData: MediaUserData(playbackPositionTicks: 123 * PlaybackTime.ticksPerSecond)
        )

        #expect(AudioPlayerStore.initialReportSeconds(for: audiobook, resume: true) == 123)
        #expect(AudioPlayerStore.initialReportSeconds(for: audiobook, resume: false) == 0)
    }

    @Test("audio-only originals with playable containers qualify for original download")
    func audioOriginalsAreDownloadable() {
        let mp3Source = MediaSource(
            container: "mp3",
            id: "source-1",
            mediaStreams: [MediaStreamInfo(codec: "mp3", index: 0, type: .audio)]
        )
        let oggSource = MediaSource(
            container: "ogg",
            id: "source-2",
            mediaStreams: [MediaStreamInfo(codec: "vorbis", index: 0, type: .audio)]
        )

        #expect(OfflineDownloadEligibility.isAVPlayerPlayable(mp3Source))
        #expect(!OfflineDownloadEligibility.isAVPlayerPlayable(oggSource))
    }

    @Test("non-native audio falls back to the universal audio transcode source")
    func audioTranscodeFallback() throws {
        let item = MediaItem(
            canDownload: true,
            id: "song-9",
            mediaSources: [
                MediaSource(
                    container: "ogg",
                    id: "source-9",
                    mediaStreams: [MediaStreamInfo(codec: "vorbis", index: 0, type: .audio)]
                ),
            ],
            type: .audio
        )

        let source = try DownloadSourceResolver.localSource(for: item)
        #expect(source.kind == .transcoded)
        #expect(source.fileExtension == "mp3")
        #expect(source.request.url?.path.contains("/Audio/song-9/universal") == true)
    }

    @Test("books download the original file, never a transcode")
    func booksDownloadOriginalFile() throws {
        let epub = MediaItem(
            canDownload: true,
            id: "book-1",
            mediaSources: [MediaSource(container: "epub", id: "source-1")],
            name: "Dracula",
            type: .book
        )
        let unknownContainer = MediaItem(canDownload: true, id: "book-2", type: .book)

        let source = try DownloadSourceResolver.localSource(for: epub)
        #expect(source.kind == .original)
        #expect(source.fileExtension == "epub")
        #expect(source.request.url?.path.contains("/Items/book-1/Download") == true)

        let fallback = try DownloadSourceResolver.localSource(for: unknownContainer)
        #expect(fallback.kind == .original)
        #expect(fallback.fileExtension == "epub")
    }

    @Test("universal audio URL is authenticated and targets the universal endpoint")
    func universalAudioURLBuilds() throws {
        let client = try JellyfinClientFactory.makeClient(
            url: #require(URL(string: "https://demo.example.com")),
            accessToken: "token-123"
        )
        let builder = StreamURLBuilder(client: client, userID: "user-1")

        let url = try builder.universalAudioURL(for: "song-1")
        #expect(url.path.contains("/Audio/song-1/universal"))
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.queryItems?.contains { $0.name == "api_key" && $0.value == "token-123" } == true)
    }
}

/// Audio/video lifecycle suites share the process-global audio session and Now Playing.
@Suite("Playback integration", .serialized)
struct PlaybackIntegrationTests {}

extension PlaybackIntegrationTests {
    @MainActor
    @Suite("Audio queue replay")
    struct AudioReplayTests {
        @Test("Play after natural queue completion restarts playback and tracks the next completion", arguments: [false, true])
        func replaysAfterNaturalCompletion(muted: Bool) async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = try silentAudio(in: directory)
            let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
            provider.audioHandler = {
                PlaybackSourceResolution(
                    url: url,
                    playSessionID: nil,
                    mediaSourceID: nil,
                    playMethod: .directStream,
                    stereoLayout: .none,
                    stereoFallbackReason: nil
                )
            }
            var createdPlayer: AVPlayer?
            // Match production: construct the player inside its factory, after
            // AudioPlayerStore has awaited audio-session activation. Silence is
            // in the PCM fixture, so both renderer modes remain covered.
            let store = try AudioPlayerStore(session: session(provider: provider), tracks: [track], playerFactory: {
                let player = AVPlayer()
                player.isMuted = muted
                createdPlayer = player
                return player
            })
            defer { store.teardown() }

            let notifications = AudioReplayNotificationProbe()
            let startupStarted = ContinuousClock.now
            await store.start()
            let startupElapsed = ContinuousClock.now - startupStarted
            let player = try #require(createdPlayer)
            let finishedItem = try #require(player.currentItem)
            try #require(await waitUntil {
                !store.isPlaying && store.state == .loaded && notifications.snapshot(for: ObjectIdentifier(finishedItem)).endCount >= 1
            }, timeoutComment(store: store, player: player, notifications: notifications, startupElapsed: startupElapsed))
            #expect(store.currentTime == 0)
            #expect(notifications.snapshot(for: ObjectIdentifier(finishedItem)).endCount == 1)
            #expect(notifications.snapshot(for: ObjectIdentifier(finishedItem)).failureCount == 0)

            store.playPause()
            try #require(await waitUntil {
                createdPlayer !== player && createdPlayer?.currentItem !== finishedItem && store.isPlaying
            }, timeoutComment(store: store, player: createdPlayer ?? player, notifications: notifications, startupElapsed: startupElapsed))
            let replayedPlayer = try #require(createdPlayer)
            let replayedItem = try #require(replayedPlayer.currentItem)
            #expect(provider.audioResolutionCallCount == 2)
            // The second completion proves replay reinstalls its end observer
            // on the newly constructed player used by production after completion.
            try #require(await waitUntil {
                !store.isPlaying && store.state == .loaded && notifications.snapshot(for: ObjectIdentifier(replayedItem)).endCount >= 1
            }, timeoutComment(store: store, player: replayedPlayer, notifications: notifications, startupElapsed: startupElapsed))
            #expect(notifications.snapshot(for: ObjectIdentifier(replayedItem)).endCount == 1)
            #expect(notifications.snapshot(for: ObjectIdentifier(replayedItem)).failureCount == 0)
        }

        @Test("Replay after automatic deletion respects local-only playback and does not stream")
        func deletedDownloadDoesNotStreamOnReplay() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = try silentAudio(in: directory)
            let files = OfflineDownloadFileStore(directory: directory.appendingPathComponent("downloads"))
            let record = try files.persistDownloadedFile(source, item: track, serverID: "s", userID: "u", fileExtension: "wav")
            let suite = UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(true, forKey: OfflineDownloadStore.deleteFinishedDefaultsKey)
            let downloads = OfflineDownloadStore(fileStore: files, coordinator: AudioReplayDownloadCoordinator(), defaults: defaults)
            downloads.load(serverID: "s", userID: "u")
            let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
            let player = AVPlayer()
            player.isMuted = true
            let store = try AudioPlayerStore(
                session: session(provider: provider),
                tracks: [track],
                downloads: downloads,
                localOnly: true,
                localProgress: OfflinePlaybackProgressStore(directory: directory.appendingPathComponent("progress")),
                playerFactory: { player }
            )
            defer { store.teardown() }

            let notifications = AudioReplayNotificationProbe()
            let startupStarted = ContinuousClock.now
            await store.start()
            let startupElapsed = ContinuousClock.now - startupStarted
            let finishedItem = try #require(player.currentItem)
            try #require(await waitUntil {
                !store.isPlaying && files.record(forRecordID: record.id) == nil && notifications.snapshot(for: ObjectIdentifier(finishedItem)).endCount >= 1
            }, timeoutComment(store: store, player: player, notifications: notifications, startupElapsed: startupElapsed))
            #expect(notifications.snapshot(for: ObjectIdentifier(finishedItem)).endCount == 1)
            #expect(notifications.snapshot(for: ObjectIdentifier(finishedItem)).failureCount == 0)
            store.playPause()
            try #require(await waitUntil {
                if case .failed = store.state {
                    return true
                }
                return false
            }, timeoutComment(store: store, player: player, notifications: notifications, startupElapsed: startupElapsed))
            #expect(!store.isPlaying)
            #expect(provider.audioResolutionCallCount == 0)
        }

        private var track: MediaItem {
            MediaItem(id: "replay", name: "Replay", runTimeTicks: PlaybackTime.ticksPerSecond, type: .audio)
        }

        private func session(provider: FakeMediaProviderSession) throws -> SessionStore {
            let url = try #require(URL(string: "https://example.com"))
            return try SessionStore(
                client: JellyfinClientFactory.makeClient(url: url),
                user: StoredUser(id: "u", name: "User", serverID: "s"),
                server: ServerConnection(id: "s", name: "Server", url: url),
                mediaProvider: provider
            )
        }

        /// Attach state to the existing failed expectation without adding a second issue.
        private func timeoutComment(store: AudioPlayerStore, player: AVPlayer, notifications: AudioReplayNotificationProbe, startupElapsed: Duration) -> Comment {
            let item = player.currentItem
            let itemStatus = item?.status.rawValue ?? -1
            let native = notifications.snapshot(for: item.map(ObjectIdentifier.init))
            #if DEBUG
                let activation = String(describing: PlaybackAudioSession.lastActivationResult)
            #else
                let activation = "unavailable"
            #endif
            return Comment(rawValue: "Audio wait expired: state=\(String(describing: store.state)), isPlaying=\(store.isPlaying), muted=\(player.isMuted), itemStatus=\(itemStatus), timeControlStatus=\(player.timeControlStatus.rawValue), rate=\(player.rate), itemTime=\(player.currentTime().seconds), itemDuration=\(item?.duration.seconds ?? .nan), actionAtItemEnd=\(player.actionAtItemEnd.rawValue), nativeEndCount=\(native.endCount), nativeFailureCount=\(native.failureCount), failedEndErrorDomain=\(native.errorDomain ?? "none"), failedEndErrorCode=\(native.errorCode.map(String.init) ?? "none"), activation=\(activation), startupElapsed=\(startupElapsed).")
        }

        private func waitUntil(_ condition: () -> Bool) async throws -> Bool {
            let deadline = ContinuousClock.now + .seconds(8)
            while !condition(), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            return condition()
        }

        /// One second of 48 kHz, mono, 16-bit PCM exercises native completion.
        private func silentAudio(in directory: URL) throws -> URL {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sampleRate: UInt32 = 48000
            let byteCount = sampleRate * 2
            var data = Data("RIFF".utf8)
            func append<T: FixedWidthInteger>(_ value: T) {
                var value = value.littleEndian
                withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
            }
            append(byteCount + 36)
            data.append(Data("WAVEfmt ".utf8))
            append(UInt32(16))
            append(UInt16(1))
            append(UInt16(1))
            append(sampleRate)
            append(sampleRate * 2)
            append(UInt16(2))
            append(UInt16(16))
            data.append(Data("data".utf8))
            append(byteCount)
            data.append(Data(count: Int(byteCount)))
            let url = directory.appendingPathComponent("replay.wav")
            try data.write(to: url)
            return url
        }
    }
}

/// Captures native events on their posting thread without reading player state.
/// The lock protects every mutable count; observer closures capture the probe weakly.
private final class AudioReplayNotificationProbe: @unchecked Sendable {
    struct Snapshot {
        var endCount = 0
        var failureCount = 0
        var errorDomain: String?
        var errorCode: Int?
    }

    private let lock = NSLock()
    private var events: [ObjectIdentifier: Snapshot] = [:]
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?

    init() {
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: nil) { [weak self] notification in
            self?.record(notification, failed: false)
        }
        failureObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: nil) { [weak self] notification in
            self?.record(notification, failed: true)
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
    }

    func snapshot(for itemID: ObjectIdentifier?) -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return itemID.flatMap { events[$0] } ?? Snapshot()
    }

    private func record(_ notification: Notification, failed: Bool) {
        guard let item = notification.object as? AVPlayerItem else { return }
        let itemID = ObjectIdentifier(item)
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
        lock.lock()
        defer { lock.unlock() }
        var snapshot = events[itemID] ?? Snapshot()
        if failed {
            snapshot.failureCount += 1
            snapshot.errorDomain = error?.domain
            snapshot.errorCode = error?.code
        } else {
            snapshot.endCount += 1
        }
        events[itemID] = snapshot
    }
}

/// No background transfers are involved in the completed-file replay regression.
@MainActor
private final class AudioReplayDownloadCoordinator: DownloadSessionCoordinating {
    func setEventHandler(_ eventHandler: DownloadSessionCoordinatorEventHandler?) {}
    func startDownload(from url: URL, recordID: String) {}
    func resumeDownload(with resumeData: Data, recordID: String) {}
    func pause(recordID: String, completion: @escaping (Data?) -> Void) {
        completion(nil)
    }

    func cancel(recordID: String) {}
    func reconnectActiveTasks() {}
}
