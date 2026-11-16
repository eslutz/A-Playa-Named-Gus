import AVFoundation
import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@MainActor
@Suite("TV video presentation lifecycle", .serialized)
struct TVPlaybackLifecycleTests {
    private func fixture(playbackURL: URL? = nil) throws -> (store: PlaybackStore, provider: FakeMediaProviderSession) {
        let url = try playbackURL ?? RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov")
        let source = MediaSource(id: "fixture-source", mediaStreams: [
            MediaStreamInfo(codec: "subrip", index: 7, language: "eng", title: "External Captions", type: .subtitle, isExternal: true),
        ])
        let item = MediaItem(id: "fixture", mediaSources: [source], type: .movie)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in item }
        provider.playbackHandler = {
            PlaybackSourceResolution(url: url, playSessionID: nil, mediaSourceID: source.id, playMethod: .transcode, stereoLayout: .none, stereoFallbackReason: nil, mediaSource: source)
        }
        let session = SessionStore(
            client: JellyfinClient(configuration: .init(url: URL(string: "https://example.invalid")!, accessToken: "test", client: "Tests", deviceName: "Tests", deviceID: "tests", version: "1")),
            user: StoredUser(id: "tv-lifecycle-user", name: "User", serverID: "tv-lifecycle-server"),
            server: ServerConnection(id: "tv-lifecycle-server", name: "Server", url: URL(string: "https://example.invalid")!),
            mediaProvider: provider
        )
        let store = PlaybackStore(request: PlaybackRequest(item: item), session: session, playbackRefresh: PlaybackRefreshStore())
        store.usesPlaylistOrder = true
        return (store, provider)
    }

    @Test("stall notifications are recorded only for the active player item")
    func stallsAreCapturedAndObserverIsRemoved() async throws {
        let store = try fixture().store
        await store.prepare()
        let playerItem = try #require(store.player?.currentItem)
        let before = DiagnosticsHub.shared.recentEvents().filter { $0.name == "playback.stalled" }.count
        NotificationCenter.default.post(name: AVPlayerItem.playbackStalledNotification, object: playerItem)
        #expect(DiagnosticsHub.shared.recentEvents().filter { $0.name == "playback.stalled" }.count == before + 1)
        store.teardown()
        NotificationCenter.default.post(name: AVPlayerItem.playbackStalledNotification, object: playerItem)
        #expect(DiagnosticsHub.shared.recentEvents().filter { $0.name == "playback.stalled" }.count == before + 1)
    }

    @Test("startup item failure reaches an actionable error state")
    func startupFailureIsObserved() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        let store = try fixture(playbackURL: url).store
        defer { store.teardown() }
        await store.prepare()
        for _ in 0 ..< 100 {
            if case .failed = store.state {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard case let .failed(message) = store.state else {
            Issue.record("AVPlayer startup failure was not surfaced")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test("failure during a suspended initial seek is not overwritten by readiness")
    func failureDuringInitialSeekIsPreserved() async throws {
        let fixture = try RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov")
        let item = MediaItem(id: "seek-failure", type: .movie)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in item }
        provider.playbackHandler = {
            PlaybackSourceResolution(url: fixture, playSessionID: nil, mediaSourceID: nil, playMethod: .transcode, stereoLayout: .none, stereoFallbackReason: nil)
        }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(
            client: JellyfinClientFactory.makeClient(url: url),
            user: StoredUser(id: "seek-user", name: "User", serverID: "seek-server"),
            server: ServerConnection(id: "seek-server", name: "Server", url: url),
            mediaProvider: provider
        )
        var seek: CheckedContinuation<Void, Never>?
        let store = PlaybackStore(request: PlaybackRequest(item: item), session: session, playbackRefresh: PlaybackRefreshStore(), initialSeek: { _, _ in
            await withCheckedContinuation { seek = $0 }
        })
        defer { store.teardown() }
        store.usesPlaylistOrder = true
        let preparation = Task { await store.prepare(startTimeTicks: 0) }
        let deadline = ContinuousClock.now + .seconds(10)
        while seek == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let suspendedSeek = seek, let playerItem = store.player?.currentItem else {
            preparation.cancel()
            seek?.resume()
            await preparation.value
            Issue.record("Initial seek did not suspend")
            return
        }
        NotificationCenter.default.post(
            name: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: playerItem,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: NSError(domain: AVFoundationErrorDomain, code: -11800)]
        )
        let failure = store.state
        guard case .failed = failure else {
            suspendedSeek.resume()
            await preparation.value
            Issue.record("Player failure was not observed during seek")
            return
        }
        suspendedSeek.resume()
        await preparation.value
        await Task.yield()
        #expect(store.state == failure)
        #expect(!store.hasStartedPlayback)
        #expect(store.player == nil)
        #expect(provider.playbackReportCallCount == 0)
    }

    @Test("background preparation cannot start playback when it finishes")
    func preparationWhileInactive() async throws {
        let store = try fixture().store
        defer { store.teardown() }
        store.setPresentationActive(false)
        await store.prepare()
        #expect(store.state == .ready)
        #expect(store.player?.rate == 0)
        store.setPresentationActive(true)
        #expect(store.player?.rate == 0, "Foregrounding does not override a paused presentation")
    }

    @Test("server track rebuild retains an explicit playback speed")
    func speedRebuild() async throws {
        let (store, provider) = try fixture()
        defer { store.teardown() }
        await store.prepare()
        let player = try #require(store.player)
        let previousItem = try #require(player.currentItem)
        #expect(store.subtitleOptions.map(\.id) == [7])
        #expect(provider.playbackResolutionCallCount == 1)
        store.player?.rate = 1.5
        await store.selectSubtitleStream(index: 7)
        #expect(store.state == .ready)
        #expect(provider.playbackResolutionCallCount == 2)
        #expect(provider.playbackRequestedSelections.last?.subtitleStreamIndex == 7)
        #expect(store.player === player)
        #expect(player.currentItem != nil && player.currentItem !== previousItem)
        #expect(store.selectedSubtitleStreamIndex == 7)
        #expect(store.player?.rate == 1.5)
    }

    @Test("server track rebuild retains paused state")
    func pausedRebuild() async throws {
        let (store, provider) = try fixture()
        defer { store.teardown() }
        await store.prepare()
        let player = try #require(store.player)
        let previousItem = try #require(player.currentItem)
        #expect(store.subtitleOptions.map(\.id) == [7])
        #expect(provider.playbackResolutionCallCount == 1)
        store.player?.pause()
        await store.selectSubtitleStream(index: 7)
        #expect(store.state == .ready)
        #expect(provider.playbackResolutionCallCount == 2)
        #expect(provider.playbackRequestedSelections.last?.subtitleStreamIndex == 7)
        #expect(store.player === player)
        #expect(player.currentItem != nil && player.currentItem !== previousItem)
        #expect(store.selectedSubtitleStreamIndex == 7)
        #expect(store.player?.rate == 0)
    }
}
