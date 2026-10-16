import Foundation
@testable import Gus
import JellyfinAPI
import os
import Testing

@MainActor @Suite("Authenticated profile editing")
struct UserProfileStoreTests {
    @Test("Loads the current avatar through authenticated image requests")
    func avatar() async throws {
        let user = UserDto(id: "user", name: "Eric", primaryImageTag: "image-tag")
        let image = Data([1, 2, 3])
        let (store, state) = try fixture([JSONEncoder().encode(user), image])
        await store.load()
        #expect(store.profile?.name == "Eric")
        #expect(store.imageData == image)
        #expect(state.requests[1].url?.path == "/UserImage")
        #expect(state.requests[1].url?.query?.contains("tag=image-tag") == true)
        #expect(state.requests[1].url?.query?.contains("token") == false)
        #expect(state.requests[1].value(forHTTPHeaderField: "Authorization") != nil)
    }

    @Test("Saves preferences without replacing unrelated server configuration")
    func save() async throws {
        let configuration = UserConfiguration(isHidePlayedInLatest: true, orderedViews: ["library"])
        let old = UserDto(configuration: configuration, id: "user", name: "Eric")
        var new = old
        new.name = "Eric Updated"
        new.configuration?.audioLanguagePreference = "eng"
        new.configuration?.subtitleLanguagePreference = "spa"
        let (store, state) = try fixture([JSONEncoder().encode(old), Data(), Data(), JSONEncoder().encode(new)])
        #expect(await store.save(name: "Eric Updated", audioLanguage: "eng", subtitleLanguage: "spa"))
        #expect(store.profile?.name == "Eric Updated")
        let request = state.requests[2]
        let sent = try JSONDecoder().decode(UserConfiguration.self, from: #require(request.httpBody))
        #expect(sent.isHidePlayedInLatest == true)
        #expect(sent.orderedViews == ["library"])
        #expect(sent.audioLanguagePreference == "eng")
        #expect(sent.subtitleLanguagePreference == "spa")
    }

    @Test("A rejected save does not report success or erase the server error")
    func failure() async throws {
        let user = UserDto(id: "user", name: "Eric")
        let (store, _) = try fixture([JSONEncoder().encode(user), Data(), JSONEncoder().encode(user)], codes: [200, 403, 200])
        #expect(await store.save(name: "Changed", audioLanguage: "", subtitleLanguage: "") == false)
        #expect(store.profile?.name == "Eric")
        #expect(store.errorMessage != nil)
    }

    @Test("Blank names never reach the server")
    func invalidName() async throws {
        let (store, state) = try fixture([])
        #expect(await store.save(name: "  ", audioLanguage: "", subtitleLanguage: "") == false)
        #expect(state.requests.isEmpty)
    }

    private func fixture(_ data: [Data], codes: [Int]? = nil) throws -> (UserProfileStore, ProfileResponseState) {
        let state = ProfileResponseState(responses: data, statusCodes: codes)
        let id = UUID().uuidString
        ProfileURLProtocol.states.withLock { $0[id] = state }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileURLProtocol.self]
        configuration.httpAdditionalHeaders = [ProfileURLProtocol.header: id]
        let client = try JellyfinClient(configuration: .init(url: #require(URL(string: "https://jellyfin.example.com")), accessToken: "token", client: "GusTests", deviceName: "Tests", deviceID: "device", version: "1"), sessionConfiguration: configuration)
        return (UserProfileStore(client: client, userID: "user"), state)
    }
}

private final class ProfileURLProtocol: URLProtocol {
    static let header = "X-Gus-Native-List-Fixture"
    static let states = OSAllocatedUnfairLock(initialState: [String: ProfileResponseState]())

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "jellyfin.example.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func stopLoading() {}

    override func startLoading() {
        do {
            let stateID = try #require(request.value(forHTTPHeaderField: Self.header))
            let state = try #require(Self.states.withLock { $0[stateID] })
            let (data, statusCode) = try state.response(for: request)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}

private final class ProfileResponseState: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Data]
    private var recorded: [URLRequest] = []
    private var statusCodes: [Int]
    init(responses: [Data], statusCodes: [Int]?) {
        self.responses = responses
        self.statusCodes = statusCodes ?? responses.map { $0.isEmpty ? 204 : 200 }
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func response(for request: URLRequest) throws -> (Data, Int) {
        lock.lock()
        defer { lock.unlock() }
        var request = request
        request.httpBody = try bodyData(request)
        recorded.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return (responses.removeFirst(), statusCodes.removeFirst())
    }
}

private func bodyData(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeContentData)
        }
        if count == 0 {
            break
        }
        data.append(buffer, count: count)
    }
    return data
}
