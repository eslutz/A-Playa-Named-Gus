import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@Suite("Item detail actions")
struct ItemDetailActionTests {
    @Test("authoritative replacement metadata clears a cached missing-item failure")
    @MainActor
    func replacementClearsCachedFailure() async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in throw GusError.notFound }
        let session = try SessionStore(
            client: JellyfinClientFactory.makeClient(url: #require(URL(string: "https://example.invalid"))),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: #require(URL(string: "https://example.invalid"))),
            mediaProvider: provider
        )
        let store = ItemDetailStore(item: MediaItem(id: "old", type: .movie), session: session)
        await store.load()
        store.acceptResolvedMetadata(MediaItem(id: "new", name: "Current", type: .movie))
        #expect(store.item.id == "new")
        #expect(store.state == .loaded)
    }

    @Test("next up cards use a fixed widescreen frame")
    func nextUpCardsUseWidescreenFrame() {
        #expect(abs(MediaRailMetrics.aspectRatio(for: .backdrop) - (16.0 / 9.0)) < 0.000_001)
    }
}
