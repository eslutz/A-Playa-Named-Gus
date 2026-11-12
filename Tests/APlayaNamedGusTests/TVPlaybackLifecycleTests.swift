import AVFoundation
import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@MainActor
@Suite("TV video presentation lifecycle", .serialized)
struct TVPlaybackLifecycleTests {
    private func store(playbackURL: URL? = nil) throws -> PlaybackStore {
        let url = try playbackURL ?? RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov")
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.playbackHandler = {
            PlaybackSourceResolution(url: url, playSessionID: nil, mediaSourceID: nil, playMethod: .transcode, stereoLayout: .none, stereoFallbackReason: nil)
        }
        let session = SessionStore(
            client: JellyfinClient(configuration: .init(url: URL(string: "https://example.invalid")!, accessToken: "test", client: "Tests", deviceName: "Tests", deviceID: "tests", version: "1")),
            user: StoredUser(id: "tv-lifecycle-user", name: "User", serverID: "tv-lifecycle-server"),
            server: ServerConnection(id: "tv-lifecycle-server", name: "Server", url: URL(string: "https://example.invalid")!),
            mediaProvider: provider
        )
        let store = PlaybackStore(item: MediaItem(id: "fixture", type: .movie), session: session, playbackRefresh: PlaybackRefreshStore())
        store.usesPlaylistOrder = true
        return store
    }

    @Test("stall notifications are recorded only for the active player item")
    func stallsAreCapturedAndObserverIsRemoved() async throws {
        let store = try store()
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
        let store = try store(playbackURL: url)
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

    @Test("background preparation cannot start playback when it finishes")
    func preparationWhileInactive() async throws {
        let store = try store()
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
        let store = try store()
        defer { store.teardown() }
        await store.prepare()
        store.player?.rate = 1.5
        await store.selectSubtitleStream(index: 7)
        #expect(store.state == .ready)
        #expect(store.player?.rate == 1.5)
    }

    @Test("server track rebuild retains paused state")
    func pausedRebuild() async throws {
        let store = try store()
        defer { store.teardown() }
        await store.prepare()
        store.player?.pause()
        await store.selectSubtitleStream(index: 7)
        #expect(store.state == .ready)
        #expect(store.selectedSubtitleStreamIndex == 7)
        #expect(store.player?.rate == 0)
    }
}
