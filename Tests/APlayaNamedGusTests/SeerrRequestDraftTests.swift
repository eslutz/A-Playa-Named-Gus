import Foundation
@testable import Gus
import os
import Testing

@MainActor
@Suite("Seerr request review and uncertain outcomes", .timeLimit(.minutes(1)))
struct SeerrRequestDraftTests {
    @Test("fresh permission loss or quota exhaustion prevents a reviewed request from being posted", arguments: ["permission", "quota"])
    func eligibilityMustStillBeCurrent(change: String) async throws {
        let fixture = try await RequestDraftFixture()
        defer { fixture.cleanUp() }
        let draft = try fixture.draft()
        await draft.load(store: fixture.store)
        #expect(draft.canSubmit)
        if change == "permission" {
            fixture.http.update { $0.permissions = [] }
        } else {
            fixture.http.update { $0.quotaExhausted = true }
        }
        await draft.submit(store: fixture.store)
        #expect(fixture.http.postCount == 0)
        #expect(draft.phase == .review)
        #expect(draft.confirmed == nil)
        #expect(!draft.canSubmit)
        #expect(draft.message != nil)
    }

    @Test("server defaults, revoked advanced permission and failed options discard stale dependent values", arguments: ["default", "permission", "failure"])
    func staleServiceOptionsCannotEscapeTheirService(change: String) async throws {
        let fixture = try await RequestDraftFixture(permissions: [.request, .requestAdvanced])
        defer { fixture.cleanUp() }
        let draft = try fixture.draft()
        await draft.load(store: fixture.store)
        draft.serverID = 7
        draft.profileID = 88
        draft.rootFolder = "/synthetic-old-server"
        draft.languageID = 99
        if change == "default" {
            draft.serverID = nil
            await draft.loadOptions(store: fixture.store)
        } else if change == "permission" {
            fixture.http.update { $0.permissions = .request }
            await draft.load(store: fixture.store)
        } else {
            fixture.http.update { $0.optionsFail = true }
            await draft.loadOptions(store: fixture.store)
        }
        #expect(draft.serverID == nil)
        #expect(draft.profileID == nil)
        #expect(draft.rootFolder == nil)
        #expect(draft.languageID == nil)
        #expect(draft.service == nil)
        #expect(!draft.isLoadingOptions)
    }

    @Test("old completed requests across all baseline pages cannot confirm a new uncertain attempt")
    func historicalCompletedRequestIsNotAcknowledgement() async throws {
        let fixture = try await RequestDraftFixture()
        defer { fixture.cleanUp() }
        fixture.http.update { state in
            state.history = (1 ... 51).map { requestID in Self.completedRequest(id: requestID) }
            state.createBeforeTimeout = false
        }
        let draft = try fixture.draft()
        await draft.load(store: fixture.store)
        await draft.submit(store: fixture.store)
        #expect(draft.phase == .uncertain)
        #expect(fixture.http.postCount == 1)
        await draft.check(store: fixture.store)
        #expect(draft.confirmed == nil)
        #expect(draft.phase == .uncertain)
        #expect(!draft.canSubmit)
        #expect(fixture.http.postCount == 1)
        #expect(fixture.http.requests.contains { request in
            request.url?.path.hasSuffix("/user/2/requests") == true && Self.query(request, "skip") == "50"
        })
    }

    @Test("a new matching pending request resolves a lost response without replaying the POST")
    func newPendingRequestConfirmsUncertainAttempt() async throws {
        let fixture = try await RequestDraftFixture()
        defer { fixture.cleanUp() }
        fixture.http.update { state in
            state.history = [Self.completedRequest(id: 44)]
            state.createBeforeTimeout = true
        }
        let draft = try fixture.draft()
        await draft.load(store: fixture.store)
        await draft.submit(store: fixture.store)
        #expect(draft.phase == .uncertain)
        #expect(draft.confirmed == nil)
        await draft.check(store: fixture.store)
        #expect(draft.phase == .confirmed)
        #expect(draft.confirmed?.id == 500)
        #expect(draft.confirmed?.status == .pending)
        #expect(draft.confirmed?.requestedBy?.id == 2)
        #expect(fixture.http.postCount == 1)
        #expect(!draft.canSubmit)
    }

    @Test("closing and reopening a request retains the pending attempt and write lock")
    func pendingAttemptSurvivesReopeningAndStoreRestoration() async throws {
        let fixture = try await RequestDraftFixture()
        defer { fixture.cleanUp() }
        let draft = try fixture.draft()
        await draft.load(store: fixture.store)
        await draft.submit(store: fixture.store)
        #expect(draft.phase == .uncertain)
        #expect(try fixture.draft() === draft)
        let restored = fixture.reopenedStore()
        await restored.restore()
        #expect(restored.isConnected)
        let title = try JSONDecoder().decode(SeerrTitle.self, from: Data(RequestDraftHTTPState.movie.utf8))
        let reopened = restored.requestDraft(for: title)
        #expect(reopened.phase == .uncertain)
        #expect(!reopened.canSubmit)
        await reopened.check(store: restored)
        #expect(reopened.phase == .uncertain)
        #expect(!reopened.canSubmit)
        #expect(fixture.http.postCount == 1)
    }

    @Test("restricting a title after review prevents submission")
    func changedContentRestrictionPreventsPost() async throws {
        let fixture = try await RequestDraftFixture()
        defer { fixture.cleanUp() }
        let draft = try fixture.draft()
        await draft.load(store: fixture.store)
        #expect(draft.canSubmit)
        fixture.defaults.set(ContentRatingGate.Limit.general.rawValue, forKey: ContentRatingGate.limitDefaultsKey)
        fixture.defaults.set(true, forKey: ContentRatingGate.hideUnratedDefaultsKey)
        await draft.submit(store: fixture.store)
        #expect(fixture.http.postCount == 0)
        #expect(draft.confirmed == nil)
    }

    private nonisolated static func completedRequest(id: Int) -> SeerrRequest {
        SeerrRequest(
            id: id,
            status: .completed,
            type: .movie,
            media: SeerrMediaInfo(id: 20, tmdbId: 10, mediaType: .movie, status: .deleted),
            requestedBy: SeerrUser(id: 2, permissions: .request),
            is4k: false
        )
    }

    private nonisolated static func query(_ request: URLRequest, _ name: String) -> String? {
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == name }?.value
    }
}

