import Foundation
@testable import Gus
import JellyfinAPI
import os
import Testing

@MainActor @Suite("Authenticated transport recovery")
struct SessionAuthenticationTests {
    enum Activation: CaseIterable, Sendable {
        case password, quickConnect, restore, savedAccount, handoff
    }

    @Test("every activation path recovers a transport 401 without deleting saved account data", arguments: Activation.allCases)
    func activationRecovery(_ activation: Activation) async throws {
        let authentication = AuthenticationResult(accessToken: "fixture-token", user: UserDto(id: "user", name: "Gus"))
        let replies: [AuthenticationReply] = switch activation {
        case .password, .quickConnect: try [.http(200, JSONEncoder().encode(authentication)), .http(401, Data())]
        default: [.http(401, Data())]
        }
        let fixture = try AuthenticationFixture(replies: replies)
        switch activation {
        case .password: try await fixture.app.signIn(to: fixture.server, username: "Gus", password: "fixture-password")
        case .quickConnect: try await fixture.app.signIn(to: fixture.server, quickConnectSecret: "fixture-secret")
        case .restore: await fixture.app.restoreLastSession()
        case .savedAccount: try await fixture.app.switchToStoredUser(fixture.user)
        case .handoff: await fixture.app.adoptHandedOffSession(server: fixture.server, user: fixture.user, token: "fixture-token")
        }
        let session = try #require(fixture.app.currentSession)
        await session.profile.load()
        #expect(fixture.app.currentSession == nil)
        #expect(fixture.app.reauthentication?.user == fixture.user)
        #expect(fixture.app.users == [fixture.user])
        #expect(fixture.deletedData == 0)
        #expect(!session.isActive)
    }

    @Test("profile permission denial does not expire valid credentials")
    func forbiddenProfile() async throws {
        let fixture = try AuthenticationFixture(replies: [.http(403, Data())])
        await fixture.app.restoreLastSession()
        let session = try #require(fixture.app.currentSession)
        await session.profile.load()
        #expect(fixture.app.currentSession === session)
        #expect(session.profile.errorMessage == GusError.forbidden.localizedDescription)
        #expect(fixture.app.reauthentication == nil)
    }

    @Test("a delete policy 401 requires authoritative authentication before expiry")
    func deletionPolicy() async throws {
        let user = UserDto(id: "user", name: "Gus")
        let fixture = try AuthenticationFixture(replies: [.http(401, Data()), .http(200, JSONEncoder().encode(user))])
        await fixture.app.restoreLastSession()
        let session = try #require(fixture.app.currentSession)
        await #expect(throws: GusError.forbidden) { try await session.client.send(Paths.deleteItem(itemID: "collection")) }
        #expect(fixture.app.currentSession === session)
        #expect(fixture.state.requests.map(\.httpMethod) == ["DELETE", "GET"])
        #expect(fixture.state.requests.last?.url?.path == "/Users/user")
    }

    @Test("an unavailable policy probe does not infer expiry or repeat the delete")
    func unavailablePolicyProbe() async throws {
        let fixture = try AuthenticationFixture(replies: [.http(401, Data()), .failure(.notConnectedToInternet)])
        await fixture.app.restoreLastSession()
        let session = try #require(fixture.app.currentSession)
        await #expect(throws: GusError.offline) { try await session.client.send(Paths.deleteItem(itemID: "collection")) }
        #expect(fixture.app.currentSession === session)
        #expect(fixture.state.requests.count == 2)
    }

