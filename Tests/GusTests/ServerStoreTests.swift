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
}
