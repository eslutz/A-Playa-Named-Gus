import AVFoundation
import Foundation
@testable import Gus
import JellyfinAPI
import Testing
#if os(iOS) || os(tvOS) || os(visionOS)
    import UIKit
#endif
#if GUS_PLAYBACK_SOAK && os(macOS)
    import Darwin
    import OSLog
#endif

@MainActor
@Suite("Playback lifecycle policies")
struct PlaybackLifecyclePolicyTests {
    #if GUS_PLAYBACK_SOAK && os(macOS)
        /// Explicit opt-in only. Run this case alone so RSS includes no parallel tests.
        @Test("native audio wall-clock soak")
        func nativeAudioWallClockSoak() async throws {
            guard let raw = ProcessInfo.processInfo.environment["GUS_PLAYBACK_SOAK_SECONDS"], let seconds = Double(raw), seconds.isFinite, seconds >= 1 else {
                Issue.record("GUS_PLAYBACK_SOAK_SECONDS must be a finite duration of at least one second")
                return
            }
            let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GUS_PLAYBACK_SOAK_OUTPUT"] ?? "/private/tmp/gus-native-playback-soak.json")
            let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
            let item = MediaItem(id: "native-soak", type: .audio)
            provider.itemHandler = { _ in item }
            let fixture = try RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov")
            provider.audioHandler = { PlaybackSourceResolution(url: fixture, playSessionID: "native-soak", mediaSourceID: "source", playMethod: .directPlay, stereoLayout: .none, stereoFallbackReason: nil) }
            let session = makeSession(provider)
            var nativePlayers: [WeakSoakPlayer] = []
            let store = AudioPlayerStore(session: session, tracks: [item], playerFactory: {
                let player = AVPlayer()
                nativePlayers.append(WeakSoakPlayer(player))
                return player
            })
            store.cycleRepeatMode()
            store.cycleRepeatMode()
            defer { store.teardown() }
            var report = NativeSoakReport(requestedSeconds: seconds)
            let soakLogger = Logger(subsystem: "dev.ericslutz.gus.playback-soak", category: "NativeSoak")
            let startedAt = ContinuousClock.now
            let deadline = startedAt + .seconds(seconds)
            await store.start()
            var nextSample = ContinuousClock.now
            while ContinuousClock.now < deadline {
                if case let .failed(message) = store.state {
                    Issue.record("Native soak playback failed: \(message)")
                    break
                }
                let observations = provider.drainPlaybackReports()
                report.starts += observations.filter { $0.kind == "start" }.count
                report.stops += observations.filter { $0.kind == "stop" }.count
                report.progress += observations.filter { $0.kind == "progress" }.count
                switch store.nativePlayer?.timeControlStatus {
                case .playing: report.playingSamples += 1
                case .waitingToPlayAtSpecifiedRate: report.waitingSamples += 1
                default: report.pausedOrPreparingSamples += 1
                }
                if ContinuousClock.now >= nextSample {
                    let elapsed = startedAt.duration(to: .now)
                    report.elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    report.samples.append(NativeSoakSample(elapsedSeconds: report.elapsedSeconds, residentBytes: Self.residentBytes(), createdPlayers: nativePlayers.count, retiredPlayersStillReferenced: nativePlayers.filter { $0.value != nil && $0.value !== store.nativePlayer }.count))
                    try await Self.writeSoakReport(report, to: output)
                    soakLogger.notice("elapsed=\(Int(report.elapsedSeconds), privacy: .public) rssBytes=\(report.samples.last?.residentBytes ?? 0, privacy: .public) createdPlayers=\(nativePlayers.count, privacy: .public) retiredReferenced=\(report.samples.last?.retiredPlayersStillReferenced ?? 0, privacy: .public) starts=\(report.starts, privacy: .public) stops=\(report.stops, privacy: .public)")
                    nextSample = ContinuousClock.now + .seconds(5)
                }
                try await Task.sleep(for: .seconds(1))
            }
            store.teardown()
            await session.playbackReports.flush()
            let final = provider.drainPlaybackReports()
            report.starts += final.filter { $0.kind == "start" }.count
            report.stops += final.filter { $0.kind == "stop" }.count
            report.progress += final.filter { $0.kind == "progress" }.count
            report.failedReports = session.playbackReports.failedCount
            report.timedOutReports = session.playbackReports.timedOutCount
            report.createdPlayers = nativePlayers.count
            // Native destruction can finish on AVFoundation's own queues.
            try await Task.sleep(for: .seconds(1))
            report.playersStillReferencedAfterClose = nativePlayers.filter { $0.value != nil }.count
            report.finished = true
            let elapsed = startedAt.duration(to: .now)
            report.elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            try await Self.writeSoakReport(report, to: output)
            try Attachment.record(String(decoding: JSONEncoder().encode(report), as: UTF8.self), named: "native-playback-soak.json")
            #expect(store.nativePlayer == nil)
            #expect(report.playingSamples > 0)
            #expect(report.starts > 0)
            #expect(report.starts == report.stops)
            #expect(report.failedReports == 0)
            #expect(report.timedOutReports == 0)
            if seconds >= 60 {
                #expect(report.createdPlayers > 1)
            }
        }

        private final class WeakSoakPlayer {
            weak var value: AVPlayer?
            init(_ value: AVPlayer) {
                self.value = value
            }
        }

        private struct NativeSoakSample: Codable, Sendable {
            let elapsedSeconds: Double
            let residentBytes: UInt64?
            let createdPlayers: Int
            let retiredPlayersStillReferenced: Int
        }

        private struct NativeSoakReport: Codable, Sendable {
            let requestedSeconds: Double
            var elapsedSeconds = 0.0
            var starts = 0
            var stops = 0
            var progress = 0
            var playingSamples = 0
            var waitingSamples = 0
            var pausedOrPreparingSamples = 0
            var failedReports = 0
            var timedOutReports = 0
            var createdPlayers = 0
            var playersStillReferencedAfterClose = 0
            var finished = false
            var samples: [NativeSoakSample] = []
        }

