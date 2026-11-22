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
    #if os(iOS)
        let audioPlayback = AudioPlaybackCoordinator()
    #endif
    private var sessionRestore: Task<Void, Never>?
    private var clearedSurfacesAfterMissingRestore = false

    struct ReauthenticationRequest: Equatable {
        let server: ServerConnection
        let user: StoredUser
    }

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

    @MainActor struct AccountCleanupActions {
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
                OfflineDownloadStore.shared.deleteAll(serverID: scope.serverID, userID: scope.userID)
            },
            clearWatchCredential: { server, user in
                #if os(iOS) && canImport(WatchConnectivity)
                    WatchSessionRelay.shared.clear(server: server, user: user)
                #endif
            }
        )
    }

    private static let lastSessionAccountDefaultsKey = "dev.ericslutz.gus.lastSignedInSessionAccount"
    #if DEBUG
        private static let debugPreviewServerID = "debug-preview-server"
        private static let debugPreviewUserID = "debug-preview-user"
    #endif

    private let serverStore: ServerStore
    private let tokenStore: TokenStore
    private let userDefaults: UserDefaults
    private let accountCleanup: AccountCleanupActions
    private let clientFactory: @MainActor (URL, String?, SessionAuthentication?) -> JellyfinClient
    private let logger = Logger(category: .appModel)
    private var activationGeneration = UUID()
    private var authenticationGeneration = UUID()
    private var retiringSessions: [SessionLease: Task<Void, Never>] = [:]
    private var transitionCount = 0
    var isTransitioning: Bool {
        transitionCount > 0
    }

    private(set) var servers: [ServerConnection] = []
    private(set) var users: [StoredUser] = []
    private(set) var currentSession: SessionStore? {
        didSet {
            if oldValue !== currentSession {
                oldValue?.invalidate()
            }
        }
    }

    private(set) var reauthentication: ReauthenticationRequest?

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
    }

    private static func loadLastSessionAccount(
        from userDefaults: UserDefaults
    ) -> String? {
        userDefaults.string(forKey: lastSessionAccountDefaultsKey)
    }

    init(
        serverStore: ServerStore = .shared,
        tokenStore: TokenStore = KeychainStore.shared,
        userDefaults: UserDefaults = .standard,
        accountCleanup: AccountCleanupActions = .live,
        clientFactory: @escaping @MainActor (URL, String?, SessionAuthentication?) -> JellyfinClient = { url, token, authentication in
            JellyfinClientFactory.makeClient(url: url, accessToken: token, delegate: authentication)
        }
    ) {
        self.serverStore = serverStore
        self.tokenStore = tokenStore
        self.userDefaults = userDefaults
        self.accountCleanup = accountCleanup
        self.clientFactory = clientFactory
        servers = serverStore.loadServers()
        users = serverStore.loadUsers()
        lastSessionAccount = Self.loadLastSessionAccount(from: userDefaults)
    }

    func synchronizeProfile(from session: SessionStore) {
        guard currentSession === session, let profile = session.profile.profile,
              profile.id == session.user.id else { return }
        let previousUser = session.user
        session.user.name = profile.name ?? session.user.name
        session.user.primaryImageTag = profile.primaryImageTag
        upsert(user: session.user)
        if previousUser != session.user, let token = storedToken(for: session.user) {
            publishSessionToWatch(server: session.server, user: session.user, token: token)
        }
    }

    // MARK: - Launch restore

    /// Voice and Shortcuts may enter while a scene is restoring its session or while the user is switching profiles.
    func restoreForIntentIfNeeded() async {
        if let sessionRestore {
            await sessionRestore.value
            return
        }
        guard currentSession == nil, !isTransitioning else { return }
        #if os(iOS)
            reloadSavedAccountsForSessionRestore()
        #endif
        await restoreLastSession()
    }

    /// Silently restores the last session from the Keychain token + persisted stores.
    func restoreLastSession() async {
        defer {
            if currentSession == nil, self === Self.shared, !clearedSurfacesAfterMissingRestore {
                // The saved account or Keychain item may disappear while the host
                // is closed. A failed cold restore must retire the old glance.
                clearedSurfacesAfterMissingRestore = true
                SessionStore.clearPersonalSurfaces()
            }
        }
        guard currentSession == nil,
              let account = lastSessionAccount,
              let user = users.first(where: { SessionCredential(user: $0).account == account })
        else { return }

        if let sessionRestore {
            await sessionRestore.value
            return
        }
        let restore = Task {
            do {
                try await restoreSavedSession(for: user)
            } catch {
                logger.error("Last-session restore failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        sessionRestore = restore
        await restore.value
        sessionRestore = nil
    }

    #if os(iOS)
        func reloadSavedAccountsForSessionRestore() {
            guard currentSession == nil, lastSessionAccount == nil || users.isEmpty else { return }
            servers = serverStore.loadServers()
            users = serverStore.loadUsers()
            lastSessionAccount = Self.loadLastSessionAccount(from: userDefaults)
        }
    #endif

    /// Restores a saved user's session when its server and Keychain token are present.
    func restoreSavedSession(for user: StoredUser) async throws {
        guard let server = server(for: user) else { throw SessionSwitchError.missingServer }
        guard let token = storedToken(for: user) else {
            throw SessionSwitchError.missingToken
        }

        guard await activateSession(server: server, user: user, token: token) else { throw GusError.cancelled }
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
    func adoptHandedOffSession(server: ServerConnection, user: StoredUser, token: String) async {
        guard user.serverID == server.id, user.providerKind == server.providerKind, !token.isEmpty else { return }
        tokenStore.setToken(token, for: SessionCredential(user: user))
        upsert(server: server)
        upsert(user: user)

        if let currentSession {
            guard currentSession.lease.credential == SessionCredential(user: user) else { return }
            if !currentSession.isActive || currentSession.client.accessToken != token || currentSession.server.url != server.url {
                _ = await activateSession(server: server, user: user, token: token)
                return
            }
            currentSession.user = user
            return
        }
        guard await activateSession(server: server, user: user, token: token) else { return }
        logger.info("Adopted handed-off session for user \(user.name, privacy: .private)")
    }

    func switchToStoredUser(_ user: StoredUser) async throws {
        if let currentSession, currentSession.isActive, currentSession.lease.credential == SessionCredential(user: user),
           currentSession.server.url == server(for: user)?.url,
           currentSession.client.accessToken == storedToken(for: user)
        {
            return
        }
        try await restoreSavedSession(for: user)
    }

    func clearHandedOffSession(serverID: String, userID: String) async {
        let scope = AccountScope(serverID: serverID, userID: userID)
        GusIntelligencePreferences.delete(scope: scope, defaults: userDefaults)
        GusLibraryIntelligence.deleteCatalog(scope: scope)
        BrowseSnapshotCache.delete(scope: scope)
        SearchHistoryStore.delete(scope: scope, defaults: userDefaults)
        guard let user = users.first(where: { $0.id == userID && $0.serverID == serverID }) else {
            let credential = SessionCredential(serverID: serverID, userID: userID)
            tokenStore.deleteToken(for: credential)
            return
        }

        let credential = SessionCredential(user: user)
        tokenStore.deleteToken(for: credential)
        users.removeAll { $0.id == userID && $0.serverID == serverID }
        serverStore.saveUsers(users)

        guard currentSession?.lease.credential == credential else {
            if lastSessionAccount == credential.account {
                lastSessionAccount = nil
            }
            return
        }

        activationGeneration = UUID()
        authenticationGeneration = UUID()
        let generation = activationGeneration
        await retireCurrentSession()
        guard generation == activationGeneration else { return }
        lastSessionAccount = nil
        reauthentication = nil
        currentSession = nil
    }

    func hasStoredToken(for user: StoredUser) -> Bool {
        storedToken(for: user) != nil
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
        func connectToLocalDemoServer() async -> String? {
            do {
                let address = ProcessInfo.processInfo.environment["GUS_DEMO_URL"] ?? "http://localhost:8096"
                guard let url = URL(string: address), url.scheme == "http",
                      ["localhost", "127.0.0.1", "::1"].contains(url.host ?? ""),
                      url.user == nil, url.password == nil else { return String(localized: "The demo server must use a local HTTP address.") }
                let server = try await connect(to: address)
                let username = ProcessInfo.processInfo.environment["GUS_DEMO_USERNAME"] ?? "gus"
                let password = ProcessInfo.processInfo.environment["GUS_DEMO_PASSWORD"] ?? "playa-demo"
                try await signIn(to: server, username: username, password: password)
                return nil
            } catch {
                guard !GusError(from: error).isCancellation else { return nil }
                logger.error("Demo server connect failed: \(error.localizedDescription, privacy: .private)")
                return error.localizedDescription
            }
        }

        /// Installs an in-memory signed-in session for simulator screenshots and UI tests.
        /// This intentionally avoids `ServerStore`, `TokenStore`, and `UserDefaults` writes.
        func installDebugPreviewSession() async {
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

            let session = SessionStore(
                client: JellyfinClientFactory.makeClient(url: server.url, accessToken: "debug-preview-token"),
                user: user,
                server: server,
                historyDefaults: userDefaults
            )
            activationGeneration = UUID()
            let generation = activationGeneration
            await retireCurrentSession()
            guard generation == activationGeneration else { return }
            installSession(session)
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
                try Task.checkCancellation()
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
        logger.error("Connect failed: \(detail, privacy: .private)")
        throw ConnectError.unreachable(detail)
    }

    /// Only authentication rejection should suggest changing credentials.
    static func signInError(from error: Error) -> any Error {
        let mapped = GusError(from: error)
        return mapped == .unauthorized ? ConnectError.authenticationFailed : mapped
    }

    // MARK: - Sign in

    func signIn(to server: ServerConnection, username: String, password: String) async throws {
        authenticationGeneration = UUID()
        let generation = authenticationGeneration
        let client = clientFactory(server.url, nil, nil)

        let result: AuthenticationResult
        do {
            result = try await client.signIn(username: username, password: password)
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { throw error }
            logger.error("Sign in failed: \(gusError.localizedDescription, privacy: .private)")
            throw Self.signInError(from: error)
        }

        try Task.checkCancellation()
        guard generation == authenticationGeneration else { throw GusError.cancelled }
        try await completeSignIn(to: server, result: result, fallbackName: username)
    }

    func signIn(to server: ServerConnection, quickConnectSecret: String) async throws {
        authenticationGeneration = UUID()
        let generation = authenticationGeneration
        let client = clientFactory(server.url, nil, nil)

        let result: AuthenticationResult
        do {
            result = try await client.signIn(quickConnectSecret: quickConnectSecret)
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { throw error }
            logger.error("Quick Connect sign in failed: \(gusError.localizedDescription, privacy: .private)")
            throw Self.signInError(from: error)
        }

        try Task.checkCancellation()
        guard generation == authenticationGeneration else { throw GusError.cancelled }
        try await completeSignIn(
            to: server,
            result: result,
            fallbackName: String(localized: "Jellyfin User", comment: "Fallback display name for a signed-in Jellyfin user")
        )
    }

    // MARK: - Sign out

    func signOut() async {
        await signOutCurrentUser()
    }

    func signOutCurrentUser() async {
        activationGeneration = UUID()
        authenticationGeneration = UUID()
        let generation = activationGeneration
        guard let session = currentSession else {
            if let reauthentication {
                removeAccount(server: reauthentication.server, user: reauthentication.user)
                self.reauthentication = nil
            }
            lastSessionAccount = nil
            return
        }

        await retireCurrentSession()
        guard generation == activationGeneration else { return }

        #if DEBUG
            guard !Self.isDebugPreviewSession(session) else {
                currentSession = nil
                return
            }
        #endif

        let client = session.client
        Task { try? await client.signOut() } // best-effort server-side revoke
        removeAccount(server: session.server, user: session.user)
        lastSessionAccount = nil
        reauthentication = nil
        currentSession = nil
    }

    /// Expiry locks this account's content until reauthentication without deleting its
    /// downloads, checkpoints, book locations, or pending mutation journals.
    func recoverExpiredSession(lease: SessionLease) {
        guard let session = currentSession, session.lease == lease else { return }
        activationGeneration = UUID()
        authenticationGeneration = UUID()
        beginRetirement(of: session)
        reauthentication = ReauthenticationRequest(server: session.server, user: session.user)
        tokenStore.deleteToken(for: lease.credential)
        clearAccountData(server: session.server, user: session.user, preservingDownloads: true)
        currentSession = nil
    }

    /// Background transfers can finish after credential rotation. Probe the active
    /// credential rather than interpreting an old transfer's 401 as current expiry.
    func verifyAuthentication(for scope: AccountScope) async {
        guard let session = currentSession, session.references.scope == scope else { return }
        do {
            _ = try await session.client.send(Paths.getUserByID(userID: session.user.id))
        } catch {
            guard currentSession?.lease == session.lease else { return }
            GusError(from: error).handleIfUnauthorized(session: session)
        }
    }

    private func removeAccount(server: ServerConnection, user: StoredUser) {
        #if !os(watchOS)
            GusAudiobookBookmarks(credential: SessionCredential(user: user), defaults: userDefaults).forget()
        #endif
        SystemSurfacePreferences(credential: SessionCredential(user: user), defaults: userDefaults).forget()
        clearAccountData(server: server, user: user)
        let scope = AccountScope(serverID: server.id, userID: user.id)
        GusIntelligencePreferences.delete(scope: scope, defaults: userDefaults)
        GusLibraryIntelligence.deleteCatalog(scope: scope)
        BrowseSnapshotCache.delete(scope: scope)
        SearchHistoryStore.delete(scope: scope, defaults: userDefaults)
        tokenStore.deleteToken(for: SessionCredential(user: user))
        users.removeAll { SessionCredential(user: $0) == SessionCredential(user: user) }
        serverStore.saveUsers(users)
    }

    private func activateSession(server: ServerConnection, user: StoredUser, token: String) async -> Bool {
        activationGeneration = UUID()
        authenticationGeneration = UUID()
        let generation = activationGeneration
        await retireCurrentSession()
        guard generation == activationGeneration else { return false }
        clearCurrentAccountDataIfNeeded(replacingWith: user)
        let authentication = SessionAuthentication(userID: user.id)
        let client = clientFactory(server.url, token, authentication)
        let session = SessionStore(client: client, user: user, server: server, historyDefaults: userDefaults)
        authentication.bind(to: session)
        installSession(session)
        lastSessionAccount = SessionCredential(user: user).account
        return true
    }

    /// Invalidation synchronously checkpoints players and queues terminal reports on
    /// the originating transport. All outgoing queues get one shared five-second
    /// grace window before another account can become visible.
    private func beginRetirement(of session: SessionStore) {
        guard retiringSessions[session.lease] == nil else { return }
        session.invalidate()
        retiringSessions[session.lease] = Task { @MainActor [weak self] in
            try? await PlaybackDeadline.run(for: .seconds(5)) {
                await session.playbackReports.flush()
            }
            self?.retiringSessions[session.lease] = nil
        }
    }

    private func retireCurrentSession() async {
        transitionCount += 1
        defer { transitionCount -= 1 }
        if let currentSession {
            beginRetirement(of: currentSession)
        }
        let pending = Array(retiringSessions.values)
        for task in pending {
            await task.value
        }
    }

    /// All authenticated activation paths install the same lease-bound recovery hook.
    private func installSession(_ session: SessionStore) {
        session.bindRecovery(to: self)
        currentSession = session
        clearedSurfacesAfterMissingRestore = false
        if self === Self.shared {
            session.systemPrivacyDidChange(restoring: true)
        }
        reauthentication = nil
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

    private func clearCurrentAccountDataIfNeeded(replacingWith user: StoredUser) {
        guard let session = currentSession, SessionCredential(user: session.user) != SessionCredential(user: user) else { return }
        clearAccountData(server: session.server, user: session.user, preservingDownloads: true)
    }

    private func clearAccountData(server: ServerConnection, user: StoredUser, preservingDownloads: Bool = false) {
        let scope = AccountScope(serverID: server.id, userID: user.id)
        accountCleanup.clearSearchIndex(server.id, user.id)
        accountCleanup.clearTopShelf()
        if !preservingDownloads {
            #if !os(watchOS)
                try? GusRecordingJournal(scope: scope).clear()
            #endif
            accountCleanup.clearBookState(scope)
            OfflinePlaybackProgressStore.shared.deleteCheckpoints(scope: scope)
            accountCleanup.clearDownloads(scope)
        }
        accountCleanup.clearWatchCredential(server, user)
        JellyfinClientFactory.urlCache.removeAllCachedResponses()
    }

    private func completeSignIn(
        to server: ServerConnection,
        result: AuthenticationResult,
        fallbackName: String
    ) async throws {
        guard let token = result.accessToken,
              let userDto = result.user,
              let userID = userDto.id
        else { throw GusError(from: URLError(.cannotParseResponse)) }

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

        guard await activateSession(server: server, user: user, token: token) else { throw GusError.cancelled }
        publishSessionToWatch(server: server, user: user, token: token)
        logger.info("Signed in user \(user.name, privacy: .private)")
    }

    private func storedToken(for user: StoredUser) -> String? {
        tokenStore.token(for: SessionCredential(user: user))
    }

    // MARK: - URL helpers

    nonisolated static func normalizeURL(_ raw: String) throws -> URL {
        var string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { throw ConnectError.invalidURL }

        if !string.contains("://") {
            string = "http://" + string
        }
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
