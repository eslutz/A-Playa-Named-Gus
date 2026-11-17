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
        #expect(await store.save(name: "Eric Updated", audioLanguage: "eng", subtitleLanguage: "spa") == .confirmed)
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
        #expect(await store.save(name: "Changed", audioLanguage: "", subtitleLanguage: "") != .confirmed)
        #expect(store.profile?.name == "Eric")
        #expect(store.errorMessage != nil)
    }

    @Test("a saved username and denied preference write reports the confirmed partial result")
    func partialUsernameSave() async throws {
        let original = UserDto(configuration: UserConfiguration(audioLanguagePreference: "eng"), id: "user", name: "Original")
        var updated = original
        updated.name = "Changed"
        let (store, state) = try fixture([JSONEncoder().encode(original), Data(), Data(), JSONEncoder().encode(updated)], codes: [200, 204, 403, 200])
        #expect(await store.save(name: "Changed", audioLanguage: "fra", subtitleLanguage: "") == .failed(.forbidden))
        #expect(store.profile?.name == "Changed")
        #expect(store.profile?.configuration?.audioLanguagePreference == "eng")
        #expect(store.currentUsernameAfterPartialSave == "Changed")
        #expect(!store.needsSaveReadback)
        #expect(store.errorMessage?.contains("username was saved") == true)
        #expect(state.requests.filter { $0.httpMethod == "POST" }.count == 2)
    }

    @Test("a partial profile write with unavailable readback blocks another save until reload")
    func partialUsernameNeedsReadback() async throws {
        let original = UserDto(id: "user", name: "Original")
        let updated = UserDto(id: "user", name: "Changed")
        let (store, state) = try fixture([JSONEncoder().encode(original), Data(), Data(), Data(), JSONEncoder().encode(updated)], codes: [200, 204, 403, 503, 200])
        #expect(await store.save(name: "Changed", audioLanguage: "fra", subtitleLanguage: "") == .uncertain)
        #expect(store.currentUsernameAfterPartialSave == nil)
        #expect(store.needsSaveReadback)
        #expect(await store.save(name: "Changed", audioLanguage: "fra", subtitleLanguage: "") == nil)
        #expect(state.requests.count == 4)
        await store.load()
        #expect(store.profile?.name == "Changed")
        #expect(!store.needsSaveReadback)
        #expect(store.saveOutcome == nil)
        #expect(state.requests.count == 5)
    }

    @Test("a canceled transmitted profile save requires readback only while its session remains active", arguments: ProfileCancellationScenario.allCases)
    func canceledProfileSave(scenario: ProfileCancellationScenario) async throws {
        let original = UserDto(configuration: UserConfiguration(audioLanguagePreference: "eng"), id: "user", name: "Original")
        let name = scenario.renames ? "Changed" : "Original"
        var canonical = original
        if scenario.accepted {
            if scenario.renames {
                canonical.name = name
            } else {
                canonical.configuration?.audioLanguagePreference = "fra"
            }
        }
        let (store, state) = try fixture([JSONEncoder().encode(original), JSONEncoder().encode(original), Data(), JSONEncoder().encode(canonical)])
        await store.load()
        state.suspendNextWrite()
        let saving = Task { await store.save(name: name, audioLanguage: "fra", subtitleLanguage: "") }
        while !state.hasSuspendedWrite {
            await Task.yield()
        }
        if scenario.retires {
            store.invalidate()
        }
        saving.cancel()
        state.finishSuspendedWrite(accepted: scenario.accepted)
        #expect(await saving.value == nil)
        #expect(store.saveOutcome == nil)
        #expect(store.profile?.name == "Original")
        #expect(store.profile?.configuration?.audioLanguagePreference == "eng")
        #expect(state.requests.filter { $0.httpMethod == "POST" }.count == 1)
        #expect(await store.save(name: name, audioLanguage: "fra", subtitleLanguage: "") == nil)
        #expect(state.requests.count == 3)
        if scenario.retires {
            #expect(!store.needsSaveReadback)
            await store.load()
            #expect(state.requests.count == 3)
        } else {
            #expect(store.needsSaveReadback)
            #expect(store.errorMessage != nil)
            await store.load()
            #expect(store.profile == canonical)
            #expect(!store.needsSaveReadback)
            #expect(store.saveOutcome == nil)
            #expect(state.requests.count == 4)
        }
    }

    @Test("Blank names never reach the server")
    func invalidName() async throws {
        let (store, state) = try fixture([])
        #expect(await store.save(name: "  ", audioLanguage: "", subtitleLanguage: "") == nil)
        #expect(state.requests.isEmpty)
    }

    @Test("accepted profile writes require canonical readback before reporting confirmation", arguments: [200, 503])
    func unconfirmedSave(status: Int) async throws {
        let original = UserDto(id: "user", name: "Eric")
        let (store, state) = try fixture(
            [JSONEncoder().encode(original), Data(), Data(), JSONEncoder().encode(original)],
            codes: [200, 204, 204, status]
        )
        #expect(await store.save(name: "Changed", audioLanguage: "eng", subtitleLanguage: "") == .uncertain)
        #expect(store.saveOutcome == .uncertain)
        #expect(store.errorMessage != nil)
        #expect(state.requests.filter { $0.httpMethod == "POST" }.count == 2)
    }

    @Test("An unavailable avatar does not turn a confirmed save into a failure", arguments: [404, 503])
    func avatarFailureAfterSave(status: Int) async throws {
        let old = UserDto(id: "user", name: "Eric", primaryImageTag: "old-tag")
        let updated = UserDto(configuration: UserConfiguration(audioLanguagePreference: "eng"), id: "user", name: "Updated", primaryImageTag: "new-tag")
        let (store, _) = try fixture(
            [JSONEncoder().encode(old), Data([1]), JSONEncoder().encode(old), Data(), Data(), JSONEncoder().encode(updated), Data()],
            codes: [200, 200, 200, 204, 204, 200, status]
        )
        await store.load()
        #expect(store.imageData == Data([1]))
        #expect(await store.save(name: "Updated", audioLanguage: "eng", subtitleLanguage: "") == .confirmed)
        #expect(store.profile?.name == "Updated")
        #expect(store.profile?.configuration?.audioLanguagePreference == "eng")
        #expect(store.imageData == nil)
        #expect(store.errorMessage == nil)
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

enum ProfileCancellationScenario: CaseIterable {
    case acceptedUsername, canceledUsername, acceptedPreferences, canceledPreferences, retiredAccepted, retiredCanceled

    var accepted: Bool {
        switch self {
        case .acceptedUsername, .acceptedPreferences, .retiredAccepted: true
        default: false
        }
    }

    var renames: Bool {
        self != .acceptedPreferences && self != .canceledPreferences
    }

    var retires: Bool {
        self == .retiredAccepted || self == .retiredCanceled
    }
}

private final class ProfileURLProtocol: URLProtocol {
    static let header = "X-Gus-Native-List-Fixture"
    static let states = OSAllocatedUnfairLock(initialState: [String: ProfileResponseState]())
    private let stopped = OSAllocatedUnfairLock(initialState: false)

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "jellyfin.example.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func stopLoading() {
        stopped.withLock { $0 = true }
    }

    override func startLoading() {
        do {
            let stateID = try #require(request.value(forHTTPHeaderField: Self.header))
            let state = try #require(Self.states.withLock { $0[stateID] })
            let response = try state.response(for: request)
            if state.suspendResponseIfNeeded(for: request, response: response, deliver: { [weak self] in self?.deliver($0) }) {
                return
            }
            deliver(.success(response))
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    private func deliver(_ result: Result<(Data, Int), Error>) {
        guard !stopped.withLock({ $0 }) else { return }
        do {
            let (data, statusCode) = try result.get()
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
    private var suspendsNextWrite = false
    private var suspendedResponse: ((Data, Int), (Result<(Data, Int), Error>) -> Void)?
    init(responses: [Data], statusCodes: [Int]?) {
        self.responses = responses
        self.statusCodes = statusCodes ?? responses.map { $0.isEmpty ? 204 : 200 }
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func suspendNextWrite() {
        lock.withLock { suspendsNextWrite = true }
    }

    var hasSuspendedWrite: Bool {
        lock.withLock { suspendedResponse != nil }
    }

    func suspendResponseIfNeeded(for request: URLRequest, response: (Data, Int), deliver: @escaping (Result<(Data, Int), Error>) -> Void) -> Bool {
        lock.withLock {
            guard suspendsNextWrite, request.httpMethod == "POST" else { return false }
            suspendsNextWrite = false
            suspendedResponse = (response, deliver)
            return true
        }
    }

    func finishSuspendedWrite(accepted: Bool) {
        let suspended = lock.withLock {
            let result = suspendedResponse
            suspendedResponse = nil
            return result
        }
        guard let (response, deliver) = suspended else { return }
        deliver(accepted ? .success(response) : .failure(CancellationError()))
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
