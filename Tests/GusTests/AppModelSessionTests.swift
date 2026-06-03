import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("App model session switching")
struct AppModelSessionTests {
    @Test("switching stored users preserves all saved tokens")
    func switchingStoredUsersPreservesTokens() throws {
        let fixture = try Fixture()

        try fixture.appModel.switchToStoredUser(fixture.userA)
        #expect(fixture.appModel.currentSession?.user == fixture.userA)
        #expect(fixture.appModel.lastSignedInUserID == fixture.userA.id)

        try fixture.appModel.switchToStoredUser(fixture.userB)
        #expect(fixture.appModel.currentSession?.user == fixture.userB)
        #expect(fixture.appModel.lastSignedInUserID == fixture.userB.id)
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userA)) == "token-a")
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userB)) == "token-b")
    }

    @Test("signing out deletes only the active user's token and stored record")
    func signOutDeletesOnlyActiveUser() throws {
        let fixture = try Fixture()

        try fixture.appModel.switchToStoredUser(fixture.userA)
        fixture.appModel.signOut()

        #expect(fixture.appModel.currentSession == nil)
        #expect(fixture.appModel.lastSignedInUserID == nil)
        #expect(fixture.appModel.servers == [fixture.serverA, fixture.serverB])
        #expect(fixture.appModel.users == [fixture.userB])
        #expect(fixture.store.loadUsers() == [fixture.userB])
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userA)) == nil)
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userB)) == "token-b")
    }

    @Test("stored users without a token are marked for sign-in instead of restored")
    func missingTokenRequiresSignIn() throws {
        let fixture = try Fixture(seedTokenB: false)

        #expect(fixture.appModel.hasStoredToken(for: fixture.userA))
        #expect(!fixture.appModel.hasStoredToken(for: fixture.userB))
        #expect(throws: AppModel.SessionSwitchError.self) {
            try fixture.appModel.switchToStoredUser(fixture.userB)
        }
        #expect(fixture.appModel.currentSession == nil)
    }
}

private final class MemoryTokenStore: TokenStore {
    private var tokens: [String: String] = [:]

    func token(for credential: SessionCredential) -> String? {
        tokens[credential.account]
    }

    func setToken(_ token: String, for credential: SessionCredential) {
        tokens[credential.account] = token
    }

    func deleteToken(for credential: SessionCredential) {
        tokens[credential.account] = nil
    }
}

private struct Fixture {
    let directory: URL
    let store: ServerStore
    let tokens: MemoryTokenStore
    let userDefaults: UserDefaults
    let serverA: ServerConnection
    let serverB: ServerConnection
    let userA: StoredUser
    let userB: StoredUser
    let appModel: AppModel

    @MainActor
    init(seedTokenB: Bool = true) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = ServerStore(directory: directory)
        tokens = MemoryTokenStore()
        userDefaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        serverA = try ServerConnection(
            id: "server-a",
            name: "Psych Office",
            url: #require(URL(string: "https://psych.example.com"))
        )
        serverB = try ServerConnection(
            id: "server-b",
            name: "SBPD",
            url: #require(URL(string: "https://sbpd.example.com"))
        )
        userA = StoredUser(id: "user-a", name: "Gus", serverID: serverA.id)
        userB = StoredUser(id: "user-b", name: "Shawn", serverID: serverB.id)

        store.saveServers([serverA, serverB])
        store.saveUsers([userA, userB])
        tokens.setToken("token-a", for: SessionCredential(user: userA))
        if seedTokenB {
            tokens.setToken("token-b", for: SessionCredential(user: userB))
        }
        appModel = AppModel(serverStore: store, tokenStore: tokens, userDefaults: userDefaults)
    }
}
