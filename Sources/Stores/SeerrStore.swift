import Foundation
import Observation

/// One device's Seerr session, scoped to the active Jellyfin server and account.
/// Passwords never leave the sign-in operation; only session cookies enter Keychain.
@MainActor @Observable
final class SeerrStore {
    enum ConnectionState { case disconnected, restoring, connected, expired, offline }
    private(set) var state: ConnectionState = .disconnected
    private(set) var client: SeerrClient?
    private(set) var user: SeerrUser?
    private(set) var serverURL: URL?
    private(set) var revision = UUID()
    var errorMessage: String?
    let scope: AccountScope
    private let directory: URL
    private let clientFactory: @Sendable (URL, [SeerrSessionCookie]) throws -> SeerrClient
    private let defaults: UserDefaults
    private let tokens: any TokenStore
    private var restored = false
    private var blockedTitles = Set<String>()
    @ObservationIgnored private var requestDrafts: [String: SeerrRequestDraft] = [:]
    private var pendingRequests: [String: SeerrPendingRequest] = [:]
    private var pendingSupport = Set<String>()

    var restrictionRevision: String {
        (defaults.string(forKey: ContentRatingGate.limitDefaultsKey) ?? "off") + ":" + String(defaults.bool(forKey: ContentRatingGate.hideUnratedDefaultsKey))
    }

    var isConnected: Bool {
        state == .connected && client != nil && user != nil
    }

    private var credentialAccount: String {
        "seerr:\(scope.serverID):\(scope.userID)"
    }

    private var fileURL: URL {
        directory.appendingPathComponent(scope.storageKey + ".json")
    }

    init(scope: AccountScope, directory: URL = AppStorageLocation.appDirectory().appendingPathComponent("Seerr", isDirectory: true), tokens: any TokenStore = KeychainStore.shared, userDefaults: UserDefaults = .standard, clientFactory: @escaping @Sendable (URL, [SeerrSessionCookie]) throws -> SeerrClient = { try SeerrClient(baseURL: $0, cookies: $1) }) {
        self.scope = scope
        self.directory = directory
        self.tokens = tokens
        self.defaults = userDefaults
        self.clientFactory = clientFactory
    }

    func restore() async {
        guard !restored else { return }
        restored = true
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(SavedConnection.self, from: data), saved.scope == scope
        else { return }
        serverURL = saved.url
        pendingRequests = saved.pendingRequests ?? [:]
        pendingSupport = Set(saved.pendingSupport ?? [])
        guard let secret = tokens.token(account: credentialAccount),
              let cookieData = secret.data(using: .utf8),
              let cookies = try? JSONDecoder().decode([SeerrSessionCookie].self, from: cookieData)
        else { state = .expired; return }
        let expected = revision
        state = .restoring
        defer {
            if expected == revision, state == .restoring {
                state = .offline
                restored = false
            }
        }
        do {
            let candidate = try clientFactory(saved.url, cookies)
            _ = try await candidate.validateServer()
            let account = try await candidate.me()
            guard account.id == saved.seerrUserID else { throw SeerrClientError.unauthorized }
            guard expected == revision, !Task.isCancelled else { return }
            try await persistCookies(candidate)
            guard expected == revision, !Task.isCancelled else { return }
            client = candidate
            user = account
            state = .connected
            errorMessage = nil
        } catch {
            guard expected == revision, !Task.isCancelled else { return }
            handle(error)
            if state != .expired {
                state = .offline
            }
        }
    }

