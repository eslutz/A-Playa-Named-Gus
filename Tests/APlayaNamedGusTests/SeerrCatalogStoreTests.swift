import Foundation
@testable import Gus
import os
import Testing

@MainActor
@Suite("Seerr catalog state and isolation", .timeLimit(.minutes(1)))
struct SeerrCatalogStoreTests {
    @Test("failed next page retains prior titles, retries that page and deduplicates identities")
    func failedPageRetainsContent() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, totalPages: 2, titles: #"{"id":1,"mediaType":"movie","title":"First"}"#)),
            .init(json: "{}", status: 503),
            .init(json: Self.page(2, totalPages: 2, titles: #"{"id":1,"mediaType":"movie","title":"First"},{"id":2,"mediaType":"tv","name":"Second"}"#)),
        ])
        defer { fixture.cleanUp() }
        let catalog = SeerrCatalogStore(source: .feed(.trending))
        await catalog.load(store: fixture.store)
        await catalog.loadMore(store: fixture.store)
        #expect(catalog.items.map(\.id) == [1])
        #expect(catalog.state == .loaded)
        #expect(catalog.hasMore)
        #expect(catalog.failedPage == 2)
        #expect(catalog.errorMessage != nil)
        #expect(!catalog.isLoadingMore)

        await catalog.loadMore(store: fixture.store)
        #expect(catalog.items.map(\.id) == [1, 2])
        #expect(!catalog.hasMore)
        #expect(catalog.errorMessage == nil)
        #expect(fixture.http.requests.map { Self.query($0, key: "page") } == ["1", "2", "2"])
    }

    @Test("a delayed previous-account response cannot replace the new connection's catalog")
    func accountChangeRejectsLateResponse() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, titles: #"{"id":1,"mediaType":"movie","title":"Previous account"}"#), paused: true),
        ])
        defer { fixture.cleanUp() }
        let catalog = SeerrCatalogStore(source: .feed(.trending))
        let previousLoad = Task { await catalog.load(store: fixture.store) }
        await fixture.http.waitForStarted(1)

        let replacement = CatalogHTTPFixture(replies: [
            .init(json: Self.page(1, titles: #"{"id":2,"mediaType":"movie","title":"Current account"}"#)),
        ])
        try await fixture.store.connect(client: replacement.client(), user: SeerrUser(id: 88, permissions: .request))
        #expect(!catalog.isValid(for: fixture.store))
        await catalog.load(store: fixture.store)
        fixture.http.releasePausedResponses()
        await previousLoad.value

        #expect(catalog.items.map(\.id) == [2])
        #expect(catalog.state == .loaded)
        #expect(catalog.isValid(for: fixture.store))
    }

    @Test("a new applied filter rejects the delayed prior-query page")
    func filterGenerationRejectsLateResponse() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, titles: #"{"id":1,"mediaType":"tv","name":"Old filter"}"#), paused: true),
            .init(json: Self.page(1, titles: #"{"id":2,"mediaType":"movie","title":"New filter"}"#)),
        ])
        defer { fixture.cleanUp() }
        let catalog = SeerrCatalogStore(source: .feed(.trending))
        let previousLoad = Task { await catalog.load(store: fixture.store) }
        await fixture.http.waitForStarted(1)
        await catalog.applyFilters(SeerrCatalogFilters(mediaType: "movie", language: "en"), store: fixture.store)
        fixture.http.releasePausedResponses()
        await previousLoad.value

        #expect(catalog.items.map(\.id) == [2])
        #expect(catalog.filters.mediaType == "movie")
        #expect(try Self.query(#require(fixture.http.requests.last), key: "mediaType") == "movie")
        #expect(try Self.query(#require(fixture.http.requests.last), key: "language") == "en")
    }

    @Test("canceling a first-page read leaves it reloadable when the view returns")
    func canceledReadCanReload() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, titles: #"{"id":1,"mediaType":"movie","title":"Canceled"}"#), paused: true),
            .init(json: Self.page(1, titles: #"{"id":2,"mediaType":"movie","title":"Returned"}"#)),
        ])
        defer { fixture.cleanUp() }
        let catalog = SeerrCatalogStore(source: .feed(.trending))
        let load = Task { await catalog.load(store: fixture.store) }
        await fixture.http.waitForStarted(1)
        load.cancel()
        await load.value
        #expect(catalog.state == .idle)
        await catalog.load(store: fixture.store)
        #expect(catalog.items.map(\.id) == [2])
        #expect(catalog.state == .loaded)
    }

    @Test("restricted catalogs hydrate missing ratings and omit restricted, unrated and blocked titles")
    func restrictionsHydrateBeforePresentation() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, titles: #"{"id":1,"mediaType":"movie","title":"Restricted"},{"id":2,"mediaType":"movie","title":"Allowed"},{"id":3,"mediaType":"movie","title":"Blocked"},{"id":4,"mediaType":"movie","title":"Unrated"},{"id":9,"mediaType":"person","name":"A Person"}"#)),
            .init(json: Self.movie(1, title: "Restricted", rating: "R")),
            .init(json: Self.movie(2, title: "Allowed", rating: "G")),
            .init(json: Self.movie(3, title: "Blocked", rating: "G", status: 6)),
            .init(json: #"{"id":4,"title":"Unrated"}"#),
        ])
        defer { fixture.cleanUp() }
        fixture.defaults.set(ContentRatingGate.Limit.general.rawValue, forKey: ContentRatingGate.limitDefaultsKey)
        fixture.defaults.set(true, forKey: ContentRatingGate.hideUnratedDefaultsKey)
        let catalog = SeerrCatalogStore(source: .feed(.trending))
        await catalog.load(store: fixture.store)

        #expect(catalog.items.map(\.id) == [2, 9])
        #expect(catalog.items.first?.certification == "G")
        #expect(catalog.items.allSatisfy { fixture.store.admits($0) })
        #expect(fixture.http.requests.compactMap(\.url?.lastPathComponent) == ["trending", "1", "2", "3", "4"])

        fixture.defaults.set(ContentRatingGate.Limit.off.rawValue, forKey: ContentRatingGate.limitDefaultsKey)
        #expect(!catalog.isValid(for: fixture.store))
    }

    @Test("an empty restricted page still permits reading later pages")
    func restrictedFirstPageIsNotEnd() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, totalPages: 2, titles: #"{"id":1,"mediaType":"movie","title":"Restricted"}"#)),
            .init(json: Self.movie(1, title: "Restricted", rating: "R")),
            .init(json: Self.page(2, totalPages: 2, titles: #"{"id":2,"mediaType":"movie","title":"Allowed"}"#)),
            .init(json: Self.movie(2, title: "Allowed", rating: "G")),
        ])
        defer { fixture.cleanUp() }
        fixture.defaults.set(ContentRatingGate.Limit.general.rawValue, forKey: ContentRatingGate.limitDefaultsKey)
        let catalog = SeerrCatalogStore(source: .feed(.trending))
        await catalog.load(store: fixture.store)
        #expect(catalog.items.isEmpty)
        #expect(catalog.hasMore)
        await catalog.loadMore(store: fixture.store)
        #expect(catalog.items.map(\.id) == [2])
        #expect(!catalog.hasMore)
    }

    @Test("server order and enabled built-in slider capabilities determine available feeds")
    func enabledSupportedFeeds() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: #"[{"id":1,"type":4,"order":3,"enabled":true,"isBuiltIn":true},{"id":2,"type":5,"order":0,"enabled":false,"isBuiltIn":true},{"id":3,"type":7,"order":1,"enabled":true,"isBuiltIn":false},{"id":4,"type":99,"order":2,"enabled":true,"isBuiltIn":true},{"id":5,"type":9,"order":0,"enabled":true,"isBuiltIn":true}]"#),
        ])
        defer { fixture.cleanUp() }
        let sliders = try await fixture.store.requireClient().discoverSliders()
        #expect(sliders.sorted { $0.order < $1.order }.compactMap(\.supportedFeed) == [.popularTV, .trending])
        #expect(fixture.http.requests.first?.url?.path == "/seerr/api/v1/settings/discover")
    }

    @Test("one feed's failure preserves another feed's successful catalog")
    func feedsFailIndependently() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, titles: #"{"id":1,"mediaType":"movie","title":"Retained"}"#)),
            .init(json: "{}", status: 503),
        ])
        defer { fixture.cleanUp() }
        let trending = SeerrCatalogStore(source: .feed(.trending))
        let movies = SeerrCatalogStore(source: .feed(.popularMovies))
        await trending.load(store: fixture.store)
        await movies.load(store: fixture.store)
        #expect(trending.items.map(\.id) == [1])
        #expect(trending.state == .loaded)
        if case .failed = movies.state {} else {
            Issue.record("The failed feed must retain its own error state")
        }
        #expect(fixture.store.isConnected)
    }

    private static func query(_ request: URLRequest, key: String) -> String? {
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == key }?.value
    }

    private static func page(_ page: Int, totalPages: Int = 1, titles: String) -> String {
        "{\"page\":\(page),\"totalPages\":\(totalPages),\"totalResults\":20,\"results\":[\(titles)]}"
    }

    private static func movie(_ id: Int, title: String, rating: String, status: Int = 1) -> String {
        "{\"id\":\(id),\"title\":\"\(title)\",\"releases\":{\"results\":[{\"iso_3166_1\":\"US\",\"release_dates\":[{\"certification\":\"\(rating)\",\"type\":3}]}]},\"mediaInfo\":{\"id\":\(id),\"status\":\(status)}}"
    }
}

