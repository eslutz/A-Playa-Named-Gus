import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("App model session switching")
struct AppModelSessionTests {
    private static let lastSessionAccountKey = "dev.ericslutz.gus.lastSignedInSessionAccount"

    @Test("switching stored users preserves all saved tokens")
    func switchingStoredUsersPreservesTokens() throws {
        let fixture = try Fixture()

        try fixture.appModel.switchToStoredUser(fixture.userA)
        #expect(fixture.appModel.currentSession?.user == fixture.userA)
        #expect(fixture.appModel.lastSessionAccount == SessionCredential(user: fixture.userA).account)

        try fixture.appModel.switchToStoredUser(fixture.userB)
        #expect(fixture.appModel.currentSession?.user == fixture.userB)
        #expect(fixture.appModel.lastSessionAccount == SessionCredential(user: fixture.userB).account)
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userA)) == "token-a")
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userB)) == "token-b")
    }

    @Test("switching stored users clears outgoing account system surfaces")
    func switchingStoredUsersClearsOutgoingAccountSystemSurfaces() throws {
        let cleanup = AccountCleanupSpy()
        let fixture = try Fixture(accountCleanup: cleanup.actions)

        try fixture.appModel.switchToStoredUser(fixture.userA)
        cleanup.events.removeAll()

        try fixture.appModel.switchToStoredUser(fixture.userB)

        #expect(cleanup.events == [
            .spotlight(serverID: fixture.serverA.id, userID: fixture.userA.id),
            .topShelf,
            .watch(serverID: fixture.serverA.id, userID: fixture.userA.id),
        ])
    }

    @Test("signing out deletes only the active user's token and stored record")
    func signOutDeletesOnlyActiveUser() throws {
        let cleanup = AccountCleanupSpy()
        let fixture = try Fixture(accountCleanup: cleanup.actions)

        try fixture.appModel.switchToStoredUser(fixture.userA)
        cleanup.events.removeAll()
        fixture.appModel.signOut()

        #expect(fixture.appModel.currentSession == nil)
        #expect(fixture.appModel.lastSessionAccount == nil)
        #expect(fixture.appModel.servers == [fixture.serverA, fixture.serverB])
        #expect(fixture.appModel.users == [fixture.userB])
        #expect(fixture.store.loadUsers() == [fixture.userB])
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userA)) == nil)
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userB)) == "token-b")
        #expect(cleanup.events == [
            .spotlight(serverID: fixture.serverA.id, userID: fixture.userA.id),
            .topShelf,
            .books(serverID: fixture.serverA.id, userID: fixture.userA.id),
            .downloads(serverID: fixture.serverA.id, userID: fixture.userA.id),
            .watch(serverID: fixture.serverA.id, userID: fixture.userA.id),
        ])
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

    @Test("last session restore uses the server-qualified session account")
    func restoreUsesServerQualifiedSessionAccount() throws {
        let fixture = try Fixture()
        let duplicateIDUser = StoredUser(id: fixture.userA.id, name: "Burton", serverID: fixture.serverB.id)
        fixture.store.saveUsers([fixture.userA, duplicateIDUser])
        fixture.tokens.setToken("token-duplicate", for: SessionCredential(user: duplicateIDUser))
        fixture.userDefaults.set(
            SessionCredential(user: duplicateIDUser).account,
            forKey: Self.lastSessionAccountKey
        )

        let appModel = AppModel(serverStore: fixture.store, tokenStore: fixture.tokens, userDefaults: fixture.userDefaults)
        appModel.restoreLastSession()

        #expect(appModel.currentSession?.user == duplicateIDUser)
        #expect(appModel.lastSessionAccount == SessionCredential(user: duplicateIDUser).account)
    }

    @Test("debug preview session installs a signed-in session without persistence")
    func debugPreviewSessionInstallsSignedInSession() throws {
        #if DEBUG
            let fixture = try Fixture()
            let usersBeforePreview = fixture.store.loadUsers()

            fixture.appModel.installDebugPreviewSession()

            let session = try #require(fixture.appModel.currentSession)
            #expect(session.user.name == "Preview User")
            #expect(session.server.name == "Preview Jellyfin")
            #expect(fixture.store.loadUsers() == usersBeforePreview)
        #endif
    }

    @Test("debug preview sign out preserves persisted accounts")
    func debugPreviewSignOutPreservesPersistedAccounts() throws {
        #if DEBUG
            let fixture = try Fixture()
            try fixture.appModel.switchToStoredUser(fixture.userA)
            let lastSessionBeforePreview = fixture.appModel.lastSessionAccount

            fixture.appModel.installDebugPreviewSession()
            fixture.appModel.signOut()

            #expect(fixture.appModel.currentSession == nil)
            #expect(fixture.appModel.lastSessionAccount == lastSessionBeforePreview)
            #expect(fixture.appModel.servers == [fixture.serverA, fixture.serverB])
            #expect(fixture.appModel.users == [fixture.userA, fixture.userB])
            #expect(fixture.store.loadServers() == [fixture.serverA, fixture.serverB])
            #expect(fixture.store.loadUsers() == [fixture.userA, fixture.userB])
            #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userA)) == "token-a")
            #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userB)) == "token-b")
        #endif
    }

    @Test("clearing handed off session removes only the matching watch account")
    func clearingHandedOffSessionRemovesOnlyMatchingWatchAccount() throws {
        let fixture = try Fixture()

        fixture.appModel.adoptHandedOffSession(server: fixture.serverA, user: fixture.userA, token: "watch-token-a")
        fixture.appModel.adoptHandedOffSession(server: fixture.serverB, user: fixture.userB, token: "watch-token-b")

        fixture.appModel.clearHandedOffSession(serverID: fixture.serverB.id, userID: fixture.userB.id)

        #expect(fixture.appModel.currentSession?.user == fixture.userA)
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userA)) == "watch-token-a")
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userB)) == nil)
        #expect(fixture.appModel.users == [fixture.userA])
        #expect(fixture.store.loadUsers() == [fixture.userA])
    }

    @Test("clearing active handed off session signs out watch")
    func clearingActiveHandedOffSessionSignsOutWatch() throws {
        let fixture = try Fixture()

        try fixture.appModel.switchToStoredUser(fixture.userA)
        fixture.appModel.clearHandedOffSession(serverID: fixture.serverA.id, userID: fixture.userA.id)

        #expect(fixture.appModel.currentSession == nil)
        #expect(fixture.appModel.lastSessionAccount == nil)
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userA)) == nil)
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userB)) == "token-b")
    }

    @Test("a handed-off profile refresh updates the active account without replacing its session")
    func handedOffProfileRefresh() throws {
        let fixture = try Fixture()
        fixture.appModel.adoptHandedOffSession(server: fixture.serverA, user: fixture.userA, token: "token-a")
        let session = try #require(fixture.appModel.currentSession)
        var updated = fixture.userA
        updated.name = "Updated"
        updated.primaryImageTag = "new-tag"
        fixture.appModel.adoptHandedOffSession(server: fixture.serverA, user: updated, token: "token-a")
        #expect(fixture.appModel.currentSession === session)
        #expect(session.user == updated)
        #expect(fixture.store.loadUsers().contains(updated))

        // Another account's handoff must not replace the active account's profile.
        fixture.appModel.adoptHandedOffSession(server: fixture.serverB, user: fixture.userB, token: "token-b")
        #expect(session.user == updated)
    }
}