    /// Commit a new connection only after the server confirms the authenticated user.
    func connect(client candidate: SeerrClient, user account: SeerrUser, expectedRevision: UUID? = nil) async throws {
        let expected = expectedRevision ?? revision
        guard expected == revision else { throw CancellationError() }
        let cookies = try await encodedCookies(candidate)
        try Task.checkCancellation()
        guard expected == revision else { throw CancellationError() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previousConnection = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(SavedConnection.self, from: $0) }
        let samePrincipal = previousConnection?.url == candidate.baseURL && previousConnection?.seerrUserID == account.id
        let saved = SavedConnection(
            scope: scope,
            url: candidate.baseURL,
            seerrUserID: account.id,
            pendingRequests: samePrincipal ? previousConnection?.pendingRequests : nil,
            pendingSupport: samePrincipal ? previousConnection?.pendingSupport : nil
        )
        let data = try JSONEncoder().encode(saved)
        let previousToken = tokens.token(account: credentialAccount)
        do {
            tokens.setToken(cookies, account: credentialAccount)
            guard tokens.token(account: credentialAccount) == cookies else { throw SeerrConnectionError.secureStorage }
            try data.write(to: fileURL, options: .atomic)
        } catch {
            if let previousToken {
                tokens.setToken(previousToken, account: credentialAccount)
            } else {
                tokens.deleteToken(account: credentialAccount)
            }
            throw error
        }
        let previous = client
        if previous !== candidate {
            previous?.invalidateSession()
        }
        revision = UUID()
        blockedTitles = []
        requestDrafts = [:]
        pendingRequests = saved.pendingRequests ?? [:]
        pendingSupport = Set(saved.pendingSupport ?? [])
        client = candidate
        user = account
        serverURL = candidate.baseURL
        restored = true
        state = .connected
        errorMessage = nil
        if previous !== candidate {
            Task { await previous?.clearSession() }
        }
    }

    func retryRestore() async {
        restored = false; await restore()
    }

    func requireClient() throws -> SeerrClient {
        guard isConnected, let client else { throw SeerrConnectionError.signInRequired }
        return client
    }

    func refreshUser() async throws {
        let expected = revision
        let client = try requireClient()
        let current = try await client.me()
        guard expected == revision, !Task.isCancelled else { throw CancellationError() }
        guard current.id == user?.id else {
            handle(SeerrClientError.unauthorized)
            throw SeerrClientError.unauthorized
        }
        user = current
        try await persistCookies(client)
    }

    /// Account replacement invalidates in-flight work while preserving this account's saved connection.
    func deactivate() {
        let previous = client
        previous?.invalidateSession()
        revision = UUID()
        client = nil
        user = nil
        requestDrafts = [:]
        restored = false
        state = .disconnected
        Task { await previous?.clearSession() }
    }

    func disconnect() {
        let previous = client
        previous?.invalidateSession()
        revision = UUID()
        client = nil
        user = nil
        serverURL = nil
        blockedTitles = []
        requestDrafts = [:]
        pendingRequests = [:]
        pendingSupport = []
        state = .disconnected
        errorMessage = nil
        tokens.deleteToken(account: credentialAccount)
        try? FileManager.default.removeItem(at: fileURL)
        // Forget this device locally; no unowned network operation may outlive its session.
        Task { await previous?.clearSession() }
    }

    func handle(_ error: Error) {
        guard !(error is CancellationError) else { return }
        errorMessage = error.localizedDescription
        if case SeerrClientError.unauthorized = error {
            let previous = client
            previous?.invalidateSession()
            Task { await previous?.clearSession() }
            revision = UUID()
            client = nil
            user = nil
            state = .expired
            tokens.deleteToken(account: credentialAccount)
        }
    }

    private func titleKey(type: SeerrMediaType?, id: Int) -> String {
        "\(type?.rawValue ?? "unknown"):\(id)"
    }

    func requestDraft(for title: SeerrTitle) -> SeerrRequestDraft {
        let key = titleKey(type: title.mediaType, id: title.id)
        if let draft = requestDrafts[key] {
            return draft
        }
        let draft = SeerrRequestDraft(title: title)
        if let pending = pendingRequests[key] {
            draft.restoreAttempt(pending, store: self)
        }
        requestDrafts[key] = draft
        return draft
    }

    func finishRequestDraft(title: SeerrTitle) {
        requestDrafts.removeValue(forKey: titleKey(type: title.mediaType, id: title.id))
    }

    func beginRequestAttempt(payload: SeerrRequestPayload, baselineIDs: Set<Int>) throws {
        let key = titleKey(type: payload.mediaType, id: payload.mediaId)
        guard pendingRequests[key] == nil else { throw SeerrClientError.mutationOutcomeUnknown }
        pendingRequests[key] = SeerrPendingRequest(payload: payload, baselineIDs: baselineIDs)
        do { try persistJournal() } catch { pendingRequests.removeValue(forKey: key); throw error }
    }

    func completeRequestAttempt(payload: SeerrRequestPayload) {
        pendingRequests.removeValue(forKey: titleKey(type: payload.mediaType, id: payload.mediaId))
        try? persistJournal()
    }

    func hasPendingSupportMutation(key: String) -> Bool {
        pendingSupport.contains(key)
    }

