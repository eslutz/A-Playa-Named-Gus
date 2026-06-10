import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("Up Next store")
struct UpNextStoreTests {
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
        #expect(merged.first?.name == "Manual")
    }

    @Test("default application support location migrates legacy Up Next items")
    func defaultLocationMigratesLegacyItems() {
        let baseDirectory = temporaryDirectory()
        let legacyDirectory = baseDirectory
            .appendingPathComponent("Gus", isDirectory: true)
            .appendingPathComponent("UpNext", isDirectory: true)
        let legacyPersistence = UpNextPersistence(directory: legacyDirectory)
        let item = MediaItem(id: "movie-1", name: "Manual", type: .movie)
        let scope = AccountScope(serverID: "server-1", userID: "user-1")
        legacyPersistence.save([item], scope: scope)

        let persistence = UpNextPersistence(applicationSupportDirectory: baseDirectory)
        let migratedDirectory = baseDirectory
            .appendingPathComponent("A Playa Named Gus", isDirectory: true)
            .appendingPathComponent("UpNext", isDirectory: true)

        #expect(persistence.load(scope: scope).map(\.id) == ["movie-1"])
        #expect(FileManager.default.fileExists(atPath: migratedDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: legacyDirectory.path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
