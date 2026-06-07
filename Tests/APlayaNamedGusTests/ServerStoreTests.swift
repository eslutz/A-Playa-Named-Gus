import Foundation
@testable import Gus
import Testing

@Suite("Server store")
struct ServerStoreTests {
    @Test("round-trips servers and users in an injected directory")
    func roundTripsServersAndUsers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ServerStore(directory: directory)
        let server = try ServerConnection(
            id: "server-1",
            name: "Psych Office",
            url: #require(URL(string: "https://jellyfin.example.com"))
        )
        let user = StoredUser(
            id: "user-7",
            name: "Gus",
            serverID: server.id,
            primaryImageTag: "tag-1"
        )

        store.saveServers([server])
        store.saveUsers([user])

        #expect(store.loadServers() == [server])
        #expect(store.loadUsers() == [user])
    }

    @Test("default application support location migrates legacy Gus folder")
    func defaultLocationMigratesLegacyFolder() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyDirectory = baseDirectory.appendingPathComponent("Gus", isDirectory: true)
        let migratedDirectory = baseDirectory.appendingPathComponent("A Playa Named Gus", isDirectory: true)
        let legacyStore = ServerStore(directory: legacyDirectory)
        let server = try ServerConnection(
            id: "server-1",
            name: "Psych Office",
            url: #require(URL(string: "https://jellyfin.example.com"))
        )

        legacyStore.saveServers([server])

        let store = ServerStore(applicationSupportDirectory: baseDirectory)

        #expect(store.loadServers() == [server])
        #expect(FileManager.default.fileExists(atPath: migratedDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: legacyDirectory.path))
    }
}
