import AVFoundation
import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@MainActor
@Suite("TV video presentation lifecycle", .serialized)
struct TVPlaybackLifecycleTests {
    private func store() throws -> PlaybackStore {
        let url = try RepositoryTestFixtures.url(for: "Tests/Fixtures/OfflinePlaylist.mov")
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
