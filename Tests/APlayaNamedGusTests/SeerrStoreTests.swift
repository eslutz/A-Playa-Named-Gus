import Foundation
@testable import Gus
import os
import Testing

@MainActor
@Suite("Seerr device session safety", .timeLimit(.minutes(1)))
struct SeerrStoreTests {
    @Test("an authenticated-user payload without a usable session cookie cannot be committed")
    func rejectsMissingSessionCookie() async throws {
        let context = try StoreTestContext()
        defer { context.cleanUp() }
        let candidate = try context.http.client(cookies: [])
        do {
            try await context.store.connect(client: candidate, user: SeerrUser(id: 2, permissions: .request))
            Issue.record("A connection without connect.sid must be rejected")
        } catch SeerrConnectionError.signInRequired {}
        #expect(context.store.state == .disconnected)
        #expect(context.store.client == nil)
        #expect(context.store.user == nil)
        #expect(context.tokens.values.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: context.connectionFile.path))
    }

    @Test("disconnect invalidates a connection suspended while reading its actor-owned cookies")
    func disconnectCancelsSuspendedConnect() async throws {
        let context = try StoreTestContext()
        defer { context.cleanUp() }
        let candidate = try context.http.client()
        let gate = StoreActorGate()
        let occupyingActor = Task.detached { await candidate.occupyForStoreTest(gate) }
        defer { gate.release() }
        await gate.entered.wait()

        let started = StoreTestSignal()
        let expected = context.store.revision
        let connecting = Task {
            started.signal()
            try await context.store.connect(client: candidate, user: SeerrUser(id: 2, permissions: .request), expectedRevision: expected)
        }
        // Both callers run on MainActor. This waiter resumes after connect reaches
        // its actor hop, whose executor is held by the gate above.
        await started.wait()
        context.store.disconnect()
        let disconnectedRevision = context.store.revision
        gate.release()
        await occupyingActor.value
        await #expect(throws: CancellationError.self) { try await connecting.value }

        #expect(context.store.state == .disconnected)
        #expect(context.store.revision == disconnectedRevision)
        #expect(context.store.client == nil)
        #expect(context.tokens.values.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: context.connectionFile.path))
    }

    @Test("disk metadata and cookies stay scoped to their Gus server and account")
    func persistenceIsScopedAndSecretFree() async throws {
        let context = try StoreTestContext(replies: [.init(json: "{}")])
        defer { context.cleanUp() }
        let firstClient = try context.http.client()
        try await context.store.connect(client: firstClient, user: SeerrUser(id: 22, permissions: .request))

        let secondScope = AccountScope(serverID: context.scope.serverID, userID: "other-user")
        let secondStore = context.makeStore(scope: secondScope)
        try await secondStore.connect(client: context.http.client(cookieValue: "second-fixture"), user: SeerrUser(id: 33, permissions: .request))
        let secondFile = context.directory.appendingPathComponent(secondScope.storageKey + ".json")
        let firstKey = context.credentialAccount
        let secondKey = "seerr:\(secondScope.serverID):\(secondScope.userID)"

        let disk = try Data(contentsOf: context.connectionFile)
        let metadata = try #require(JSONSerialization.jsonObject(with: disk) as? [String: Any])
        let savedScope = try #require(metadata["scope"] as? [String: String])
        #expect(savedScope["serverID"] == context.scope.serverID)
        #expect(savedScope["userID"] == context.scope.userID)
        #expect(metadata["url"] as? String == firstClient.baseURL.absoluteString)
        #expect(Set(metadata.keys).isDisjoint(with: ["cookies", "cookie", "token", "password"]))
        #expect(metadata["seerrUserID"] as? Int == 22)
        let serialized = try #require(String(data: disk, encoding: .utf8))
        #expect(!serialized.contains("connect.sid"))
        #expect(!serialized.contains("store-fixture-secret"))
        let token = try #require(context.tokens.token(account: firstKey))
        let cookies = try JSONDecoder().decode([SeerrSessionCookie].self, from: Data(token.utf8))
        #expect(cookies.count == 1)
        #expect(cookies.first?.origin == firstClient.baseURL)
        #expect(cookies.first?.name == "connect.sid")
        #expect(cookies.first?.value == "store-fixture-secret")
        #expect(context.tokens.token(account: secondKey) != token)

        context.store.disconnect()
        #expect(context.tokens.token(account: firstKey) == nil)
        #expect(context.tokens.token(account: secondKey) != nil)
        #expect(!FileManager.default.fileExists(atPath: context.connectionFile.path))
        #expect(FileManager.default.fileExists(atPath: secondFile.path))
        #expect(secondStore.isConnected)
    }

