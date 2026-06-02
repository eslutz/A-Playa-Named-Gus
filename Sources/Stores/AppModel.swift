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

    enum ConnectError: LocalizedError {
        case invalidURL
        case unreachable(String)
        case authenticationFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Enter a valid server address."
            case let .unreachable(detail):
                return "Couldn't reach that server. \(detail)"
            case .authenticationFailed:
                return "Sign in failed. Check your username and password."
            }
        }
    }

    private static let lastUserDefaultsKey = "dev.ericslutz.gus.lastSignedInUserID"

    private let serverStore = ServerStore.shared
    private let keychain = KeychainStore.shared
    private let logger = Logger(subsystem: "dev.ericslutz.gus", category: "AppModel")

    private(set) var servers: [ServerConnection] = []
    private(set) var users: [StoredUser] = []
    var currentSession: SessionStore?

    var lastSignedInUserID: String? {
        didSet { UserDefaults.standard.set(lastSignedInUserID, forKey: Self.lastUserDefaultsKey) }
    }

    init() {
        servers = serverStore.loadServers()
        users = serverStore.loadUsers()
        lastSignedInUserID = UserDefaults.standard.string(forKey: Self.lastUserDefaultsKey)
    }

    // MARK: - Launch restore

    /// Silently restores the last session from the Keychain token + persisted stores.
    func restoreLastSession() {
        guard currentSession == nil,
              let userID = lastSignedInUserID,
              let user = users.first(where: { $0.id == userID }),
              let server = servers.first(where: { $0.id == user.serverID }),
              let token = keychain.token(for: SessionCredential(user: user))
        else { return }

        let client = JellyfinClientFactory.makeClient(url: server.url, accessToken: token)
        currentSession = SessionStore(client: client, user: user, server: server)
        logger.info("Restored session for user \(user.name, privacy: .public)")
    }

    // MARK: - Connect

    /// Normalizes a URL, queries public system info, follows any redirect, and persists
    /// the resulting `ServerConnection`.
    func connect(to rawURL: String) async throws -> ServerConnection {
        let url = try Self.normalizeURL(rawURL)
        let client = JellyfinClientFactory.makeClient(url: url)

        let info: PublicSystemInfo
        let baseURL: URL
        do {
            let response = try await client.send(Paths.getPublicSystemInfo)
            info = response.value
            baseURL = Self.followRedirect(
                responseURL: (response.response as? HTTPURLResponse)?.url,
                fallback: url
            )
        } catch {
            logger.error("Connect failed: \(error.localizedDescription, privacy: .public)")
            throw ConnectError.unreachable(error.localizedDescription)
        }

        let server = ServerConnection(
            id: info.id ?? baseURL.absoluteString,
            name: info.serverName ?? baseURL.host ?? "Jellyfin",
            url: baseURL
        )
        upsert(server: server)
        return server
    }

    // MARK: - Sign in

    func signIn(to server: ServerConnection, username: String, password: String) async throws {
        let client = JellyfinClientFactory.makeClient(url: server.url)

        let result: AuthenticationResult
        do {
            result = try await client.signIn(username: username, password: password)
        } catch {
            logger.error("Sign in failed: \(error.localizedDescription, privacy: .public)")
            throw ConnectError.authenticationFailed
        }

        guard let token = result.accessToken,
              let userDto = result.user,
              let userID = userDto.id
        else { throw ConnectError.authenticationFailed }

        let user = StoredUser(
            id: userID,
            name: userDto.name ?? username,
            serverID: server.id,
            primaryImageTag: userDto.primaryImageTag
        )

        keychain.setToken(token, for: SessionCredential(user: user))
        upsert(server: server)
        upsert(user: user)
        lastSignedInUserID = userID

        // `signIn` already set the access token on this client's configuration.
        currentSession = SessionStore(client: client, user: user, server: server)
        logger.info("Signed in user \(user.name, privacy: .public)")
    }

    // MARK: - Sign out

    func signOut() {
        if let session = currentSession {
            let credential = SessionCredential(user: session.user)
            let client = session.client
            Task { try? await client.signOut() } // best-effort server-side revoke
            keychain.deleteToken(for: credential)
        }
        lastSignedInUserID = nil
        currentSession = nil
    }

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
        if let index = users.firstIndex(where: { $0.id == user.id }) {
            users[index] = user
        } else {
            users.append(user)
        }
        serverStore.saveUsers(users)
    }

    // MARK: - URL helpers

    static func normalizeURL(_ raw: String) throws -> URL {
        var string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { throw ConnectError.invalidURL }

        if !string.contains("://") { string = "http://" + string }
        while string.hasSuffix("/") { string.removeLast() }

        guard let url = URL(string: string), url.host != nil else { throw ConnectError.invalidURL }
        return url
    }

    /// Recovers the server base URL if the public-info request was redirected.
    private static func followRedirect(responseURL: URL?, fallback: URL) -> URL {
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
