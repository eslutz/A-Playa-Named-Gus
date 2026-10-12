import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("Up Next store")
struct UpNextStoreTests {
    @Test("current server metadata supersedes a pinned snapshot without changing queue order")
    func refreshesMergedMetadata() {
        let store = UpNextStore(persistence: UpNextPersistence(directory: temporaryDirectory()))
        let saved = MediaItem(id: "movie", imageTags: ["Primary": "old"], name: "Old", type: .movie)
        let fresh = MediaItem(id: "movie", imageTags: ["Primary": "new"], name: "Current", type: .movie)
        store.toggle(saved, serverID: "server", userID: "user")
        let merged = store.mergedItems(remote: [fresh], serverID: "server", userID: "user")
        #expect(merged.count == 1)
        #expect(merged.first?.imageTags["Primary"] == "new")
    }

    @Test("toggles items per server and user")
    func togglesItemsPerServerAndUser() {
        let store = UpNextStore(persistence: UpNextPersistence(directory: temporaryDirectory()))
        let item = MediaItem(id: "movie-1", name: "Movie One", type: .movie)

        store.load(serverID: "server-1", userID: "user-1")
        #expect(store.contains(item, serverID: "server-1", userID: "user-1") == false)

        store.toggle(item, serverID: "server-1", userID: "user-1")
        #expect(store.contains(item, serverID: "server-1", userID: "user-1") == true)
        #expect(store.items(serverID: "server-1", userID: "user-1").map(\.id) == ["movie-1"])

        store.toggle(item, serverID: "server-1", userID: "user-1")
        #expect(store.contains(item, serverID: "server-1", userID: "user-1") == false)
    }

    @Test("merges manual items ahead of server next up without duplicates")
    func mergesManualItemsAheadOfServerNextUpWithoutDuplicates() {
        let store = UpNextStore(persistence: UpNextPersistence(directory: temporaryDirectory()))
        let manual = MediaItem(id: "movie-1", name: "Manual", type: .movie)
        let remoteDuplicate = MediaItem(id: "movie-1", name: "Remote Duplicate", type: .movie)
        let remote = MediaItem(id: "episode-1", name: "Remote", type: .episode)

        store.load(serverID: "server-1", userID: "user-1")
        store.toggle(manual, serverID: "server-1", userID: "user-1")

        let merged = store.mergedItems(remote: [remoteDuplicate, remote], serverID: "server-1", userID: "user-1")

        #expect(merged.map(\.id) == ["movie-1", "episode-1"])
        #expect(merged.first?.name == "Remote Duplicate")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