        private static func residentBytes() -> UInt64? {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
            }
            return result == KERN_SUCCESS ? UInt64(info.resident_size) : nil
        }

        private static func writeSoakReport(_ report: NativeSoakReport, to url: URL) async throws {
            let data = try JSONEncoder().encode(report)
            try await Task.detached { try data.write(to: url, options: .atomic) }.value
        }
    #endif

    @Test("thirty real native open/close cycles retire every item and report boundary")
    func nativeOpenCloseCycles() async throws {
        #if os(iOS) || os(tvOS) || os(visionOS)
            // Physical QA opts into a measured foreground precondition; production
            // background/Now Playing eligibility is deliberately not changed.
            if ProcessInfo.processInfo.environment["GUS_REQUIRE_ACTIVE_PLAYBACK_TEST_HOST"] == "1" {
                let requestedAt = Date()
                let initialState = UIApplication.shared.applicationState.rawValue
                let active = await ActivePlaybackTestHostPrerequisite().wait(timeout: .seconds(15))
                let observedAt = Date()
                let observedState = UIApplication.shared.applicationState.rawValue
                print("Native playback host prerequisite: requested=\(requestedAt) initialState=\(initialState) observed=\(observedAt) observedState=\(observedState) active=\(active)")
                try #require(active, "Physical playback host must become active before native activation; requested=\(requestedAt), observed=\(observedAt), initialState=\(initialState), observedState=\(observedState)")
            }
        #endif
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let item = MediaItem(id: "native-cycle", type: .movie)
        provider.itemHandler = { _ in item }
        let fixture = try RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov")
        provider.playbackHandler = { PlaybackSourceResolution(url: fixture, playSessionID: "cycle", mediaSourceID: "source", playMethod: .directPlay, stereoLayout: .none, stereoFallbackReason: nil) }
        let session = makeSession(provider)
        for cycle in 0 ..< 30 {
            let store = PlaybackStore(request: PlaybackRequest(item: item), session: session, playbackRefresh: PlaybackRefreshStore())
            await store.prepare()
            #if (os(iOS) || os(tvOS) || os(visionOS)) && DEBUG
                if cycle == 0, ProcessInfo.processInfo.environment["GUS_REQUIRE_ACTIVE_PLAYBACK_TEST_HOST"] == "1" {
                    print("First native preparation completed: observed=\(Date()) state=\(UIApplication.shared.applicationState.rawValue) activation=\(String(describing: PlaybackAudioSession.lastActivationResult)) playbackState=\(store.state)")
                }
            #endif
            let deadline = ContinuousClock.now + .seconds(45)
            while !store.hasStartedPlayback, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(store.hasStartedPlayback, "Cycle \(cycle) must reach actual playing")
            let player = try #require(store.player)
            let retiredItem = try #require(player.currentItem)
            store.teardown()
            store.teardown()
            #expect(player.currentItem == nil)
            #expect(store.player == nil)
            await session.playbackReports.flush()
            let reportsBeforeStaleEnd = provider.playbackReports.count
            NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: retiredItem)
            await Task.yield()
            #expect(provider.playbackReports.count == reportsBeforeStaleEnd)
        }
        let boundaries = provider.playbackReports.filter { $0.kind == "start" || $0.kind == "stop" }
        #expect(boundaries.count == 60)
        #expect(boundaries.enumerated().allSatisfy { $0.element.kind == ($0.offset.isMultiple(of: 2) ? "start" : "stop") })
    }

    @Test("ordered boundaries survive replacement and only pending progress is coalesced")
    func orderedReports() async {
        let queue = PlaybackReportQueue(timeout: .seconds(1))
        let first = UUID(), second = UUID()
        var events: [String] = []
        var release: CheckedContinuation<Void, Never>?
        queue.enqueue(.start, sessionID: first) {
            events.append("start-A")
            await withCheckedContinuation { release = $0 }
        }
        while release == nil {
            await Task.yield()
        }
        queue.enqueue(.progress, sessionID: first) { events.append("old-progress") }
        queue.enqueue(.progress, sessionID: first) { events.append("latest-progress") }
        queue.enqueue(.stop, sessionID: first) { events.append("stop-A") }
        queue.enqueue(.progress, sessionID: first) { events.append("late-progress") }
        queue.enqueue(.stop, sessionID: first) { events.append("duplicate-stop") }
        queue.enqueue(.start, sessionID: second) { events.append("start-B") }
        release?.resume()
        await queue.flush()
        #expect(events == ["start-A", "stop-A", "start-B"])
    }

    @Test("a timed out report releases the queue and records its outcome")
    func reportTimeout() async {
        let queue = PlaybackReportQueue(timeout: .milliseconds(10))
        let id = UUID()
        var stopped = false
        queue.enqueue(.start, sessionID: id) { try await Task.sleep(for: .seconds(2)) }
        queue.enqueue(.stop, sessionID: id) { stopped = true }
        await queue.flush()
        #expect(stopped)
        #expect(queue.timedOutCount == 1)
        #expect(queue.succeededCount == 1)
    }

    @Test("late successful allocation is released after a deadline returns")
    func abandonedResolution() async {
        var release: CheckedContinuation<String, Never>?
        var discarded: [String] = []
        do {
            _ = try await PlaybackDeadline.run(for: .milliseconds(10), cancelOperation: false, onDiscard: { discarded.append($0) }) {
                await withCheckedContinuation { release = $0 }
            }
            Issue.record("Deadline unexpectedly succeeded")
        } catch { #expect(error is PlaybackDeadline.Timeout) }
        release?.resume(returning: "opened-live-stream")
        for _ in 0 ..< 100 where discarded.isEmpty {
            await Task.yield()
        }
        #expect(discarded == ["opened-live-stream"])
    }

    @Test("semantic memory is opt in, account scoped, same series and never reuses a stream index")
    func semanticTrackMemory() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let first = AccountScope(serverID: "server-a", userID: "same-user")
        let other = AccountScope(serverID: "server-b", userID: "same-user")
        let memory = PlaybackTrackMemory(defaults: defaults)
        let item = MediaItem(id: "episode-a", seriesID: "series", type: .episode)
        let source = MediaSource(mediaStreams: [MediaStreamInfo(codec: "aac", index: 2, language: "eng", title: "Main", type: .audio)])
        memory.remember(item: item, source: source, selection: PlaybackStreamSelection(audioStreamIndex: 2, subtitleStreamIndex: -1), scope: first)
        #expect(memory.selection(for: MediaItem(id: "episode-b", seriesID: "series", type: .episode), source: source, scope: first) == .none)
        memory.setEnabled(true, scope: first)
        memory.remember(item: item, source: source, selection: PlaybackStreamSelection(audioStreamIndex: 2, subtitleStreamIndex: -1), scope: first)
        let next = MediaSource(mediaStreams: [MediaStreamInfo(codec: "aac", index: 19, language: "en-US", title: "Main", type: .audio)])
        let remembered = memory.selection(for: MediaItem(id: "episode-b", seriesID: "series", type: .episode), source: next, scope: first)
        #expect(remembered.audioStreamIndex == 19)
        #expect(remembered.subtitleStreamIndex == -1)
        #expect(memory.selection(for: MediaItem(id: "episode-b", seriesID: "series", type: .episode), source: next, scope: other) == .none)
        #expect(memory.selection(for: MediaItem(id: "episode-b", seriesID: "other-series", type: .episode), source: next, scope: first) == .none)
    }

    @Test("persisted audio and subtitle preferences contain semantic identity without source indexes")
    func semanticPreferencePersistence() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scope = AccountScope(serverID: "server", userID: "user")
        let memory = PlaybackTrackMemory(defaults: defaults)
        memory.setEnabled(true, scope: scope)
        let source = MediaSource(mediaStreams: [
            MediaStreamInfo(codec: "aac", index: 2, language: "eng", title: "Main", type: .audio, isExternal: false),
            MediaStreamInfo(codec: "srt", index: 7, language: "eng", title: "SDH", type: .subtitle, isForced: false, isHearingImpaired: true),
        ])
        memory.remember(
            item: MediaItem(id: "episode-a", seriesID: "series", type: .episode),
            source: source,
            selection: .init(audioStreamIndex: 2, subtitleStreamIndex: 7),
            scope: scope
        )
        let blob = try #require(defaults.dictionaryRepresentation().first { $0.key.hasPrefix("playbackTrackMemory.") && $0.value is Data }?.value as? Data)
        let stored = try #require(JSONSerialization.jsonObject(with: blob) as? [String: Any])
        let series = try #require(stored["series"] as? [String: Any])
        for kind in ["audio", "subtitle"] {
            let preference = try #require(series[kind] as? [String: Any])
            #expect(preference["index"] == nil)
            #expect(preference["codec"] == nil)
        }
        let next = MediaSource(mediaStreams: [
            MediaStreamInfo(codec: "ac3", index: 19, language: "en-US", title: "Main", type: .audio),
            MediaStreamInfo(codec: "ass", index: 27, language: "en-US", title: "SDH", type: .subtitle, isForced: false, isHearingImpaired: true),
        ])
        let restored = PlaybackTrackMemory(defaults: defaults).selection(for: MediaItem(id: "episode-b", seriesID: "series", type: .episode), source: next, scope: scope)
        #expect(restored.audioStreamIndex == 19)
        #expect(restored.subtitleStreamIndex == 27)
    }

    @Test("cut switches retain semantic intent and remap audio instead of copying indexes")
    func cutSwitchSemanticIntent() {
        let audio = MediaStreamInfo(codec: "aac", index: 2, language: "eng", title: "Commentary", type: .audio)
        let original = PlaybackRequest(item: MediaItem(id: "movie", type: .movie), streamSelection: .init(audioStreamIndex: 2, subtitleStreamIndex: -1, mediaSourceID: "theatrical"), audioTrack: audio, subtitleIntent: .off, start: .fromBeginning, presentation: .twoD, maxStreamingBitrate: 3_000_000)
        let changed = original.selectingMediaSource("extended", startPositionTicks: 90_000_000)
        #expect(changed.requestedStartTicks == 90_000_000)
        #expect(changed.streamSelection.audioStreamIndex == nil)
        #expect(changed.subtitleIntent == .off)
        #expect(changed.presentation == .twoD)
        #expect(changed.maxStreamingBitrate == 3_000_000)
        let source = MediaSource(id: "extended", mediaStreams: [MediaStreamInfo(codec: "aac", index: 19, language: "en-US", title: "Commentary", type: .audio)])
        let selection = changed.selection(in: source)
        #expect(selection.mediaSourceID == "extended")
        #expect(selection.audioStreamIndex == 19)
        #expect(selection.subtitleStreamIndex == -1)
    }

    @Test("track menu checks distinguish Automatic, Off and remapped explicit selection")
    func trackMenuIntent() {
        let preferred = MediaStreamInfo(index: 2, language: "eng", title: "Commentary", type: .subtitle)
        let source = MediaSource(id: "alternate", mediaStreams: [
            MediaStreamInfo(index: 7, isDefault: true, language: "eng", title: "Main", type: .subtitle),
            MediaStreamInfo(index: 19, language: "eng", title: "Commentary", type: .subtitle),
        ], defaultSubtitleStreamIndex: 7)
        let item = MediaItem(id: "menu-intent", mediaSources: [source], type: .movie)
        var request = PlaybackRequest(item: item)
        #expect(PlaybackTrackMenuSelection.subtitle(for: request, source: source) == .automatic)
        request.subtitleIntent = .off
        #expect(PlaybackTrackMenuSelection.subtitle(for: request, source: source) == .off)
        request.subtitleIntent = .explicit
        request.subtitleTrack = preferred
        #expect(PlaybackTrackMenuSelection.subtitle(for: request, source: source) == .stream(19))
        var unavailable = source
        unavailable.mediaStreams.removeAll { $0.index == 19 }
        #expect(PlaybackTrackMenuSelection.subtitle(for: request, source: unavailable) == nil)
        // The effective/default track at7 must never turn a missing explicit choice
        // into an Automatic, Off or unrelated explicit checkmark.
        #expect(PlaybackTrackMenuSelection.audio(for: PlaybackRequest(item: item), source: source) == .automatic)
    }

    @Test("actual store setters change explicit intent when the effective track is unchanged")
    func unchangedEffectiveTrackUpdatesIntent() async {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.playbackHandler = { throw GusError.notFound }
        provider.audioHandler = { throw GusError.notFound }
        let session = makeSession(provider)
        let source = MediaSource(id: "source", mediaStreams: [MediaStreamInfo(index: 7, language: "eng", title: "Main", type: .audio)])
        let movie = MediaItem(id: "intent-no-op", mediaSources: [source], type: .movie)
        // A native Automatic selection may effectively have no subtitle (-1).
        // Keep that effective state distinct from the explicit Automatic request.
        let automatic = PlaybackRequest(item: movie, streamSelection: .init(audioStreamIndex: nil, subtitleStreamIndex: -1), subtitleIntent: .automatic)
        let subtitles = PlaybackStore(request: automatic, session: session, playbackRefresh: PlaybackRefreshStore())
        #expect(subtitles.subtitleMenuSelection == .automatic)
        #expect(subtitles.selectedSubtitleStreamIndex == nil)
        await subtitles.selectSubtitleStream(index: nil)
        #expect(subtitles.request.subtitleIntent == .off)
        #expect(subtitles.subtitleMenuSelection == .off)
        await subtitles.selectSubtitleStream(index: nil)
        await subtitles.selectAutomaticSubtitles()
        #expect(subtitles.request.subtitleIntent == .automatic)

        let unavailable = MediaStreamInfo(index: 2, language: "fra", title: "Français", type: .audio)
        let missingAudio = PlaybackRequest(item: movie, audioTrack: unavailable)
        let video = PlaybackStore(request: missingAudio, session: session, playbackRefresh: PlaybackRefreshStore())
        #expect(video.audioMenuSelection == nil)
        await video.selectAudioStream(index: nil)
        #expect(video.request.audioTrack == nil)
        #expect(video.audioMenuSelection == .automatic)
        await video.selectAudioStream(index: nil)

        let song = MediaItem(id: "audio-intent-no-op", mediaSources: [source], type: .audio)
        let audio = AudioPlayerStore(session: session, tracks: [song], request: PlaybackRequest(item: song, audioTrack: unavailable))
        #expect(audio.audioMenuSelection == nil)
        await audio.selectAudioStream(index: nil)
        #expect(audio.request?.audioTrack == nil)
        #expect(audio.request?.streamSelection.audioStreamIndex == nil)
        #expect(audio.audioMenuSelection == .automatic)
        await audio.selectAudioStream(index: 7)
        #expect(audio.audioMenuSelection == .stream(7))
        await audio.selectAudioStream(index: nil)
        #expect(audio.audioMenuSelection == .automatic)
        await audio.selectAudioStream(index: nil)
        #expect(provider.playbackRequestedSelections.isEmpty)
        #expect(provider.playbackReports.isEmpty)
    }

    @Test("native chapter metadata starts no fetch until its value is requested")
    func deferredChapterArtwork() async throws {
        let payload = Data([1, 2, 3])
        let loader = ChapterArtworkLoader(isCurrent: { true }) { _, _ in payload }
        defer { loader.invalidate() }
        let metadata = try loader.metadataItem(for: URLRequest(url: #require(URL(string: "https://images.example/chapter.jpg"))))
        #expect(loader.startedRequestCount == 0)
        let value = try await metadata.load(.dataValue)
        #expect(value == payload)
        #expect(loader.startedRequestCount == 1)
    }

    @Test("native chapter metadata cancels pending value loading at player retirement")
    func canceledChapterArtwork() async throws {
        let loader = ChapterArtworkLoader(isCurrent: { true }) { _, _ in
            try await Task.sleep(for: .seconds(60))
            return Data([1])
        }
        let metadata = try loader.metadataItem(for: URLRequest(url: #require(URL(string: "https://images.example/chapter.jpg"))))
        let loading = Task { try await metadata.load(.dataValue) }
        let deadline = ContinuousClock.now + .seconds(5)
        while loader.startedRequestCount == 0, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(loader.startedRequestCount == 1)
        loader.invalidate()
        do {
            _ = try await loading.value
            Issue.record("Retired chapter value unexpectedly completed")
        } catch { /* AVFoundation may wrap the cancellation in a metadata error. */ }
        #expect(loader.startedRequestCount == 1)
    }

    @Test("native chapter requests respect the per-player compressed-byte ceiling")
    func chapterArtworkByteBudget() async throws {
        let loader = ChapterArtworkLoader(isCurrent: { true }) { _, maximum in Data(repeating: 1, count: maximum) }
        defer { loader.invalidate() }
        for index in 0 ..< 17 {
            let metadata = try loader.metadataItem(for: URLRequest(url: #require(URL(string: "https://images.example/chapter-\(index).jpg"))))
            do {
                let data = try await metadata.load(.dataValue)
                #expect(index < 16)
                #expect(data?.count == 256 * 1024)
            } catch { #expect(index == 16) }
        }
        #expect(loader.startedRequestCount == 16)
    }

    @Test("ambiguous same-language commentary and accessibility tracks are not interchanged")
    func semanticTrackAmbiguity() {
        let preferred = MediaStreamInfo(codec: "aac", index: 2, language: "eng", title: "Main", type: .audio)
        let alternatives = [
            MediaStreamInfo(codec: "aac", index: 9, language: "eng", title: "Commentary", type: .audio),
            MediaStreamInfo(codec: "aac", index: 10, language: "eng", title: "Audio Description", type: .audio),
        ]
        #expect(PlaybackTrackMemory.match(preferred, in: alternatives) == nil)
    }

    @Test("a named track in any language cannot silently fall back to a different same-language role")
    func customTrackRoleIdentity() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = PlaybackTrackMemory(defaults: defaults)
        let scope = AccountScope(serverID: "server", userID: "user")
        let commentary = MediaStreamInfo(displayTitle: "Français - AAC - Stereo", index: 2, language: "fra", title: "Commentaire du réalisateur", type: .audio)
        let main = MediaStreamInfo(displayTitle: "Français - AAC - Stereo", index: 9, language: "fra", title: "Piste principale", type: .audio)
        memory.setEnabled(true, scope: scope)
        memory.remember(
            item: MediaItem(id: "episode-a", seriesID: "series", type: .episode),
            source: MediaSource(mediaStreams: [commentary]),
            selection: .init(audioStreamIndex: 2),
            scope: scope
        )
        let next = MediaItem(id: "episode-b", seriesID: "series", type: .episode)
        #expect(memory.selection(for: next, source: MediaSource(mediaStreams: [main]), scope: scope).audioStreamIndex == nil)
        #expect(memory.hasUnavailableSelection(for: next, source: MediaSource(mediaStreams: [main]), scope: scope))

        let generatedBefore = MediaStreamInfo(displayTitle: "English - AAC - Stereo", index: 3, language: "eng", type: .audio)
        let generatedAfter = MediaStreamInfo(displayTitle: "English - AC3 - 5.1", index: 12, language: "eng", type: .audio)
        #expect(PlaybackTrackMemory.match(generatedBefore, in: [generatedAfter]) == 12)
    }

    @Test("a discarded video allocation is released once without ever reporting playback")
    func staleVideoAllocation() async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let item = MediaItem(id: "live", type: .liveChannel)
        provider.itemHandler = { _ in item }
        var reply: CheckedContinuation<PlaybackSourceResolution, Never>?
        provider.playbackHandler = { await withCheckedContinuation { reply = $0 } }
        let session = makeSession(provider)
        let store = PlaybackStore(request: PlaybackRequest(item: item), session: session, playbackRefresh: PlaybackRefreshStore())
        let task = Task { await store.prepare() }
        let deadline = ContinuousClock.now + .seconds(10)
        while reply == nil, ContinuousClock.now < deadline {
            await Task.yield()
        }
        let continuation = try #require(reply)
        session.invalidate()
        let resource = PlaybackResource(liveStreamID: "tuner-a", playSessionID: "play-a", isTranscoding: true)
        try continuation.resume(returning: PlaybackSourceResolution(
            url: #require(URL(string: "https://example.invalid/live.m3u8")),
            playSessionID: "play-a",
            mediaSourceID: "source-a",
            playMethod: .transcode,
            stereoLayout: .none,
            stereoFallbackReason: nil,
            resource: resource,
            isLive: true
        ))
        await task.value
        await session.playbackReports.flush()
        #expect(provider.releasedPlaybackResources == [resource])
        #expect(provider.playbackReports.isEmpty)
        #expect(store.player == nil)
        #expect(!store.hasStartedPlayback)
    }

    @Test("dismissal during metadata never starts an allocating request", arguments: [false, true])
    func canceledBeforeAllocation(audio: Bool) async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let item = MediaItem(id: "canceled-before-allocation", type: audio ? .audio : .movie)
        var metadata: CheckedContinuation<MediaItem, Never>?
        provider.itemHandler = { _ in await withCheckedContinuation { metadata = $0 } }
        let session = makeSession(provider)
        let video = audio ? nil : PlaybackStore(request: PlaybackRequest(item: item), session: session, playbackRefresh: PlaybackRefreshStore())
        let music = audio ? AudioPlayerStore(session: session, tracks: [item]) : nil
        let preparation = Task {
            if let video {
                await video.prepare()
            }
            if let music {
                await music.start()
            }
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while metadata == nil, ContinuousClock.now < deadline {
            await Task.yield()
        }
        let reply = try #require(metadata)
        video?.teardown()
        music?.teardown()
        reply.resume(returning: item)
        await preparation.value
        #expect(provider.playbackRequestedSelections.isEmpty)
        #expect(provider.playbackReports.isEmpty)
        #expect(video?.player == nil)
        #expect(music?.nativePlayer == nil)
    }

    @Test("prepared paused video has no started event, report or viewing activity")
    func pausedPreparationDoesNotStart() async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let item = MediaItem(id: "paused-fixture", type: .movie)
        provider.itemHandler = { _ in item }
        let fixture = try RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov")
        let resource = PlaybackResource(liveStreamID: "unstarted-live", playSessionID: "paused", isTranscoding: false)
        provider.playbackHandler = { PlaybackSourceResolution(url: fixture, playSessionID: "paused", mediaSourceID: "source", playMethod: .directPlay, stereoLayout: .none, stereoFallbackReason: nil, resource: resource, isLive: true) }
        let session = makeSession(provider)
        let store = PlaybackStore(request: PlaybackRequest(item: item), session: session, playbackRefresh: PlaybackRefreshStore())
        store.setPresentationActive(false)
        await store.prepare()
        #expect(store.state == .ready)
        #expect(!store.hasStartedPlayback)
        #expect(store.player?.rate == 0)
        await session.playbackReports.flush()
        #expect(provider.playbackReports.isEmpty)
        store.teardown()
        for _ in 0 ..< 100 where provider.releasedPlaybackResources.isEmpty {
            await Task.yield()
        }
        #expect(provider.releasedPlaybackResources == [resource])
    }

    @Test("audio session refusal fails before resolution and explicit retry can prepare", arguments: [false, true])
    func audioSessionRefusal(audio: Bool) async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let item = MediaItem(id: "session-refusal", type: audio ? .audio : .movie)
        provider.itemHandler = { _ in item }
        let fixture = try RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov")
        let resolution = PlaybackSourceResolution(url: fixture, playSessionID: "session-retry", mediaSourceID: "source", playMethod: .directPlay, stereoLayout: .none, stereoFallbackReason: nil)
        provider.playbackHandler = { resolution }
        provider.audioHandler = { resolution }
        let session = makeSession(provider)
        let activationState = AudioSessionRefusalState()
        let activate: @MainActor @Sendable (Bool) async throws -> Void = { video in
            activationState.arguments.append(video)
            let shouldDeny = activationState.denied
            try await PlaybackAudioSession.activate(video: video, configureCategory: { _ in }, activateSession: {
                if shouldDeny {
                    throw NSError(domain: NSOSStatusErrorDomain, code: 560_557_684, userInfo: [NSLocalizedDescriptionKey: "Audio session activation denied"])
                }
            })
        }
        let message = String(localized: "Couldn't start audio playback. Try again.")
        let video = audio ? nil : PlaybackStore(request: PlaybackRequest(item: item), session: session, playbackRefresh: PlaybackRefreshStore(), activateAudioSession: activate)
        let music = audio ? AudioPlayerStore(session: session, tracks: [item], activateAudioSession: activate) : nil
        defer { video?.teardown(); music?.teardown() }
        video?.setPresentationActive(false)
        await video?.prepare()
        await music?.start()
        if let video {
            #expect(video.state == .failed(message))
            #expect(!video.hasStartedPlayback)
            #expect(video.player == nil)
        }
        if let music {
            #expect(music.state == .failed(message))
            #expect(!music.isPlaying)
            #expect(!music.hasPreparedContent)
            #expect(music.nativePlayer == nil)
        }
        await session.playbackReports.flush()
        #expect(activationState.arguments == [!audio])
        #expect(provider.playbackResolutionCallCount == 0)
        #expect(provider.audioResolutionCallCount == 0)
        #expect(provider.playbackReports.isEmpty)
        #expect(provider.releasedPlaybackResources.isEmpty)

        activationState.denied = false
        await video?.prepare()
        await music?.start()
        #expect(activationState.arguments == [!audio, !audio])
        #expect(provider.playbackResolutionCallCount == (audio ? 0 : 1))
        #expect(provider.audioResolutionCallCount == (audio ? 1 : 0))
        if let video {
            #expect(video.state == .ready); #expect(video.player != nil)
        }
        if let music {
            #expect(music.state == .loaded); #expect(music.nativePlayer != nil)
        }
    }

    @Test("live Stop owns release even when its response is lost", arguments: [false, true])
    func liveStopDoesNotDoubleClose(responseLost: Bool) async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let item = MediaItem(id: "shared-live-fixture", type: .liveChannel)
        provider.itemHandler = { _ in item }
        let fixture = try RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov")
        let resource = PlaybackResource(liveStreamID: "shared-tuner", playSessionID: "live-play", isTranscoding: true)
        provider.playbackHandler = { PlaybackSourceResolution(url: fixture, playSessionID: "live-play", mediaSourceID: "source", playMethod: .transcode, stereoLayout: .none, stereoFallbackReason: nil, resource: resource, isLive: true) }
        var serverConsumerReleases = 0
        provider.playbackReportHandler = { kind, _, _, _ in
            if kind == "stop" {
                serverConsumerReleases += 1
                if responseLost {
                    throw URLError(.networkConnectionLost)
                }
            }
        }
        let session = makeSession(provider)
        let store = PlaybackStore(request: PlaybackRequest(item: item), session: session, playbackRefresh: PlaybackRefreshStore())
        await store.prepare()
        let deadline = ContinuousClock.now + .seconds(45)
        while !store.hasStartedPlayback, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.hasStartedPlayback)
        store.teardown()
        store.teardown()
        await session.playbackReports.flush()
        #expect(serverConsumerReleases == 1)
        #expect(provider.releasedPlaybackResources.isEmpty)
        #expect(session.playbackReports.failedCount == (responseLost ? 1 : 0))
    }

    @Test("failure after real playback sends one failed stop and releases its resource")
    func terminalFailure() async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let item = MediaItem(id: "failure-fixture", type: .movie)
        provider.itemHandler = { _ in item }
        let fixture = try RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov")
        let resource = PlaybackResource(liveStreamID: nil, playSessionID: "failure", isTranscoding: true)
        provider.playbackHandler = { PlaybackSourceResolution(url: fixture, playSessionID: "failure", mediaSourceID: "source", playMethod: .transcode, stereoLayout: .none, stereoFallbackReason: nil, resource: resource) }
        let session = makeSession(provider)
        let store = PlaybackStore(request: PlaybackRequest(item: item), session: session, playbackRefresh: PlaybackRefreshStore())
        defer { store.teardown() }
        await store.prepare()
        let deadline = ContinuousClock.now + .seconds(45)
        while !store.hasStartedPlayback, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.hasStartedPlayback)
        let nativeItem = try #require(store.player?.currentItem)
        let error = NSError(domain: AVFoundationErrorDomain, code: -11800)
        for _ in 0 ..< 2 {
            NotificationCenter.default.post(
                name: AVPlayerItem.failedToPlayToEndTimeNotification,
                object: nativeItem,
                userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: error]
            )
        }
        await session.playbackReports.flush()
        #expect(provider.playbackReports.filter { $0.kind == "start" }.count == 1)
        let stops = provider.playbackReports.filter { $0.kind == "stop" }
        #expect(stops.count == 1)
        #expect(stops.first?.context.isFailed == true)
        #expect(provider.releasedPlaybackResources == [resource])
        #expect(store.player == nil)
        if case .failed = store.state {} else {
            Issue.record("Missing terminal failure")
        }
    }

    @Test("audio failed-end finalizes once and never repeats an ambiguous live release", arguments: [false, true])
    func audioTerminalFailure(live: Bool) async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let item = MediaItem(id: "audio-failure", type: .audio)
        provider.itemHandler = { _ in item }
        let fixture = try RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov")
        let resource = PlaybackResource(liveStreamID: live ? "shared-live-audio" : nil, playSessionID: "audio-play", isTranscoding: true)
        provider.audioHandler = { PlaybackSourceResolution(url: fixture, playSessionID: "audio-play", mediaSourceID: "source", playMethod: .transcode, stereoLayout: .none, stereoFallbackReason: nil, resource: resource, isLive: live) }
        provider.playbackReportHandler = { kind, _, _, _ in
            if live, kind == "stop" {
                throw URLError(.networkConnectionLost)
            }
        }
        let session = makeSession(provider)
        let store = AudioPlayerStore(session: session, tracks: [item])
        defer { store.teardown() }
        await store.start()
        let deadline = ContinuousClock.now + .seconds(45)
        while !store.isPlaying, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.isPlaying)
        let nativeItem = try #require(store.nativePlayer?.currentItem)
        for _ in 0 ..< 2 {
            NotificationCenter.default.post(name: AVPlayerItem.failedToPlayToEndTimeNotification, object: nativeItem, userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: NSError(domain: AVFoundationErrorDomain, code: -11800)])
        }
        await session.playbackReports.flush()
        let stops = provider.playbackReports.filter { $0.kind == "stop" }
        #expect(stops.count == 1)
        #expect(stops.first?.context.isFailed == true)
        #expect(store.nativePlayer == nil)
        #expect(provider.releasedPlaybackResources == (live ? [] : [resource]))
        if case .failed = store.state {} else {
            Issue.record("Missing audio terminal failure")
        }
    }

    @Test("shared request round trip preserves explicit source, semantic tracks and authoritative start over")
    func playbackRequestContract() throws {
        let audio = MediaStreamInfo(codec: "aac", index: 2, language: "eng", title: "Main", type: .audio)
        let request = PlaybackRequest(
            item: MediaItem(id: "episode", type: .episode),
            streamSelection: PlaybackStreamSelection(audioStreamIndex: 2, subtitleStreamIndex: -1, mediaSourceID: "cut-b"),
            audioTrack: audio,
            subtitleIntent: .off,
            start: .fromBeginning,
            startPositionTicks: 900_000_000
        )
        let restored = try JSONDecoder().decode(PlaybackRequest.self, from: JSONEncoder().encode(request))
        #expect(restored == request)
        #expect(restored.requestedStartTicks == 0)
        let source = MediaSource(id: "cut-b", mediaStreams: [MediaStreamInfo(codec: "aac", index: 19, language: "en-US", title: "Main", type: .audio)])
        #expect(restored.selection(in: source).audioStreamIndex == 19)
        #expect(restored.selection(in: source).subtitleStreamIndex == -1)
        var automatic = restored
        automatic.subtitleIntent = .automatic
        #expect(automatic.selection(in: source).subtitleStreamIndex == nil)
    }

    @Test("ordered audio pages advance raw offsets while deduplicating library identities")
    func pagedAudioQueue() async {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var offsets: [Int] = []
        provider.itemsHandler = { query in
            offsets.append(query.startIndex)
            if query.startIndex == 1 {
                return MediaItemPage(items: [MediaItem(id: "a", type: .audio), MediaItem(id: "b", type: .audio)], totalRecordCount: 4)
            }
            return MediaItemPage(items: [MediaItem(id: "c", type: .audio)], totalRecordCount: 4)
        }
        let continuation = AudioQueueContinuation(query: MediaItemQuery(parentID: "album", startIndex: 0, limit: 2), nextStartIndex: 1, totalRecordCount: 4)
        let store = AudioPlayerStore(session: makeSession(provider), tracks: [MediaItem(id: "a", type: .audio)], continuation: continuation)
        await store.loadMoreQueue()
        #expect(store.queueContinuation?.nextStartIndex == 3)
        #expect(store.queue.tracks.compactMap(\.id) == ["a", "b"])
        await store.loadMoreQueue()
        #expect(offsets == [1, 3])
        #expect(store.queueContinuation == nil)
        #expect(store.queue.tracks.compactMap(\.id) == ["a", "b", "c"])
        #expect(store.queue.currentTrack?.id == "a")
    }

    @Test("incomplete audio pages retain the continuation and retry the same raw offset")
    func incompleteAudioQueueRetries() async {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var offsets: [Int] = []
        provider.itemsHandler = { query in
            offsets.append(query.startIndex)
            if offsets.count == 1 {
                // A later response may omit its total. The continuation still
                // knows this empty page cannot mean the end of the album.
                return MediaItemPage(items: [], totalRecordCount: nil)
            }
            if query.startIndex == 1 {
                return MediaItemPage(items: [MediaItem(id: "b", type: .audio)], totalRecordCount: nil)
            }
            return MediaItemPage(items: [MediaItem(id: "c", type: .audio), MediaItem(id: "d", type: .audio)], totalRecordCount: nil)
        }
        let continuation = AudioQueueContinuation(query: MediaItemQuery(parentID: "album", startIndex: 0, limit: 2), nextStartIndex: 1, totalRecordCount: 4)
        let store = AudioPlayerStore(session: makeSession(provider), tracks: [MediaItem(id: "a", type: .audio)], continuation: continuation)
        await store.loadMoreQueue()
        #expect(store.queueErrorMessage != nil)
        #expect(store.queueContinuation?.nextStartIndex == continuation.nextStartIndex)
        #expect(store.queueContinuation?.totalRecordCount == continuation.totalRecordCount)
        #expect(store.queue.tracks.compactMap(\.id) == ["a"])
        #expect(!store.isLoadingQueue)
        await store.loadMoreQueue()
        #expect(store.queueErrorMessage == nil)
        #expect(store.queueContinuation?.nextStartIndex == 2)
        #expect(store.queueContinuation?.totalRecordCount == 4)
        #expect(store.queue.tracks.compactMap(\.id) == ["a", "b"])
        await store.loadMoreQueue()
        #expect(offsets == [1, 1, 2])
        #expect(store.queueContinuation == nil)
        #expect(store.queue.tracks.compactMap(\.id) == ["a", "b", "c", "d"])
        #expect(provider.audioResolutionCallCount == 0)
        #expect(provider.playbackReportCallCount == 0)
    }

    @Test("online alternate source duration and checkpoint never inherit the primary cut", arguments: [false, true])
    func onlineAlternateDuration(knownDuration: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gus-online-duration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let alternate = MediaSource(id: "alternate", runTimeTicks: knownDuration ? 40_000_000 : nil)
        let sources = [MediaSource(id: "primary", runTimeTicks: 10_000_000), alternate]
        let movie = MediaItem(id: "video-duration", mediaSources: sources, runTimeTicks: 10_000_000, type: .movie)
        let song = MediaItem(id: "audio-duration", mediaSources: sources, runTimeTicks: 10_000_000, type: .audio)
        provider.itemHandler = { id in id == movie.id ? movie : song }
        let fixture = try RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov")
        // The response omits duration even when canonical B metadata knows it.
        let resolution = PlaybackSourceResolution(url: fixture, playSessionID: "alternate", mediaSourceID: "alternate", playMethod: .directPlay, stereoLayout: .none, stereoFallbackReason: nil, mediaSource: MediaSource(id: "alternate"))
        provider.playbackHandler = { resolution }
        provider.audioHandler = { resolution }
        let session = makeSession(provider)
        let scope = AccountScope(serverID: session.server.id, userID: session.user.id)
        let progress = OfflinePlaybackProgressStore(directory: directory)
        progress.checkpoint(itemID: "video-duration", positionTicks: 20_000_000, scope: scope, mediaSourceID: "alternate")
        progress.checkpoint(itemID: "audio-duration", positionTicks: 20_000_000, scope: scope, mediaSourceID: "alternate")
        let selection = PlaybackStreamSelection(audioStreamIndex: nil, subtitleStreamIndex: nil, mediaSourceID: "alternate")
        var videoSeek: Int?
        let video = PlaybackStore(request: PlaybackRequest(item: movie, streamSelection: selection), session: session, playbackRefresh: PlaybackRefreshStore(), localProgress: progress, initialSeek: { _, ticks in videoSeek = ticks })
        defer { video.teardown() }
        video.setPresentationActive(false)
        await video.prepare()
        #expect(video.state == .ready)
        #expect(videoSeek == 20_000_000)
        #expect(video.item.runTimeTicks == (knownDuration ? 40_000_000 : nil))
        let audio = AudioPlayerStore(session: session, tracks: [song], request: PlaybackRequest(item: song, streamSelection: selection), localProgress: progress)
        defer { audio.teardown() }
        await audio.start()
        #expect(audio.state == .loaded)
        #expect(audio.currentTime >= 2)
        #expect(audio.currentTrack?.runTimeTicks == (knownDuration ? 40_000_000 : nil))
        #expect(audio.duration == (knownDuration ? 4 : 0))
    }

    @Test("shuffle collects the full eligible queue before producing its permutation")
    func completeShuffle() async {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemsHandler = { _ in MediaItemPage(items: [MediaItem(id: "b", type: .audio), MediaItem(id: "c", type: .audio)], totalRecordCount: 3) }
        let continuation = AudioQueueContinuation(query: MediaItemQuery(parentID: "album", startIndex: 0, limit: 2), nextStartIndex: 1, totalRecordCount: 3)
        let store = AudioPlayerStore(session: makeSession(provider), tracks: [MediaItem(id: "a", type: .audio)], continuation: continuation)
        #expect(await store.collectForShuffle())
        #expect(store.queueContinuation == nil)
        #expect(store.queue.isShuffled)
        #expect(Set(store.queue.tracks.compactMap(\.id)) == ["a", "b", "c"])
        #expect(!store.isCollectingShuffle)
        #expect(provider.playbackReportCallCount == 0)
    }

    @MainActor
    private final class AudioSessionRefusalState {
        var arguments: [Bool] = []
        var denied = true
    }

    private func makeSession(_ provider: FakeMediaProviderSession) -> SessionStore {
        let url = URL(string: "https://example.invalid")!
        return SessionStore(
            client: JellyfinClientFactory.makeClient(url: url),
            user: StoredUser(id: "lifecycle-user", name: "User", serverID: "lifecycle-server"),
            server: ServerConnection(id: "lifecycle-server", name: "Server", url: url),
            mediaProvider: provider
        )
    }
}