@MainActor
private final class AccountCleanupSpy {
    enum Event: Equatable {
        case spotlight(serverID: String, userID: String)
        case topShelf
        case books(serverID: String, userID: String)
        case downloads(serverID: String, userID: String)
        case watch(serverID: String, userID: String)
    }

    var events: [Event] = []

    var actions: AppModel.AccountCleanupActions {
        AppModel.AccountCleanupActions(
            clearSearchIndex: { [self] serverID, userID in
                events.append(.spotlight(serverID: serverID, userID: userID))
            },
            clearTopShelf: { [self] in
                events.append(.topShelf)
            },
            clearBookState: { [self] scope in
                events.append(.books(serverID: scope.serverID, userID: scope.userID))
            },
            clearDownloads: { [self] scope in
                events.append(.downloads(serverID: scope.serverID, userID: scope.userID))
            },
            clearWatchCredential: { [self] server, user in
                events.append(.watch(serverID: server.id, userID: user.id))
            }
        )
    }
}

private final class MemoryTokenStore: TokenStore {
    private var tokens: [String: String] = [:]

    func token(for credential: SessionCredential) -> String? {
        tokens[credential.account]
    }

    func token(account: String) -> String? {
        tokens[account]
    }

    func setToken(_ token: String, for credential: SessionCredential) {
        tokens[credential.account] = token
    }

    func setToken(_ token: String, account: String) {
        tokens[account] = token
    }

    func deleteToken(for credential: SessionCredential) {
        tokens[credential.account] = nil
    }

    func deleteToken(account: String) {
        tokens[account] = nil
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
    init(
        seedTokenA: Bool = true,
        seedTokenB: Bool = true,
        accountCleanup: AppModel.AccountCleanupActions = .live
    ) throws {
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
        if seedTokenA {
            tokens.setToken("token-a", for: SessionCredential(user: userA))
        }
        if seedTokenB {
            tokens.setToken("token-b", for: SessionCredential(user: userB))
        }
        appModel = AppModel(
            serverStore: store,
            tokenStore: tokens,
            userDefaults: userDefaults,
            accountCleanup: accountCleanup
        )
    }
}