    @Test("failed disk persistence restores the previous cookie and leaves the active session unchanged")
    func failedReplacementRollsBack() async throws {
        let context = try StoreTestContext()
        defer { context.cleanUp() }
        let previousClient = try context.http.client(cookieValue: "previous-fixture")
        let previousUser = SeerrUser(id: 2, permissions: .request)
        try await context.store.connect(client: previousClient, user: previousUser)
        let previousRevision = context.store.revision
        let previousToken = context.tokens.token(account: context.credentialAccount)

        // A directory at the final file URL makes atomic file replacement fail
        // deterministically, independently of the test runner's filesystem permissions.
        try FileManager.default.removeItem(at: context.connectionFile)
        try FileManager.default.createDirectory(at: context.connectionFile, withIntermediateDirectories: false)
        do {
            try await context.store.connect(client: context.http.client(cookieValue: "replacement-fixture"), user: SeerrUser(id: 99, permissions: .request))
            Issue.record("Writing connection metadata over a directory must fail")
        } catch {}

        #expect(context.tokens.token(account: context.credentialAccount) == previousToken)
        #expect(context.store.client === previousClient)
        #expect(context.store.user == previousUser)
        #expect(context.store.revision == previousRevision)
        #expect(context.store.isConnected)
    }

    @Test("failed initial persistence removes the newly staged cookie")
    func failedFirstSaveRemovesCookie() async throws {
        let context = try StoreTestContext()
        defer { context.cleanUp() }
        try FileManager.default.createDirectory(at: context.connectionFile, withIntermediateDirectories: true)
        let previousRevision = context.store.revision
        do {
            try await context.store.connect(client: context.http.client(), user: SeerrUser(id: 2, permissions: .request))
            Issue.record("Initial metadata write must fail when its URL is a directory")
        } catch {}
        #expect(context.tokens.token(account: context.credentialAccount) == nil)
        #expect(context.store.state == .disconnected)
        #expect(context.store.client == nil)
        #expect(context.store.revision == previousRevision)
    }