#if os(iOS) || os(tvOS) || os(visionOS)
    /// Notification-owned wait avoids racing unit-host startup or polling/sleeping
    /// before activation. Expiry/cancellation removes the observer and reports failure.
    @MainActor
    private final class ActivePlaybackTestHostPrerequisite {
        private var observer: NSObjectProtocol?
        private var deadlineTask: Task<Void, Never>?
        private var continuation: CheckedContinuation<Bool, Never>?

        func wait(timeout: Duration) async -> Bool {
            if Task.isCancelled {
                return false
            }
            if UIApplication.shared.applicationState == .active {
                return true
            }
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    observer = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                        Task { @MainActor in
                            if UIApplication.shared.applicationState == .active {
                                self?.complete()
                            }
                        }
                    }
                    deadlineTask = Task<Void, Never> { [weak self] in
                        do { try await Task.sleep(for: timeout) } catch { return }
                        self?.complete()
                    }
                    // Subscribe before rechecking so activation between the initial
                    // observation and registration cannot be lost.
                    if Task.isCancelled || UIApplication.shared.applicationState == .active {
                        complete()
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.complete(cancelled: true) }
            }
        }

        private func complete(cancelled: Bool = false) {
            guard let continuation else { return }
            let active = !cancelled && !Task.isCancelled && UIApplication.shared.applicationState == .active
            self.continuation = nil
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
            deadlineTask?.cancel()
            deadlineTask = nil
            continuation.resume(returning: active)
        }
    }
#endif