@MainActor
private struct CatalogStoreFixture {
    let http: CatalogHTTPFixture
    let store: SeerrStore
    let defaults: UserDefaults
    private let suite: String
    private let directory: URL

    init(replies: [CatalogReply]) async throws {
        suite = "dev.ericslutz.gus.tests.catalog.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        http = CatalogHTTPFixture(replies: replies)
        store = SeerrStore(
            scope: AccountScope(serverID: "test-server", userID: "test-user"),
            directory: directory,
            tokens: CatalogTokenStore(),
            userDefaults: defaults
        )
        try await store.connect(client: http.client(), user: SeerrUser(id: 2, permissions: .request))
    }

    func cleanUp() {
        http.releasePausedResponses()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class CatalogTokenStore: TokenStore {
    private var values: [String: String] = [:]
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

private struct CatalogReply: Sendable {
    var json: String
    var status = 200
    var paused = false
}

private final class CatalogHTTPFixture: @unchecked Sendable {
    private let id = UUID().uuidString
    private let state: CatalogProtocolState
    private let session: URLSession

    init(replies: [CatalogReply]) {
        state = CatalogProtocolState(replies: replies)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogURLProtocol.self]
        configuration.httpAdditionalHeaders = [CatalogURLProtocol.header: id]
        session = URLSession(configuration: configuration)
        CatalogURLProtocol.states.withLock { $0[id] = state }
    }

    deinit {
        session.invalidateAndCancel()
        _ = CatalogURLProtocol.states.withLock { $0.removeValue(forKey: id) }
    }

    var requests: [URLRequest] {
        state.requests
    }

    func waitForStarted(_ count: Int) async {
        await state.waitForStarted(count)
    }

    func releasePausedResponses() {
        state.release()
    }

    func client() throws -> SeerrClient {
        let base = try #require(URL(string: "https://media.example/seerr"))
        let cookie = SeerrSessionCookie(origin: base, name: "connect.sid", value: "catalog-fixture", path: "/", expiresAt: nil, secure: true)
        return try SeerrClient(baseURL: base, session: session, cookies: [cookie])
    }
}

/// Protocol callbacks are resumed only once; pending replies and waiters are protected by the state lock.
private final class CatalogURLProtocol: URLProtocol {
    static let header = "X-Gus-Catalog-Test-ID"
    static let states = OSAllocatedUnfairLock(initialState: [String: CatalogProtocolState]())
    private let stopped = OSAllocatedUnfairLock(initialState: false)

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: header) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: Self.header), let state = Self.states.withLock({ $0[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        if let reply = state.accept(request, loader: self) {
            send(reply)
        }
    }

    override func stopLoading() {
        stopped.withLock { $0 = true }
    }

    func send(_ reply: CatalogReply) {
        guard !stopped.withLock({ $0 }) else { return }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])
        else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class CatalogProtocolState: Sendable {
    private struct Pending {
        let loader: CatalogURLProtocol
        let reply: CatalogReply
    }

    private struct State {
        var replies: [CatalogReply]
        var requests: [URLRequest] = []
        var pending: [Pending] = []
        var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    }

    private let state: OSAllocatedUnfairLock<State>
    init(replies: [CatalogReply]) {
        // URLProtocol forbids Sendable conformance. Its pending reference stays behind this
        // lock until one release drains it; stopped loaders ignore delivery after cancellation.
        state = OSAllocatedUnfairLock(uncheckedState: State(replies: replies))
    }

    var requests: [URLRequest] {
        state.withLock { $0.requests }
    }

    func accept(_ request: URLRequest, loader: CatalogURLProtocol) -> CatalogReply? {
        let (reply, waiters) = state.withLockUnchecked { value -> (CatalogReply, [CheckedContinuation<Void, Never>]) in
            value.requests.append(request)
            let reply = value.replies.isEmpty ? CatalogReply(json: "{}", status: 500) : value.replies.removeFirst()
            if reply.paused {
                value.pending.append(Pending(loader: loader, reply: reply))
            }
            let ready = value.waiters.filter { $0.0 <= value.requests.count }.map(\.1)
            value.waiters.removeAll { $0.0 <= value.requests.count }
            return (reply, ready)
        }
        for waiter in waiters {
            waiter.resume()
        }
        return reply.paused ? nil : reply
    }

    func waitForStarted(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let alreadyStarted = state.withLock { value in
                if value.requests.count >= count {
                    return true
                }
                value.waiters.append((count, continuation))
                return false
            }
            if alreadyStarted {
                continuation.resume()
            }
        }
    }

    func release() {
        let pending = state.withLockUnchecked { value in
            let pending = value.pending
            value.pending = []
            return pending
        }
        for item in pending {
            item.loader.send(item.reply)
        }
    }
}