    @Test("a rejected canonical probe expires once and never repeats the write")
    func expiredPolicyProbe() async throws {
        let fixture = try AuthenticationFixture(replies: [.http(401, Data()), .http(401, Data())])
        await fixture.app.restoreLastSession()
        let session = try #require(fixture.app.currentSession)
        do { try await session.client.send(Paths.deleteItem(itemID: "collection")) }
        catch { #expect(GusError(from: error) == .unauthorized) }
        #expect(fixture.app.currentSession == nil)
        #expect(fixture.app.reauthentication?.user == fixture.user)
        #expect(fixture.state.requests.count == 2)
        #expect(fixture.deletedData == 0)
    }

    @Test("a background failure probes the rotated credential without expiring it")
    func backgroundProbeAfterRotation() async throws {
        let fixture = try AuthenticationFixture(replies: [.http(200, JSONEncoder().encode(UserDto(id: "user", name: "Gus")))])
        await fixture.app.restoreLastSession()
        await fixture.app.adoptHandedOffSession(server: fixture.server, user: fixture.user, token: "replacement")
        let replacement = try #require(fixture.app.currentSession)
        await fixture.app.verifyAuthentication(for: replacement.references.scope)
        #expect(fixture.app.currentSession === replacement)
        #expect(fixture.app.reauthentication == nil)
    }
}

private enum AuthenticationReply: Sendable {
    case http(Int, Data)
    case failure(URLError.Code)
}

@MainActor
private final class AuthenticationFixture {
    let app: AppModel
    let state: AuthenticationResponseState
    let server: ServerConnection
    let user: StoredUser
    private let deletionCounter: AuthenticationDeletionCounter
    var deletedData: Int {
        deletionCounter.count
    }

    init(replies: [AuthenticationReply]) throws {
        let responseState = AuthenticationResponseState(replies: replies)
        state = responseState
        let id = UUID().uuidString
        AuthenticationURLProtocol.states.withLock { $0[id] = responseState }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticationURLProtocol.self]
        configuration.httpAdditionalHeaders = [AuthenticationURLProtocol.header: id]
        server = try ServerConnection(id: "server", name: "Server", url: #require(URL(string: "https://authentication.example.invalid")))
        user = StoredUser(id: "user", name: "Gus", serverID: "server")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ServerStore(directory: directory)
        store.saveServers([server])
        store.saveUsers([user])
        let tokens = AuthenticationTokenStore()
        tokens.setToken("fixture-token", for: SessionCredential(user: user))
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        defaults.set(SessionCredential(user: user).account, forKey: "dev.ericslutz.gus.lastSignedInSessionAccount")
        let counter = AuthenticationDeletionCounter()
        deletionCounter = counter
        app = AppModel(
            serverStore: store, tokenStore: tokens, userDefaults: defaults,
            accountCleanup: .init(clearSearchIndex: { _, _ in }, clearTopShelf: {}, clearBookState: { _ in counter.count += 1 }, clearDownloads: { _ in counter.count += 1 }, clearWatchCredential: { _, _ in }),
            clientFactory: { url, token, delegate in
                JellyfinClient(configuration: .init(url: url, accessToken: token, client: "GusTests", deviceName: "Tests", deviceID: "device", version: "1"), delegate: delegate, sessionConfiguration: configuration)
            }
        )
    }
}

@MainActor
private final class AuthenticationDeletionCounter {
    var count = 0
}

private final class AuthenticationTokenStore: TokenStore {
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

private final class AuthenticationURLProtocol: URLProtocol {
    static let header = "X-Gus-Authentication-Fixture"
    static let states = OSAllocatedUnfairLock(initialState: [String: AuthenticationResponseState]())
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "authentication.example.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func stopLoading() {}

    override func startLoading() {
        do {
            let id = try #require(request.value(forHTTPHeaderField: Self.header))
            let state = try #require(Self.states.withLock { $0[id] })
            switch try state.response(for: request) {
            case let .failure(code): throw URLError(code)
            case let .http(code, data):
                let requestURL = try #require(request.url)
                let response = try #require(HTTPURLResponse(url: requestURL, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}

private final class AuthenticationResponseState: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [AuthenticationReply]
    private var recorded: [URLRequest] = []
    init(replies: [AuthenticationReply]) {
        self.replies = replies
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    func response(for request: URLRequest) throws -> AuthenticationReply {
        try lock.withLock {
            recorded.append(request)
            guard !replies.isEmpty else { throw URLError(.badServerResponse) }
            return replies.removeFirst()
        }
    }
}
