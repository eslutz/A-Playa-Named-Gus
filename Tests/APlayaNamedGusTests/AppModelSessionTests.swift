import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("App model session switching")
struct AppModelSessionTests {
    private static let lastSessionAccountKey = "dev.ericslutz.gus.lastSignedInSessionAccount"

    @Test("switching stored users preserves all saved tokens")
    func switchingStoredUsersPreservesTokens() async throws {
        let fixture = try Fixture()

        try await fixture.appModel.switchToStoredUser(fixture.userA)
        #expect(fixture.appModel.currentSession?.user == fixture.userA)
        #expect(fixture.appModel.lastSessionAccount == SessionCredential(user: fixture.userA).account)

        let outgoingSeerr = try #require(fixture.appModel.currentSession?.seerr)
        let outgoingRevision = outgoingSeerr.revision
        try await fixture.appModel.switchToStoredUser(fixture.userB)
        #expect(outgoingSeerr.revision != outgoingRevision)
        #expect(!outgoingSeerr.isConnected)
        #expect(throws: SeerrConnectionError.signInRequired) { try outgoingSeerr.requireClient() }
        #expect(fixture.appModel.currentSession?.user == fixture.userB)
        #expect(fixture.appModel.lastSessionAccount == SessionCredential(user: fixture.userB).account)
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userA)) == "token-a")
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userB)) == "token-b")
    }

    @Test("switching stored users clears outgoing account system surfaces")
    func switchingStoredUsersClearsOutgoingAccountSystemSurfaces() async throws {
        let cleanup = AccountCleanupSpy()
        let fixture = try Fixture(accountCleanup: cleanup.actions)

        try await fixture.appModel.switchToStoredUser(fixture.userA)
        cleanup.events.removeAll()

        try await fixture.appModel.switchToStoredUser(fixture.userB)

        #expect(cleanup.events == [
            .spotlight(serverID: fixture.serverA.id, userID: fixture.userA.id),
            .topShelf,
            .watch(serverID: fixture.serverA.id, userID: fixture.userA.id),
        ])
    }

    @Test("search history survives account switching and disappears only for an explicitly removed account")
    func searchHistoryFollowsAccount() async throws {
        let cleanup = AccountCleanupSpy()
        let fixture = try Fixture(accountCleanup: cleanup.actions)
        try await fixture.appModel.switchToStoredUser(fixture.userA)
        let previous = try #require(fixture.appModel.currentSession?.searchHistory)
        previous.record(.typed("First account"))
        try await fixture.appModel.switchToStoredUser(fixture.userB)
        let other = try #require(fixture.appModel.currentSession?.searchHistory)
        #expect(other.entries.isEmpty)
        other.record(.typed("Second account"))
        try await fixture.appModel.switchToStoredUser(fixture.userA)
        let restored = try #require(fixture.appModel.currentSession?.searchHistory)
        #expect(restored.entries == [.typed("First account")])
        await fixture.appModel.signOut()
        restored.record(.typed("Late completion"))
        let scope = AccountScope(serverID: fixture.serverA.id, userID: fixture.userA.id)
        #expect(SearchHistoryStore(scope: scope, defaults: fixture.userDefaults).entries.isEmpty)
        try await fixture.appModel.switchToStoredUser(fixture.userB)
        #expect(fixture.appModel.currentSession?.searchHistory.entries == [.typed("Second account")])
    }

    @Test("signing out deletes only the active user's token and stored record")
    func signOutDeletesOnlyActiveUser() async throws {
        let cleanup = AccountCleanupSpy()
        let fixture = try Fixture(accountCleanup: cleanup.actions)

        try await fixture.appModel.switchToStoredUser(fixture.userA)
        cleanup.events.removeAll()
        await fixture.appModel.signOut()

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
    func missingTokenRequiresSignIn() async throws {
        let fixture = try Fixture(seedTokenB: false)

        #expect(fixture.appModel.hasStoredToken(for: fixture.userA))
        #expect(!fixture.appModel.hasStoredToken(for: fixture.userB))
        await #expect(throws: AppModel.SessionSwitchError.self) {
            try await fixture.appModel.switchToStoredUser(fixture.userB)
        }
        #expect(fixture.appModel.currentSession == nil)
    }

    @Test("last session restore uses the server-qualified session account")
    func restoreUsesServerQualifiedSessionAccount() async throws {
        let fixture = try Fixture()
        let duplicateIDUser = StoredUser(id: fixture.userA.id, name: "Burton", serverID: fixture.serverB.id)
        fixture.store.saveUsers([fixture.userA, duplicateIDUser])
        fixture.tokens.setToken("token-duplicate", for: SessionCredential(user: duplicateIDUser))
        fixture.userDefaults.set(
            SessionCredential(user: duplicateIDUser).account,
            forKey: Self.lastSessionAccountKey
        )

        let appModel = AppModel(serverStore: fixture.store, tokenStore: fixture.tokens, userDefaults: fixture.userDefaults)
        await appModel.restoreLastSession()

        #expect(appModel.currentSession?.user == duplicateIDUser)
        #expect(appModel.lastSessionAccount == SessionCredential(user: duplicateIDUser).account)
    }

    @Test("debug preview session installs a signed-in session without persistence")
    func debugPreviewSessionInstallsSignedInSession() async throws {
        #if DEBUG
            let fixture = try Fixture()
            let usersBeforePreview = fixture.store.loadUsers()

            await fixture.appModel.installDebugPreviewSession()

            let session = try #require(fixture.appModel.currentSession)
            #expect(session.user.name == "Preview User")
            #expect(session.server.name == "Preview Jellyfin")
            #expect(fixture.store.loadUsers() == usersBeforePreview)
        #endif
    }

    @Test("debug preview sign out preserves persisted accounts")
    func debugPreviewSignOutPreservesPersistedAccounts() async throws {
        #if DEBUG
            let fixture = try Fixture()
            try await fixture.appModel.switchToStoredUser(fixture.userA)
            let lastSessionBeforePreview = fixture.appModel.lastSessionAccount

            await fixture.appModel.installDebugPreviewSession()
            await fixture.appModel.signOut()

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
    func clearingHandedOffSessionRemovesOnlyMatchingWatchAccount() async throws {
        let fixture = try Fixture()

        await fixture.appModel.adoptHandedOffSession(server: fixture.serverA, user: fixture.userA, token: "watch-token-a")
        await fixture.appModel.adoptHandedOffSession(server: fixture.serverB, user: fixture.userB, token: "watch-token-b")

        await fixture.appModel.clearHandedOffSession(serverID: fixture.serverB.id, userID: fixture.userB.id)

        #expect(fixture.appModel.currentSession?.user == fixture.userA)
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userA)) == "watch-token-a")
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userB)) == nil)
        #expect(fixture.appModel.users == [fixture.userA])
        #expect(fixture.store.loadUsers() == [fixture.userA])
    }

    @Test("clearing active handed off session signs out watch")
    func clearingActiveHandedOffSessionSignsOutWatch() async throws {
        let fixture = try Fixture()

        try await fixture.appModel.switchToStoredUser(fixture.userA)
        await fixture.appModel.clearHandedOffSession(serverID: fixture.serverA.id, userID: fixture.userA.id)

        #expect(fixture.appModel.currentSession == nil)
        #expect(fixture.appModel.lastSessionAccount == nil)
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userA)) == nil)
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userB)) == "token-b")
    }

    @Test("a handed-off profile refresh updates the active account without replacing its session")
    func handedOffProfileRefresh() async throws {
        let fixture = try Fixture()
        await fixture.appModel.adoptHandedOffSession(server: fixture.serverA, user: fixture.userA, token: "token-a")
        let session = try #require(fixture.appModel.currentSession)
        var updated = fixture.userA
        updated.name = "Updated"
        updated.primaryImageTag = "new-tag"
        await fixture.appModel.adoptHandedOffSession(server: fixture.serverA, user: updated, token: "token-a")
        #expect(fixture.appModel.currentSession === session)
        #expect(session.user == updated)
        #expect(fixture.store.loadUsers().contains(updated))

        // Another account's handoff must not replace the active account's profile.
        await fixture.appModel.adoptHandedOffSession(server: fixture.serverB, user: fixture.userB, token: "token-b")
        #expect(session.user == updated)
        #expect(fixture.appModel.lastSessionAccount == SessionCredential(user: updated).account)
    }

    @Test("restored and handed-off expiry preserves saved data and requests the correct account", arguments: [false, true])
    func recoverableExpiry(handedOff: Bool) async throws {
        let cleanup = AccountCleanupSpy()
        let fixture = try Fixture(accountCleanup: cleanup.actions)
        if handedOff {
            await fixture.appModel.adoptHandedOffSession(server: fixture.serverA, user: fixture.userA, token: "token-a")
        } else {
            try await fixture.appModel.restoreSavedSession(for: fixture.userA)
        }
        let session = try #require(fixture.appModel.currentSession)
        cleanup.events.removeAll()
        session.handleUnauthorized()
        session.handleUnauthorized()
        #expect(fixture.appModel.currentSession == nil)
        #expect(!session.isActive)
        #expect(fixture.appModel.reauthentication == .init(server: fixture.serverA, user: fixture.userA))
        #expect(fixture.appModel.users == [fixture.userA, fixture.userB])
        #expect(fixture.appModel.lastSessionAccount == SessionCredential(user: fixture.userA).account)
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userA)) == nil)
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userB)) == "token-b")
        #expect(cleanup.events == [
            .spotlight(serverID: fixture.serverA.id, userID: fixture.userA.id), .topShelf,
            .watch(serverID: fixture.serverA.id, userID: fixture.userA.id),
        ])
        await fixture.appModel.adoptHandedOffSession(server: fixture.serverA, user: fixture.userA, token: "replacement")
        #expect(fixture.appModel.reauthentication == nil)
        #expect(fixture.appModel.currentSession?.lease != session.lease)
    }

    @Test("old credential callbacks cannot expire a replacement account or rotated token")
    func staleExpiry() async throws {
        let cleanup = AccountCleanupSpy()
        let fixture = try Fixture(accountCleanup: cleanup.actions)
        try await fixture.appModel.restoreSavedSession(for: fixture.userA)
        let old = try #require(fixture.appModel.currentSession)
        let lateLease = old.lease
        try await fixture.appModel.switchToStoredUser(fixture.userB)
        let replacement = try #require(fixture.appModel.currentSession)
        cleanup.events.removeAll()
        fixture.appModel.recoverExpiredSession(lease: lateLease)
        #expect(fixture.appModel.currentSession === replacement)
        #expect(fixture.appModel.reauthentication == nil)
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userB)) == "token-b")
        #expect(cleanup.events.isEmpty)
        await fixture.appModel.adoptHandedOffSession(server: fixture.serverB, user: fixture.userB, token: "rotated")
        let rotated = try #require(fixture.appModel.currentSession)
        fixture.appModel.recoverExpiredSession(lease: replacement.lease)
        #expect(fixture.appModel.currentSession === rotated)
        #expect(rotated.client.accessToken == "rotated")
        #expect(!replacement.isActive)
    }

    @Test("token and endpoint replacement install new transports for the same account")
    func sameAccountRotation() async throws {
        let fixture = try Fixture()
        try await fixture.appModel.restoreSavedSession(for: fixture.userA)
        let original = try #require(fixture.appModel.currentSession)
        await fixture.appModel.adoptHandedOffSession(server: fixture.serverA, user: fixture.userA, token: "rotated")
        let rotated = try #require(fixture.appModel.currentSession)
        #expect(rotated.lease != original.lease)
        #expect(rotated.client !== original.client)
        #expect(rotated.client.accessToken == "rotated")
        var moved = fixture.serverA
        moved.url = try #require(URL(string: "https://new-address.example.com/jellyfin"))
        await fixture.appModel.adoptHandedOffSession(server: moved, user: fixture.userA, token: "rotated")
        let replaced = try #require(fixture.appModel.currentSession)
        #expect(replaced.lease != rotated.lease)
        #expect(replaced.server.url == moved.url)
        #expect(replaced.client.configuration.url == moved.url)
        #expect(fixture.appModel.server(for: fixture.userA)?.url == moved.url)
    }

    @Test("permission, offline and cancellation failures preserve the active credential")
    func nonAuthenticationErrors() async throws {
        let cleanup = AccountCleanupSpy()
        let fixture = try Fixture(accountCleanup: cleanup.actions)
        try await fixture.appModel.restoreSavedSession(for: fixture.userA)
        let session = try #require(fixture.appModel.currentSession)
        cleanup.events.removeAll()
        for error in [GusError.forbidden, .offline, .cancelled] {
            error.handleIfUnauthorized(session: session)
        }
        #expect(fixture.appModel.currentSession === session)
        #expect(fixture.tokens.token(for: SessionCredential(user: fixture.userA)) == "token-a")
        #expect(cleanup.events.isEmpty)
    }

    @Test("explicit sign out after expiry retains the account deletion policy")
    func signOutAfterExpiry() async throws {
        let cleanup = AccountCleanupSpy()
        let fixture = try Fixture(accountCleanup: cleanup.actions)
        try await fixture.appModel.restoreSavedSession(for: fixture.userA)
        fixture.appModel.currentSession?.handleUnauthorized()
        cleanup.events.removeAll()
        await fixture.appModel.signOut()
        #expect(fixture.appModel.users == [fixture.userB])
        #expect(fixture.appModel.reauthentication == nil)
        #expect(cleanup.events.contains(.books(serverID: fixture.serverA.id, userID: fixture.userA.id)))
        #expect(cleanup.events.contains(.downloads(serverID: fixture.serverA.id, userID: fixture.userA.id)))
    }

    @Test("session invalidation does not retain departed owners and coalesces owner registration")
    func invalidationOwnership() async throws {
        let fixture = try Fixture()
        try await fixture.appModel.restoreSavedSession(for: fixture.userA)
        let session = try #require(fixture.appModel.currentSession)
        var owner: InvalidationOwner? = InvalidationOwner()
        weak let releasedOwner = owner
        try session.onInvalidation(of: #require(owner)) { $0.calls += 1 }
        owner = nil
        #expect(releasedOwner == nil)
        let retainedOwner = InvalidationOwner()
        session.onInvalidation(of: retainedOwner) { $0.calls += 10 }
        session.onInvalidation(of: retainedOwner) { $0.calls += 1 }
        session.invalidate()
        session.invalidate()
        #expect(retainedOwner.calls == 1)
    }

    @Test("account replacement waits for outgoing terminal reporting after synchronous invalidation")
    func accountSwitchFlushesTerminalReports() async throws {
        let fixture = try Fixture()
        try await fixture.appModel.restoreSavedSession(for: fixture.userA)
        let outgoing = try #require(fixture.appModel.currentSession)
        let owner = InvalidationOwner()
        let gate = AsyncStream<Void>.makeStream()
        let invalidated = AsyncStream<Void>.makeStream()
        let playbackID = UUID()
        outgoing.playbackReports.enqueue(.start, sessionID: playbackID) {}
        outgoing.onInvalidation(of: owner) { owner in
            owner.calls += 1
            outgoing.playbackReports.enqueue(.stop, sessionID: playbackID) {
                for await _ in gate.stream {
                    break
                }
                owner.calls += 1
            }
            invalidated.continuation.yield(())
        }
        let transition = Task { try await fixture.appModel.switchToStoredUser(fixture.userB) }
        for await _ in invalidated.stream {
            break
        }
        #expect(!outgoing.isActive)
        #expect(fixture.appModel.currentSession === outgoing)
        #expect(fixture.appModel.isTransitioning)
        #expect(owner.calls == 1)
        gate.continuation.yield(())
        gate.continuation.finish()
        try await transition.value
        #expect(owner.calls == 2)
        #expect(fixture.appModel.currentSession?.user == fixture.userB)
        #expect(!fixture.appModel.isTransitioning)
    }
}

@MainActor
private final class InvalidationOwner {
    var calls = 0
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
