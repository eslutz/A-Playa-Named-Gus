import Foundation
@testable import Gus
import Testing

@Suite("Home store helpers")
struct HomeStoreTests {
    @Test("a delayed Shared with You batch cannot overwrite newer links")
    @MainActor func sharedLinksSupersedeOlderBatch() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var pending: CheckedContinuation<MediaItem, Never>?
        provider.itemHandler = { id in
            if id == "a" {
                return await withCheckedContinuation { pending = $0 }
            }
            return .init(id: id, officialRating: "G", type: .movie)
        }
        defer { pending?.resume(returning: .init(id: "a", officialRating: "G", type: .movie)) }
        let store = try makeHome(provider)
        let older = Task { await store.loadSharedWithYou(links: [.item(id: "a", serverID: "s", provider: .jellyfin)], title: "Older") }
        try await waitUntil { pending != nil }
        await store.loadSharedWithYou(links: [.item(id: "b", serverID: "s", provider: .jellyfin)], title: "Newer")
        #expect(store.sharedWithYouItems.compactMap(\.id) == ["b"])
        pending?.resume(returning: .init(id: "a", officialRating: "G", type: .movie)); pending = nil
        await older.value
        #expect(store.sharedWithYouItems.compactMap(\.id) == ["b"])
        #expect(store.sharedWithYouTitle == "Newer")
    }

    @Test("clearing Shared with You invalidates an in-flight batch")
    @MainActor func clearingSharedLinksSupersedesBatch() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var pending: CheckedContinuation<MediaItem, Never>?
        provider.itemHandler = { id in
            if id == "a" {
                return await withCheckedContinuation { pending = $0 }
            }
            return .init(id: id, officialRating: "G", type: .movie)
        }
        defer { pending?.resume(returning: .init(id: "a", officialRating: "G", type: .movie)) }
        let store = try makeHome(provider)
        await store.loadSharedWithYou(links: [.item(id: "existing", serverID: "s", provider: .jellyfin)], title: "Existing")
        #expect(!store.sharedWithYouItems.isEmpty)
        let older = Task { await store.loadSharedWithYou(links: [.item(id: "a", serverID: "s", provider: .jellyfin)], title: "Loading") }
        try await waitUntil { pending != nil }
        await store.loadSharedWithYou(links: [], title: "Cleared")
        pending?.resume(returning: .init(id: "a", officialRating: "G", type: .movie)); pending = nil
        await older.value
        #expect(store.sharedWithYouItems.isEmpty)
        #expect(store.sharedWithYouTitle == "Cleared")
    }

    @MainActor private func makeHome(_ provider: FakeMediaProviderSession) throws -> HomeStore {
        let url = try #require(URL(string: "https://example.invalid"))
        return HomeStore(session: SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: .init(id: "u", name: "User", serverID: "s"), server: .init(id: "s", name: "Server", url: url), mediaProvider: provider))
    }

    @MainActor private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0 ..< 2000 {
            if predicate() {
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(predicate(), "Timed out awaiting delayed provider request")
    }

    @Test("maps latest episodes to unique series display items with posters")
    func mapsLatestEpisodesToUniqueSeriesDisplayItems() {
        let episodes = [
            MediaItem(
                id: "episode-1",
                imageTags: [:],
                name: "Pilot",
                seriesID: "series-1",
                seriesName: "Psych",
                seriesPrimaryImageTag: "poster-1",
                type: .episode
            ),
            MediaItem(
                id: "episode-2",
                imageTags: [:],
                name: "Spellingg Bee",
                seriesID: "series-1",
                seriesName: "Psych",
                seriesPrimaryImageTag: "poster-1",
                type: .episode
            ),
            MediaItem(
                id: "episode-3",
                imageTags: [:],
                name: "The Kidnapping",
                seriesID: "series-2",
                seriesName: "Monk",
                seriesPrimaryImageTag: "poster-2",
                type: .episode
            ),
        ]

        let displayItems = LatestMediaDisplayMapper.displayItems(from: episodes, libraryCollectionType: .tvshows)

        #expect(displayItems.map(\.id) == ["series-1", "series-2"])
        #expect(displayItems.map(\.name) == ["Psych", "Monk"])
        #expect(displayItems.map(\.type) == [.series, .series])
        #expect(displayItems.first?.imageTags[MediaImageKind.primary.rawValue] == "poster-1")
    }
}