    func beginSupportMutation(key: String) throws {
        guard !pendingSupport.contains(key) else { throw SeerrClientError.mutationOutcomeUnknown }
        pendingSupport.insert(key)
        do { try persistJournal() } catch { pendingSupport.remove(key); throw error }
    }

    func completeSupportMutation(key: String) {
        pendingSupport.remove(key)
        try? persistJournal()
    }

    private func persistJournal() throws {
        guard let serverURL, let user else { throw SeerrConnectionError.signInRequired }
        let value = SavedConnection(
            scope: scope,
            url: serverURL,
            seerrUserID: user.id,
            pendingRequests: pendingRequests,
            pendingSupport: Array(pendingSupport).sorted()
        )
        try JSONEncoder().encode(value).write(to: fileURL, options: .atomic)
    }

    func recordBlock(mediaType: SeerrMediaType, id: Int, blocked: Bool) {
        let key = "\(mediaType.rawValue):\(id)"
        let changed = blocked ? blockedTitles.insert(key).inserted : blockedTitles.remove(key) != nil
        if changed {
            requestDrafts = [:]
            revision = UUID()
        }
    }

    func admits(_ title: SeerrTitle) -> Bool {
        guard !blockedTitles.contains("\(title.mediaType?.rawValue ?? "unknown"):\(title.id)") else { return false }
        if title.mediaType == .person {
            return true
        }
        guard title.mediaInfo?.status != .blocklisted else { return false }
        let item = MediaItem(officialRating: title.certification, type: title.mediaType == .tv ? .series : .movie)
        return ContentRatingGate.admitsStored(item, userDefaults: defaults)
    }

    /// Catalog endpoints omit certifications; restrictions require the richer title before presentation.
    func admitted(_ titles: [SeerrTitle]) async throws -> [SeerrTitle] {
        let expected = revision
        let restrictions = restrictionRevision
        let restriction = ContentRatingGate.storedLimit(userDefaults: defaults)
        var result: [SeerrTitle] = []
        for title in titles {
            try Task.checkCancellation()
            guard expected == revision, restrictions == restrictionRevision else { throw CancellationError() }
            if title.mediaType == .person {
                result.append(title); continue
            }
            guard title.mediaType == .movie || title.mediaType == .tv else { continue }
            if restriction == .off {
                if admits(title) {
                    result.append(title)
                }
            } else {
                let client = try requireClient()
                var detail = try await client.details(mediaType: title.mediaType ?? .unknown, id: title.id)
                detail.character = title.character
                detail.job = title.job
                guard expected == revision, restrictions == restrictionRevision else { throw CancellationError() }
                if admits(detail) {
                    result.append(detail)
                }
            }
        }
        guard expected == revision, restrictions == restrictionRevision else { throw CancellationError() }
        return result
    }

    private func encodedCookies(_ client: SeerrClient) async throws -> String {
        let cookies = await client.sessionCookies()
        guard cookies.contains(where: { $0.name == "connect.sid" && !$0.value.isEmpty }) else { throw SeerrConnectionError.signInRequired }
        let data = try JSONEncoder().encode(cookies)
        guard let value = String(data: data, encoding: .utf8) else { throw SeerrConnectionError.secureStorage }
        return value
    }

    private func persistCookies(_ client: SeerrClient) async throws {
        let expected = revision
        let value = try await encodedCookies(client)
        guard expected == revision, !Task.isCancelled else { throw CancellationError() }
        tokens.setToken(value, account: credentialAccount)
        guard tokens.token(account: credentialAccount) == value else { throw SeerrConnectionError.secureStorage }
    }

    private struct SavedConnection: Codable {
        let scope: AccountScope
        let url: URL
        let seerrUserID: Int
        var pendingRequests: [String: SeerrPendingRequest]?
        var pendingSupport: [String]?
    }
}

enum SeerrConnectionError: LocalizedError {
    case secureStorage, signInRequired, eligibilityChanged, notPermitted
    var errorDescription: String? {
        switch self {
        case .secureStorage: String(localized: "The Seerr session could not be saved securely. Please try again.")
        case .signInRequired: String(localized: "Sign in to Seerr to continue.")
        case .eligibilityChanged: String(localized: "Request eligibility changed. Review the current title and try again.")
        case .notPermitted: String(localized: "Your Seerr account does not allow this action.")
        }
    }
}
