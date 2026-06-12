import Foundation
import JellyfinAPI
import Observation
import OSLog

/// Root application model: the set of known servers/users and the current session.
///
/// Injected at the `App` root via `.environment(...)`. Replaces Swiftfin's Factory DI +
/// Stinsen root coordinator: `RootView` switches on `currentSession`, and connect /
/// sign-in / restore / sign-out all funnel through here.
@MainActor
@Observable
final class AppModel {
    /// The app-wide instance. SwiftUI injects it via `@Environment`; non-SwiftUI entry
    /// points (the CarPlay scene) read the same instance so there is a single source of
    /// truth for the active session — a second `AppModel` would diverge on sign-out and
    /// account switches.
    static let shared = AppModel()

    enum ConnectError: LocalizedError {
        case invalidURL
        case unreachable(String)
        case authenticationFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return String(localized: "Enter a valid server address.", comment: "Connect error: malformed URL")
            case let .unreachable(detail):
                return String(localized: "Couldn't reach that server. \(detail)", comment: "Connect error: server unreachable, with detail")
            case .authenticationFailed:
                return String(localized: "Sign in failed. Check your username and password.", comment: "Sign-in error: bad credentials")
            }
        }
    }

    enum SessionSwitchError: LocalizedError {
        case missingServer
        case missingToken

        var errorDescription: String? {
            switch self {
            case .missingServer:
                return String(localized: "That server is no longer available.", comment: "Stored-user switch error: missing server")
            case .missingToken:
                return String(localized: "Sign in again to use that account.", comment: "Stored-user switch error: missing saved token")
            }
        }
    }

    struct AccountCleanupActions {
        var clearSearchIndex: @MainActor (_ serverID: String, _ userID: String) -> Void
        var clearTopShelf: @MainActor () -> Void
        var clearBookState: @MainActor (_ scope: AccountScope) -> Void
        var clearDownloads: @MainActor (_ scope: AccountScope) -> Void
        var clearWatchCredential: @MainActor (_ server: ServerConnection, _ user: StoredUser) -> Void

        static let live = AccountCleanupActions(
            clearSearchIndex: { serverID, userID in
                SpotlightIndexer.deleteIndex(serverID: serverID, userID: userID)
            },
            clearTopShelf: {
                #if os(tvOS)
                    TopShelfSnapshot.clear()
                #endif
            },
            clearBookState: { scope in
                BookFileProvider.purgeCachedFiles(scope: scope)
                BookProgressStore.shared.deleteLocators(scope: scope)
                BookProgressStore.shared.flush()
            },
            clearDownloads: { scope in
                try? OfflineDownloadFileStore.shared.deleteRecords(serverID: scope.serverID, userID: scope.userID)
            },
            clearWatchCredential: { server, user in
                #if os(iOS) && canImport(WatchConnectivity)
                    WatchSessionRelay.shared.clear(server: server, user: user)
                #endif
            }
        )
    }

    private static let lastSessionAccountDefaultsKey = "dev.ericslutz.gus.lastSignedInSessionAccount"
    private static let legacyLastUserIDDefaultsKey = "dev.ericslutz.gus.lastSignedInUserID"
    #if DEBUG
        private static let debugPreviewServerID = "debug-preview-server"
        private static let debugPreviewUserID = "debug-preview-user"
    #endif

    private let serverStore: ServerStore
    private let tokenStore: TokenStore
    private let userDefaults: UserDefaults
    private let accountCleanup: AccountCleanupActions
    private let logger = Logger(category: .appModel)

    private(set) var servers: [ServerConnection] = []
    private(set) var users: [StoredUser] = []
    var currentSession: SessionStore?

    private(set) var lastSessionAccount: String? {
        didSet {
            persistLastSessionAccount()
        }
    }

    private func persistLastSessionAccount() {
        if let lastSessionAccount {
            userDefaults.set(lastSessionAccount, forKey: Self.lastSessionAccountDefaultsKey)
        } else {
            userDefaults.removeObject(forKey: Self.lastSessionAccountDefaultsKey)
        }
        userDefaults.removeObject(forKey: Self.legacyLastUserIDDefaultsKey)
    }

    private static func loadLastSessionAccount(
        from userDefaults: UserDefaults,
        users: [StoredUser]
    ) -> String? {
        if let account = userDefaults.string(forKey: lastSessionAccountDefaultsKey) {
            return account
        }

        guard let legacyUserID = userDefaults.string(forKey: legacyLastUserIDDefaultsKey) else {
            return nil
        }

        let matches = users.filter { $0.id == legacyUserID }
        guard matches.count == 1, let user = matches.first else {
            return nil
        }

        return SessionCredential(user: user).account
    }

    init(
        serverStore: ServerStore = .shared,
        tokenStore: TokenStore = KeychainStore.shared,
        userDefaults: UserDefaults = .standard,
        accountCleanup: AccountCleanupActions = .live
    ) {
        self.serverStore = serverStore
        self.tokenStore = tokenStore
        self.userDefaults = userDefaults
        self.accountCleanup = accountCleanup
        servers = serverStore.loadServers()
        users = serverStore.loadUsers()
        lastSessionAccount = Self.loadLastSessionAccount(from: userDefaults, users: users)
        persistLastSessionAccount()
    }

    // MARK: - Launch restore

    /// Silently restores the last session from the Keychain token + persisted stores.
    func restoreLastSession() {
        guard currentSession == nil,
              let account = lastSessionAccount,
              let user = users.first(where: { SessionCredential(user: $0).account == account })
        else { return }

        do {
            try restoreSavedSession(for: user)
        } catch {
            logger.error("Last-session restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Restores a saved user's session when its server and Keychain token are present.
    func restoreSavedSession(for user: StoredUser) throws {
        try restoreSavedSession(for: user, clearingCurrentAccount: false)
    }

    private func restoreSavedSession(for user: StoredUser, clearingCurrentAccount: Bool) throws {
        guard let server = server(for: user) else { throw SessionSwitchError.missingServer }
        guard let token = tokenMigratingLegacyAccountIfNeeded(for: user) else {
            throw SessionSwitchError.missingToken
        }

        if clearingCurrentAccount {
            clearCurrentAccountDataIfNeeded(replacingWith: user, on: server)
        }
        let client = JellyfinClientFactory.makeClient(url: server.url, accessToken: token)
        currentSession = SessionStore(client: client, user: user, server: server)
        lastSessionAccount = SessionCredential(user: user).account
        DiagnosticsHub.shared.record(.sessionRestored)
        publishSessionToWatch(server: server, user: user, token: token)
        logger.info("Restored session for user \(user.name, privacy: .private)")
    }

    /// Hands the active session to a paired Apple Watch (iOS only; no-op elsewhere).
    private func publishSessionToWatch(server: ServerConnection, user: StoredUser, token: String) {
        #if os(iOS) && canImport(WatchConnectivity)
            WatchSessionRelay.shared.publish(server: server, user: user, token: token)
        #endif
    }

    /// Adopts a session handed off from a companion device (the watch side of the
    /// WatchConnectivity relay): persists the credential and signs in if signed out.
    func adoptHandedOffSession(server: ServerConnection, user: StoredUser, token: String) {
        tokenStore.setToken(token, for: SessionCredential(user: user))
        upsert(server: server)
        upsert(user: user)
        lastSessionAccount = SessionCredential(user: user).account

        guard currentSession == nil else { return }
        let client = JellyfinClientFactory.makeClient(url: server.url, accessToken: token)
        currentSession = SessionStore(client: client, user: user, server: server)
        logger.info("Adopted handed-off session for user \(user.name, privacy: .private)")
    }

    func switchToStoredUser(_ user: StoredUser) throws {
        guard currentSession?.user != user else { return }
        try restoreSavedSession(for: user, clearingCurrentAccount: true)
    }

    func clearHandedOffSession(serverID: String, userID: String) {
        guard let user = users.first(where: { $0.id == userID && $0.serverID == serverID }) else {
            let credential = SessionCredential(serverID: serverID, userID: userID)
            tokenStore.deleteToken(for: credential)
            tokenStore.deleteToken(account: credential.legacyAccount)
            return
        }

        let credential = SessionCredential(user: user)
        tokenStore.deleteToken(for: credential)
        tokenStore.deleteToken(account: credential.legacyAccount)
        users.removeAll { $0.id == userID && $0.serverID == serverID }
        serverStore.saveUsers(users)

        guard currentSession?.user == user else {
            if lastSessionAccount == credential.account {
                lastSessionAccount = nil
            }
            return
        }

        lastSessionAccount = nil
        currentSession = nil
    }

    func hasStoredToken(for user: StoredUser) -> Bool {
        tokenMigratingLegacyAccountIfNeeded(for: user) != nil
    }

    func server(for user: StoredUser) -> ServerConnection? {
        servers.first { $0.id == user.serverID }
    }

    func users(on server: ServerConnection) -> [StoredUser] {
        users.filter { $0.serverID == server.id }
    }

    #if DEBUG
        /// Connects and signs in to the local demo Jellyfin container started by
        /// `Scripts/demo-server.sh` — a real signed-in session over the rights-cleared
        /// demo library, used for screenshots and reviewer/tester walkthroughs.
        func connectToLocalDemoServer() async {
            do {
                let server = try await connect(to: "http://localhost:8096")
                try await signIn(to: server, username: "gus", password: "playa-demo")
            } catch {
                logger.error("Demo server connect failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        /// Installs an in-memory signed-in session for simulator screenshots and UI tests.
        /// This intentionally avoids `ServerStore`, `TokenStore`, and `UserDefaults` writes.
        func installDebugPreviewSession() {
            guard let serverURL = URL(string: "https://preview.jellyfin.invalid") else { return }

            let server = ServerConnection(
                id: Self.debugPreviewServerID,
                name: "Preview Jellyfin",
                url: serverURL
            )
            let user = StoredUser(
                id: Self.debugPreviewUserID,
                name: "Preview User",
                serverID: server.id
            )

            currentSession = SessionStore(
                client: JellyfinClientFactory.makeClient(url: server.url, accessToken: "debug-preview-token"),
                user: user,
                server: server
            )
        }
    #endif

    // MARK: - Connect

    /// Normalizes a URL, queries public system info, follows any redirect, and persists
    /// the resulting `ServerConnection`. Schemeless addresses try `https://` first and
    /// fall back to `http://` (which ATS only permits for local-network hosts).
    func connect(to rawURL: String) async throws -> ServerConnection {
        let candidates = try Self.candidateURLs(for: rawURL)
        let diagnostics = DiagnosticsHub.shared
        diagnostics.record(.serverConnectStarted)
        let connectInterval = diagnostics.beginInterval("ServerConnect")

        var lastError: GusError?
        for url in candidates {
            let client = JellyfinClientFactory.makeClient(url: url)
            do {
                let response = try await client.send(Paths.getPublicSystemInfo)
                let baseURL = Self.followRedirect(
                    responseURL: (response.response as? HTTPURLResponse)?.url,
                    fallback: url
                )
                diagnostics.endInterval("ServerConnect", connectInterval)
                diagnostics.record(.serverConnectSucceeded)

                let info = response.value
                let server = ServerConnection(
                    id: info.id ?? baseURL.absoluteString,
                    name: info.serverName ?? baseURL.host ?? "Jellyfin",
                    url: baseURL
                )
                upsert(server: server)
                return server
            } catch {
                let gusError = GusError(from: error)
                guard !gusError.isCancellation else {
                    diagnostics.endInterval("ServerConnect", connectInterval)
                    throw error
                }
                lastError = gusError
            }
        }

        diagnostics.endInterval("ServerConnect", connectInterval)
        diagnostics.record(.serverConnectFailed)
        let detail = lastError?.localizedDescription ?? ""
        logger.error("Connect failed: \(detail, privacy: .public)")
        throw ConnectError.unreachable(detail)
    }

    // MARK: - Sign in

    func signIn(to server: ServerConnection, username: String, password: String) async throws {
        let client = JellyfinClientFactory.makeClient(url: server.url)

        let result: AuthenticationResult
        do {
            result = try await client.signIn(username: username, password: password)
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { throw error }
            logger.error("Sign in failed: \(gusError.localizedDescription, privacy: .public)")
            throw ConnectError.authenticationFailed
        }

        try completeSignIn(to: server, client: client, result: result, fallbackName: username)
    }

    func signIn(to server: ServerConnection, quickConnectSecret: String) async throws {
        let client = JellyfinClientFactory.makeClient(url: server.url)

        let result: AuthenticationResult
        do {
            result = try await client.signIn(quickConnectSecret: quickConnectSecret)
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { throw error }
            logger.error("Quick Connect sign in failed: \(gusError.localizedDescription, privacy: .public)")
            throw ConnectError.authenticationFailed
        }

        try completeSignIn(
            to: server,
            client: client,
            result: result,
            fallbackName: String(localized: "Jellyfin User", comment: "Fallback display name for a signed-in Jellyfin user")
        )
    }

    // MARK: - Sign out

    func signOut() {
        signOutCurrentUser()
    }

    func signOutCurrentUser() {
        guard let session = currentSession else {
            lastSessionAccount = nil
            return
        }

        #if DEBUG
            guard !Self.isDebugPreviewSession(session) else {
                currentSession = nil
                return
            }
        #endif

        let credential = SessionCredential(user: session.user)
        let client = session.client
        Task { try? await client.signOut() } // best-effort server-side revoke
        clearAccountData(server: session.server, user: session.user)
        tokenStore.deleteToken(for: credential)
        tokenStore.deleteToken(account: credential.legacyAccount)
        users.removeAll { $0.id == session.user.id && $0.serverID == session.user.serverID }
        serverStore.saveUsers(users)
        lastSessionAccount = nil
        currentSession = nil
    }

    #if DEBUG
        private static func isDebugPreviewSession(_ session: SessionStore) -> Bool {
            session.server.id == debugPreviewServerID && session.user.id == debugPreviewUserID
        }
    #endif

    // MARK: - Persistence helpers

    private func upsert(server: ServerConnection) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        serverStore.saveServers(servers)
    }

    private func upsert(user: StoredUser) {
        // Match on (id, serverID) — the same Jellyfin user id can exist on two servers,
        // and sign-out removes on the same compound key.
        if let index = users.firstIndex(where: { $0.id == user.id && $0.serverID == user.serverID }) {
            users[index] = user
        } else {
            users.append(user)
        }
        serverStore.saveUsers(users)
    }

    private func clearCurrentAccountDataIfNeeded(replacingWith user: StoredUser, on server: ServerConnection) {
        guard let session = currentSession else { return }
        guard session.user != user || session.server.id != server.id else { return }
        clearAccountData(server: session.server, user: session.user)
    }

    private func clearAccountData(server: ServerConnection, user: StoredUser) {
        let scope = AccountScope(serverID: server.id, userID: user.id)
        accountCleanup.clearSearchIndex(server.id, user.id)
        accountCleanup.clearTopShelf()
        accountCleanup.clearBookState(scope)
        accountCleanup.clearDownloads(scope)
        accountCleanup.clearWatchCredential(server, user)
    }

    private func completeSignIn(
        to server: ServerConnection,
        client: JellyfinClient,
        result: AuthenticationResult,
        fallbackName: String
    ) throws {
        guard let token = result.accessToken,
              let userDto = result.user,
              let userID = userDto.id
        else { throw ConnectError.authenticationFailed }

        let user = StoredUser(
            id: userID,
            name: userDto.name ?? fallbackName,
            serverID: server.id,
            primaryImageTag: userDto.primaryImageTag
        )

        tokenStore.setToken(token, for: SessionCredential(user: user))
        upsert(server: server)
        upsert(user: user)
        lastSessionAccount = SessionCredential(user: user).account

        // SDK sign-in methods already set the access token on this client's configuration.
        clearCurrentAccountDataIfNeeded(replacingWith: user, on: server)
        currentSession = SessionStore(client: client, user: user, server: server)
        publishSessionToWatch(server: server, user: user, token: token)
        logger.info("Signed in user \(user.name, privacy: .private)")
    }

    private func tokenMigratingLegacyAccountIfNeeded(for user: StoredUser) -> String? {
        let credential = SessionCredential(user: user)
        if let token = tokenStore.token(for: credential) {
            return token
        }

        guard credential.providerKind == .jellyfin,
              let legacyToken = tokenStore.token(account: credential.legacyAccount)
        else {
            return nil
        }

        tokenStore.setToken(legacyToken, for: credential)
        tokenStore.deleteToken(account: credential.legacyAccount)
        return legacyToken
    }

    // MARK: - URL helpers

    nonisolated static func normalizeURL(_ raw: String) throws -> URL {
        var string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { throw ConnectError.invalidURL }

        if !string.contains("://") { string = "http://" + string }
        while string.hasSuffix("/") {
            string.removeLast()
        }

        guard let url = URL(string: string), url.host != nil else { throw ConnectError.invalidURL }
        return url
    }

    /// Connection attempts for a user-entered address. An explicit scheme is honored
    /// as-is; schemeless input is tried as `https://` then `http://`.
    nonisolated static func candidateURLs(for raw: String) throws -> [URL] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = try normalizeURL(trimmed)
        guard !trimmed.contains("://") else { return [url] }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        guard let httpsURL = components?.url else { return [url] }
        return [httpsURL, url]
    }

    /// Recovers the server base URL if the public-info request was redirected.
    private nonisolated static func followRedirect(responseURL: URL?, fallback: URL) -> URL {
        guard let responseURL else { return fallback }
        let absolute = responseURL.absoluteString
        if let range = absolute.range(of: "/System/Info/Public", options: [.caseInsensitive]) {
            let baseString = String(absolute[..<range.lowerBound])
            if let base = URL(string: baseString), base.host != nil {
                return base
            }
        }
        return fallback
    }
}