    @Test("restore rejects a different Seerr principal even when the cookie authenticates")
    func restoreRejectsChangedPrincipal() async throws {
        let context = try StoreTestContext(replies: [
            .init(json: #"{"version":"3.5.1"}"#),
            .init(json: #"{"initialized":true,"localLogin":true,"mediaServerLogin":true,"mediaServerType":2}"#),
            .init(json: #"{"id":99,"permissions":32}"#),
        ])
        defer { context.cleanUp() }
        try await context.store.connect(client: context.http.client(), user: SeerrUser(id: 2, permissions: .request))
        let restored = context.makeStore(scope: context.scope)
        await restored.restore()

        #expect(restored.state == .expired)
        #expect(restored.user == nil)
        #expect(restored.client == nil)
        #expect(!restored.isConnected)
        #expect(restored.serverURL == context.http.baseURL)
        #expect(context.tokens.token(account: context.credentialAccount) == nil)
        #expect(context.http.requests.compactMap(\.url?.path) == ["/seerr/api/v1/status", "/seerr/api/v1/settings/public", "/seerr/api/v1/auth/me"])
        #expect(context.http.requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == "connect.sid=store-fixture-secret" })
    }

    @Test("account deactivation preserves the saved connection while invalidating access")
    func deactivationPreservesSavedConnection() async throws {
        let context = try StoreTestContext()
        defer { context.cleanUp() }
        try await context.store.connect(client: context.http.client(), user: SeerrUser(id: 2, permissions: .request))
        let previousRevision = context.store.revision
        let metadata = try Data(contentsOf: context.connectionFile)
        let cookie = context.tokens.token(account: context.credentialAccount)
        context.store.deactivate()
        #expect(context.store.revision != previousRevision)
        #expect(!context.store.isConnected)
        #expect(context.store.user == nil)
        #expect(context.store.client == nil)
        #expect(throws: SeerrConnectionError.signInRequired) { try context.store.requireClient() }
        #expect(try Data(contentsOf: context.connectionFile) == metadata)
        #expect(context.tokens.token(account: context.credentialAccount) == cookie)
    }

    @Test("blocking invalidates cached presentation by typed media identity")
    func blockInvalidatesSharedTypedIdentity() async throws {
        let context = try StoreTestContext(replies: [
            .init(json: #"{"page":1,"totalPages":1,"totalResults":2,"results":[{"id":17,"mediaType":"movie","title":"Movie"},{"id":17,"mediaType":"tv","name":"Series"}]}"#),
        ])
        defer { context.cleanUp() }
        try await context.store.connect(client: context.http.client(), user: SeerrUser(id: 2, permissions: .request))
        let catalog = SeerrCatalogStore(source: .feed(.trending))
        await catalog.load(store: context.store)
        let movie = try #require(catalog.items.first { $0.mediaType == .movie })
        let tv = try #require(catalog.items.first { $0.mediaType == .tv })
        #expect(catalog.items.count == 2)

        let previousRevision = context.store.revision
        context.store.recordBlock(mediaType: .movie, id: 17, blocked: true)
        #expect(context.store.revision != previousRevision)
        #expect(!catalog.isValid(for: context.store))
        #expect(!context.store.admits(movie))
        #expect(context.store.admits(tv))
        let blockedRevision = context.store.revision
        context.store.recordBlock(mediaType: .movie, id: 17, blocked: true)
        #expect(context.store.revision == blockedRevision)

        context.store.recordBlock(mediaType: .movie, id: 17, blocked: false)
        #expect(context.store.revision != blockedRevision)
        #expect(context.store.admits(movie))
        #expect(context.store.admits(tv))
    }
}

@MainActor
private struct StoreTestContext {
    let scope = AccountScope(serverID: "store-test-server", userID: "store-test-user")
    let http: StoreHTTPFixture
    let tokens: StoreMemoryTokens
    let defaults: UserDefaults
    let directory: URL
    let store: SeerrStore
    private let suite: String

    init(replies: [StoreReply] = []) throws {
        suite = "dev.ericslutz.gus.tests.seerr-store.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        http = try StoreHTTPFixture(replies: replies)
        tokens = StoreMemoryTokens()
        let http = self.http
        store = SeerrStore(
            scope: scope,
            directory: directory,
            tokens: tokens,
            userDefaults: defaults,
            clientFactory: { url, cookies in try http.client(baseURL: url, cookies: cookies) }
        )
    }

    var credentialAccount: String {
        "seerr:\(scope.serverID):\(scope.userID)"
    }

    var connectionFile: URL {
        directory.appendingPathComponent(scope.storageKey + ".json")
    }

    func makeStore(scope: AccountScope) -> SeerrStore {
        let http = self.http
        return SeerrStore(
            scope: scope,
            directory: directory,
            tokens: tokens,
            userDefaults: defaults,
            clientFactory: { url, cookies in try http.client(baseURL: url, cookies: cookies) }
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class StoreMemoryTokens: TokenStore {
    private(set) var values: [String: String] = [:]
    func token(for credential: SessionCredential) -> String? {
        token(account: credential.account)
    }

    func token(account: String) -> String? {
        values[account]
    }

    func setToken(_ token: String, for credential: SessionCredential) {
        setToken(token, account: credential.account)
    }

    func setToken(_ token: String, account: String) {
        values[account] = token
    }

    func deleteToken(for credential: SessionCredential) {
        deleteToken(account: credential.account)
    }

    func deleteToken(account: String) {
        values[account] = nil
    }
}

private struct StoreReply: Sendable {
    var json: String
    var status = 200
}

private final class StoreHTTPFixture: @unchecked Sendable {
    let baseURL: URL
    private let id = UUID().uuidString
    private let state: StoreProtocolState
    private let session: URLSession

    init(replies: [StoreReply]) throws {
        baseURL = try #require(URL(string: "https://media.example/seerr"))
        state = StoreProtocolState(replies: replies)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StoreURLProtocol.self]
        configuration.httpAdditionalHeaders = [StoreURLProtocol.header: id]
        session = URLSession(configuration: configuration)
        StoreURLProtocol.states.withLock { $0[id] = state }
    }

    deinit {
        session.invalidateAndCancel()
        _ = StoreURLProtocol.states.withLock { $0.removeValue(forKey: id) }
    }

    var requests: [URLRequest] {
        state.requests
    }

    func client(baseURL: URL? = nil, cookies: [SeerrSessionCookie]? = nil, cookieValue: String = "store-fixture-secret") throws -> SeerrClient {
        let base = baseURL ?? self.baseURL
        let sessionCookies = cookies ?? [SeerrSessionCookie(origin: base, name: "connect.sid", value: cookieValue, path: "/", expiresAt: nil, secure: true)]
        return try SeerrClient(baseURL: base, session: session, cookies: sessionCookies)
    }
}

private final class StoreURLProtocol: URLProtocol {
    static let header = "X-Gus-Store-Test-ID"
    static let states = OSAllocatedUnfairLock(initialState: [String: StoreProtocolState]())
    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: header) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: Self.header), let state = Self.states.withLock({ $0[id] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let reply = state.next(request)
        guard let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class StoreProtocolState: Sendable {
    private struct State {
        var replies: [StoreReply]
        var requests: [URLRequest] = []
    }

    private let state: OSAllocatedUnfairLock<State>
    init(replies: [StoreReply]) {
        state = OSAllocatedUnfairLock(initialState: State(replies: replies))
    }

    var requests: [URLRequest] {
        state.withLock { $0.requests }
    }

    func next(_ request: URLRequest) -> StoreReply {
        state.withLock { value in
            value.requests.append(request)
            return value.replies.isEmpty ? StoreReply(json: "{}", status: 500) : value.replies.removeFirst()
        }
    }
}

private final class StoreTestSignal: Sendable {
    private struct State {
        var signaled = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    func signal() {
        let waiters = state.withLock { value in
            value.signaled = true
            let waiters = value.waiters
            value.waiters = []
            return waiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { value in
                if value.signaled {
                    return true
                }
                value.waiters.append(continuation)
                return false
            }
            if ready {
                continuation.resume()
            }
        }
    }
}

/// Only the test client actor blocks; MainActor remains free to invalidate the pending connection.
private final class StoreActorGate: Sendable {
    let entered = StoreTestSignal()
    private let semaphore = DispatchSemaphore(value: 0)
    func occupy() {
        entered.signal(); semaphore.wait()
    }

    func release() {
        semaphore.signal()
    }
}

private extension SeerrClient {
    func occupyForStoreTest(_ gate: StoreActorGate) {
        gate.occupy()
    }
}