@MainActor
private struct RequestDraftFixture {
    let http: RequestDraftHTTPFixture
    let store: SeerrStore
    let defaults: UserDefaults
    private let tokens: RequestDraftTokens
    private let suite: String
    private let directory: URL

    init(permissions: SeerrPermissions = .request) async throws {
        suite = "dev.ericslutz.gus.tests.request-draft.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let transport = RequestDraftHTTPFixture(permissions: permissions)
        http = transport
        tokens = RequestDraftTokens()
        store = SeerrStore(
            scope: AccountScope(serverID: "test-server", userID: "test-user"),
            directory: directory,
            tokens: tokens,
            userDefaults: defaults,
            clientFactory: { _, cookies in try transport.client(cookies: cookies) }
        )
        try await store.connect(client: http.client(), user: SeerrUser(id: 2, permissions: permissions))
    }

    func draft() throws -> SeerrRequestDraft {
        try store.requestDraft(for: JSONDecoder().decode(SeerrTitle.self, from: Data(RequestDraftHTTPState.movie.utf8)))
    }

    func reopenedStore() -> SeerrStore {
        let transport = http
        return SeerrStore(
            scope: store.scope,
            directory: directory,
            tokens: tokens,
            userDefaults: defaults,
            clientFactory: { _, cookies in try transport.client(cookies: cookies) }
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class RequestDraftTokens: TokenStore {
    private let values = OSAllocatedUnfairLock(initialState: [String: String]())
    func token(for credential: SessionCredential) -> String? {
        token(account: credential.account)
    }

    func token(account: String) -> String? {
        values.withLock { $0[account] }
    }

    func setToken(_ token: String, for credential: SessionCredential) {
        setToken(token, account: credential.account)
    }

    func setToken(_ token: String, account: String) {
        values.withLock { $0[account] = token }
    }

    func deleteToken(for credential: SessionCredential) {
        deleteToken(account: credential.account)
    }

    func deleteToken(account: String) {
        values.withLock { $0[account] = nil }
    }
}

private struct RequestDraftHTTPState: Sendable {
    static let movie = #"{"id":10,"mediaType":"movie","title":"Synthetic Movie","mediaInfo":{"id":20,"tmdbId":10,"mediaType":"movie","status":7}}"#
    var permissions: SeerrPermissions
    var quotaExhausted = false
    var optionsFail = false
    var createBeforeTimeout = false
    var history: [SeerrRequest] = []
    var requests: [URLRequest] = []
}

private struct RequestDraftReply {
    var json = "{}"
    var status = 200
    var error: URLError?
}

private final class RequestDraftHTTPFixture: Sendable {
    private let id = UUID().uuidString
    private let state: OSAllocatedUnfairLock<RequestDraftHTTPState>
    private let session: URLSession

    init(permissions: SeerrPermissions) {
        state = OSAllocatedUnfairLock(initialState: RequestDraftHTTPState(permissions: permissions))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestDraftURLProtocol.self]
        configuration.httpAdditionalHeaders = [RequestDraftURLProtocol.header: id]
        session = URLSession(configuration: configuration)
        RequestDraftURLProtocol.fixtures.withLock { $0[id] = state }
    }

    deinit {
        session.invalidateAndCancel()
        _ = RequestDraftURLProtocol.fixtures.withLock { $0.removeValue(forKey: id) }
    }

    var requests: [URLRequest] {
        state.withLock { $0.requests }
    }

    var postCount: Int {
        requests.filter { $0.httpMethod == "POST" }.count
    }

    func update(_ body: @Sendable (inout RequestDraftHTTPState) -> Void) {
        state.withLock(body)
    }

    func client(cookies: [SeerrSessionCookie]? = nil) throws -> SeerrClient {
        let base = try #require(URL(string: "https://draft.example.invalid/seerr"))
        let cookie = SeerrSessionCookie(origin: base, name: "connect.sid", value: "synthetic-fixture-session", path: "/", expiresAt: nil, secure: true)
        return try SeerrClient(baseURL: base, session: session, cookies: cookies ?? [cookie])
    }
}

private final class RequestDraftURLProtocol: URLProtocol {
    static let header = "X-Gus-Seerr-Request-Draft-Test"
    static let fixtures = OSAllocatedUnfairLock(initialState: [String: OSAllocatedUnfairLock<RequestDraftHTTPState>]())

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: header) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: Self.header),
              let state = Self.fixtures.withLock({ $0[id] }), let url = request.url
        else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        let capturedRequest = request
        let reply = state.withLock { state in
            state.requests.append(capturedRequest)
            return Self.reply(to: capturedRequest, state: &state)
        }
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error); return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])
        else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func reply(to request: URLRequest, state: inout RequestDraftHTTPState) -> RequestDraftReply {
        let path = request.url?.path ?? ""
        if path.hasSuffix("/status") {
            return RequestDraftReply(json: #"{"version":"3.3.0"}"#)
        }
        if path.hasSuffix("/auth/me") {
            return RequestDraftReply(json: "{\"id\":2,\"permissions\":\(state.permissions.rawValue)}")
        }
        if path.hasSuffix("/movie/10") {
            return RequestDraftReply(json: RequestDraftHTTPState.movie)
        }
        if path.hasSuffix("/settings/public") {
            return RequestDraftReply(json: #"{"initialized":true,"localLogin":true,"mediaServerLogin":true,"mediaServerType":2}"#)
        }
        if path.hasSuffix("/user/2/quota") {
            let quota = SeerrQuotaStatus(limit: 5, used: state.quotaExhausted ? 5 : 0, remaining: state.quotaExhausted ? 0 : 5, restricted: state.quotaExhausted)
            return encoded(SeerrQuota(movie: quota, tv: quota))
        }
        if path.hasSuffix("/user/2/requests") {
            let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
            let skip = query.first { $0.name == "skip" }?.value.flatMap(Int.init) ?? 0
            let take = query.first { $0.name == "take" }?.value.flatMap(Int.init) ?? 50
            return encoded(SeerrRequestPage(
                pageInfo: SeerrPageInfo(pages: (state.history.count + take - 1) / take, pageSize: take, results: state.history.count, page: skip / take + 1),
                results: Array(state.history.dropFirst(skip).prefix(take))
            ))
        }
        if path.hasSuffix("/service/radarr") {
            return state.optionsFail ? RequestDraftReply(status: 503) : encoded([SeerrServiceServer(id: 7, name: "Synthetic Service", is4k: false, isDefault: true)])
        }
        if path.hasSuffix("/request"), request.httpMethod == "POST" {
            if state.createBeforeTimeout {
                state.history.insert(SeerrRequest(
                    id: 500,
                    status: .pending,
                    type: .movie,
                    media: SeerrMediaInfo(id: 20, tmdbId: 10, mediaType: .movie, status: .pending),
                    requestedBy: SeerrUser(id: 2, permissions: .request),
                    is4k: false
                ), at: 0)
            }
            return RequestDraftReply(error: URLError(.timedOut))
        }
        return RequestDraftReply(status: 404)
    }

    private static func encoded(_ value: some Encodable) -> RequestDraftReply {
        guard let data = try? JSONEncoder().encode(value) else { return RequestDraftReply(status: 500) }
        return RequestDraftReply(json: String(decoding: data, as: UTF8.self))
    }
}
