import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("App model session switching")
struct AppModelSessionTests {
    private static let lastSessionAccountKey = "dev.ericslutz.gus.lastSignedInSessionAccount"
    private static let legacyLastUserIDKey = "dev.ericslutz.gus.lastSignedInUserID"

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

    @Test("signing out deletes only the active user's token and stored record")
    func signOutDeletesOnlyActiveUser() throws {
        let fixture = try Fixture()

        try fixture.appModel.switchToStoredUser(fixture.userA)
        fixture.appModel.signOut()

        #expect(fixture.appModel.currentSession == nil)
        #expect(fixture.appModel.lastSessionAccount == nil)
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

    @Test("legacy bare user id migrates only when it uniquely identifies a stored user")
    func legacyBareUserIDMigratesWhenUnique() throws {
        let fixture = try Fixture()
        fixture.userDefaults.set(fixture.userA.id, forKey: Self.legacyLastUserIDKey)

        let appModel = AppModel(serverStore: fixture.store, tokenStore: fixture.tokens, userDefaults: fixture.userDefaults)
        appModel.restoreLastSession()

        #expect(appModel.currentSession?.user == fixture.userA)
        #expect(appModel.lastSessionAccount == SessionCredential(user: fixture.userA).account)
        #expect(fixture.userDefaults.string(forKey: Self.lastSessionAccountKey) == SessionCredential(user: fixture.userA).account)
        #expect(fixture.userDefaults.string(forKey: Self.legacyLastUserIDKey) == nil)
    }

    @Test("legacy Jellyfin keychain account migrates to provider-qualified account")
    func legacyJellyfinKeychainAccountMigrates() throws {
        let fixture = try Fixture(seedTokenA: false)
        let credential = SessionCredential(user: fixture.userA)
        fixture.tokens.setToken("legacy-token-a", account: credential.legacyAccount)
        fixture.userDefaults.set(credential.account, forKey: Self.lastSessionAccountKey)

        let appModel = AppModel(serverStore: fixture.store, tokenStore: fixture.tokens, userDefaults: fixture.userDefaults)
        appModel.restoreLastSession()

        #expect(appModel.currentSession?.user == fixture.userA)
        #expect(fixture.tokens.token(for: credential) == "legacy-token-a")
        #expect(fixture.tokens.token(account: credential.legacyAccount) == nil)
    }

    @Test("legacy bare user id is discarded when multiple stored users match")
    func duplicateLegacyBareUserIDDoesNotRestoreWrongAccount() throws {
        let fixture = try Fixture()
        let duplicateIDUser = StoredUser(id: fixture.userA.id, name: "Burton", serverID: fixture.serverB.id)
        fixture.store.saveUsers([fixture.userA, duplicateIDUser])
        fixture.tokens.setToken("token-duplicate", for: SessionCredential(user: duplicateIDUser))
        fixture.userDefaults.set(fixture.userA.id, forKey: Self.legacyLastUserIDKey)

        let appModel = AppModel(serverStore: fixture.store, tokenStore: fixture.tokens, userDefaults: fixture.userDefaults)
        appModel.restoreLastSession()

        #expect(appModel.currentSession == nil)
        #expect(appModel.lastSessionAccount == nil)
        #expect(fixture.userDefaults.string(forKey: Self.lastSessionAccountKey) == nil)
        #expect(fixture.userDefaults.string(forKey: Self.legacyLastUserIDKey) == nil)
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
    init(seedTokenA: Bool = true, seedTokenB: Bool = true) throws {
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
        appModel = AppModel(serverStore: store, tokenStore: tokens, userDefaults: userDefaults)
    }
}
