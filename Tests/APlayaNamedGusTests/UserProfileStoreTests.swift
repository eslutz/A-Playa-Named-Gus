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
        #expect(await store.save(name: "Eric Updated", audioLanguage: "eng", subtitleLanguage: "spa", currentPassword: "current") == .confirmed)
        #expect(store.profile?.name == "Eric Updated")
        let verification = try #require(state.verificationRequests.first)
        let credentials = try JSONDecoder().decode(AuthenticateUserByName.self, from: #require(verification.httpBody))
        #expect(credentials.username == "Eric")
        #expect(credentials.pw == "current")
        #expect(verification.url?.query == nil)
        #expect(verification.value(forHTTPHeaderField: "Authorization")?.contains("Token=") == false)
        #expect(verification.value(forHTTPHeaderField: "Authorization")?.contains("device-profile-verification") == true)
        #expect(state.verificationRequests.map { $0.url?.path } == ["/Users/AuthenticateByName", "/Sessions/Logout"])
        #expect(state.verificationRequests.last?.value(forHTTPHeaderField: "Authorization")?.contains("Token=verified") == true)
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
        #expect(await store.save(name: "Changed", audioLanguage: "", subtitleLanguage: "", currentPassword: "current") != .confirmed)
        #expect(store.profile?.name == "Eric")
        #expect(store.errorMessage != nil)
    }

    @Test("a saved username and denied preference write reports the confirmed partial result")
    func partialUsernameSave() async throws {
        let original = UserDto(configuration: UserConfiguration(audioLanguagePreference: "eng"), id: "user", name: "Original")
        var updated = original
        updated.name = "Changed"
        let (store, state) = try fixture([JSONEncoder().encode(original), Data(), Data(), JSONEncoder().encode(updated)], codes: [200, 204, 403, 200])
        #expect(await store.save(name: "Changed", audioLanguage: "fra", subtitleLanguage: "", currentPassword: "current") == .failed(.forbidden))
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
        #expect(await store.save(name: "Changed", audioLanguage: "fra", subtitleLanguage: "", currentPassword: "current") == .uncertain)
        #expect(store.currentUsernameAfterPartialSave == nil)
        #expect(store.needsSaveReadback)
        #expect(await store.save(name: "Changed", audioLanguage: "fra", subtitleLanguage: "", currentPassword: "current") == nil)
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
        let saving = Task { await store.save(name: name, audioLanguage: "fra", subtitleLanguage: "", currentPassword: "current") }
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
        #expect(await store.save(name: name, audioLanguage: "fra", subtitleLanguage: "", currentPassword: "current") == nil)
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
        #expect(await store.save(name: "  ", audioLanguage: "", subtitleLanguage: "", currentPassword: "current") == nil)
        #expect(state.requests.isEmpty)
    }

    @Test("accepted profile writes require canonical readback before reporting confirmation", arguments: [200, 503])
    func unconfirmedSave(status: Int) async throws {
        let original = UserDto(id: "user", name: "Eric")
        let (store, state) = try fixture(
            [JSONEncoder().encode(original), Data(), Data(), JSONEncoder().encode(original)],
            codes: [200, 204, 204, status]
        )
        #expect(await store.save(name: "Changed", audioLanguage: "eng", subtitleLanguage: "", currentPassword: "current") == .uncertain)
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
        #expect(await store.save(name: "Updated", audioLanguage: "eng", subtitleLanguage: "", currentPassword: "current") == .confirmed)
        #expect(store.profile?.name == "Updated")
        #expect(store.profile?.configuration?.audioLanguagePreference == "eng")
        #expect(store.imageData == nil)
        #expect(store.errorMessage == nil)
    }

    @Test("Missing or incorrect credentials prevent every profile write", arguments: ["", "incorrect"])
    func rejectedCredentials(password: String) async throws {
        let user = UserDto(id: "user", name: "Eric")
        let (store, state) = try fixture([JSONEncoder().encode(user)])
        let result = await store.save(
            name: "New Name",
            audioLanguage: "eng",
            subtitleLanguage: "fra",
            currentPassword: password,
            newPassword: "new",
            picture: .replace(Data([7]))
        )
        #expect(result != .confirmed)
        #expect(state.requests.allSatisfy { $0.httpMethod == "GET" })
        #expect(state.verificationRequests.count == (password.isEmpty ? 0 : 1))
        if !password.isEmpty {
            #expect(store.errorMessage?.contains("current password") == true)
        }
    }

    @Test("A verification for another account cannot authorize a write")
    func wrongIdentity() async throws {
        let user = UserDto(id: "user", name: "Eric")
        let (store, state) = try fixture([JSONEncoder().encode(user)], verificationUserID: "different")
        #expect(await store.save(name: "New Name", audioLanguage: "", subtitleLanguage: "", currentPassword: "current") == .failed(.forbidden))
        #expect(state.requests.allSatisfy { $0.httpMethod == "GET" })
        #expect(state.verificationRequests.last?.url?.path == "/Sessions/Logout")
    }

    @Test("Passwordless accounts can update their profile or set their first password", arguments: [true, false])
    func saveWithoutCurrentPassword(rename: Bool) async throws {
        let user = UserDto(hasPassword: false, id: "user", name: "Eric")
        let updated = UserDto(hasPassword: false, id: "user", name: "Updated")
        let original = try JSONEncoder().encode(user)
        let responses = try [original, original, Data()] + (rename ? [JSONEncoder().encode(updated), Data()] : [])
        let (store, state) = try fixture(responses, verificationPassword: "")
        await store.load()
        #expect(await store.save(name: rename ? "Updated" : "Eric", audioLanguage: "", subtitleLanguage: "", currentPassword: "", newPassword: "first") == .confirmed)
        #expect(store.profile?.hasPassword == true)
        #expect(state.verificationRequests.map { $0.url?.path } == (rename ? ["/Users/AuthenticateByName", "/Sessions/Logout"] : []))
        let request = try #require(state.requests.last)
        #expect(request.url?.path == "/Users/Password")
        let body = try JSONDecoder().decode(UpdateUserPassword.self, from: #require(request.httpBody))
        #expect(body.currentPw == "" && body.newPw == "first")
    }

    @Test("A password-only change uses Jellyfin's current-password check with the active user and token")
    func changePassword() async throws {
        let user = UserDto(id: "user", name: "Eric")
        let (store, state) = try fixture([JSONEncoder().encode(user), Data()])
        #expect(await store.save(
            name: "Eric",
            audioLanguage: "",
            subtitleLanguage: "",
            currentPassword: "current",
            newPassword: " new "
        ) == .confirmed)
        #expect(state.verificationRequests.isEmpty)
        let request = try #require(state.requests.last)
        #expect(request.url?.path == "/Users/Password")
        #expect(request.url?.query == "userId=user")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.contains("Token=token") == true)
        let body = try JSONDecoder().decode(UpdateUserPassword.self, from: #require(request.httpBody))
        #expect(body.currentPw == "current" && body.newPw == " new " && body.isResetPassword != true)
    }

    @Test("A rejected current password for a password-only edit keeps the original account")
    func deniedPasswordOnly() async throws {
        let user = UserDto(id: "user", name: "Eric")
        let json = try JSONEncoder().encode(user)
        let (store, state) = try fixture([json, Data(), json], codes: [200, 403, 200])
        #expect(await store.save(
            name: "Eric",
            audioLanguage: "",
            subtitleLanguage: "",
            currentPassword: "incorrect",
            newPassword: "new"
        ) == .failed(.forbidden))
        #expect(state.verificationRequests.isEmpty)
        #expect(store.profile?.name == "Eric")
        #expect(store.errorMessage?.contains("current password") == true)
        #expect(!store.needsSaveReadback)
    }

    @Test("When the last password write fails, confirmed preferences and photo remain saved")
    func passwordDeniedAfterEdits() async throws {
        let old = UserDto(id: "user", name: "Eric")
        let updated = UserDto(configuration: .init(audioLanguagePreference: "eng"), id: "user", name: "Eric", primaryImageTag: "new-tag")
        let saved = try JSONEncoder().encode(updated)
        let jpeg = Data([1, 2, 3])
        let (store, _) = try fixture(
            [JSONEncoder().encode(old), Data(), Data(), saved, jpeg, Data(), saved, jpeg],
            codes: [200, 204, 204, 200, 200, 403, 200, 200]
        )
        #expect(await store.save(
            name: "Eric",
            audioLanguage: "eng",
            subtitleLanguage: "",
            currentPassword: "current",
            newPassword: "new",
            picture: .replace(jpeg)
        ) == .failed(.forbidden))
        #expect(store.profile == updated)
        #expect(store.didSavePicture)
        #expect(store.imageData == jpeg)
        #expect(store.errorMessage?.contains("other profile changes were saved") == true)
    }

    @Test("Uploads a base64 JPEG, reads the changed image, then changes the password")
    func changePictureAndPassword() async throws {
        let old = UserDto(id: "user", name: "Eric")
        let updated = UserDto(id: "user", name: "Eric", primaryImageTag: "new-tag")
        let jpeg = Data([1, 2, 3, 4, 5])
        let (store, state) = try fixture([JSONEncoder().encode(old), Data(), JSONEncoder().encode(updated), jpeg, Data()])
        #expect(await store.save(
            name: "Eric",
            audioLanguage: "",
            subtitleLanguage: "",
            currentPassword: "current",
            newPassword: "new",
            picture: .replace(jpeg)
        ) == .confirmed)
        #expect(store.imageData == jpeg)
        #expect(state.requests.map { $0.url?.path } == ["/Users/user", "/UserImage", "/Users/user", "/UserImage", "/Users/Password"])
        let upload = state.requests[1]
        #expect(upload.url?.query == "userId=user")
        #expect(upload.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        #expect(upload.httpBody == jpeg.base64EncodedData())
    }

    @Test("Removing a profile photo requires authorization and canonical readback", arguments: [true, false])
    func removePicture(updated: Bool) async throws {
        let old = UserDto(id: "user", name: "Eric", primaryImageTag: "old")
        let current = updated ? UserDto(id: "user", name: "Eric") : old
        var responses = try [JSONEncoder().encode(old), Data(), JSONEncoder().encode(current)]
        if !updated {
            responses.append(Data([1]))
        }
        let (store, state) = try fixture(responses)
        let result = await store.save(name: "Eric", audioLanguage: "", subtitleLanguage: "", currentPassword: "current", picture: .remove)
        #expect(result == (updated ? .confirmed : .uncertain))
        #expect(store.didSavePicture == updated)
        #expect(store.needsSaveReadback != updated)
        #expect(state.verificationRequests.count == 2)
        let deletion = try #require(state.requests.first { $0.httpMethod == "DELETE" })
        #expect(deletion.url?.path == "/UserImage")
        #expect(deletion.url?.query == "userId=user")
    }

    @Test("Quick Connect submits exactly six ASCII digits for the signed-in account and prevents overlapping submissions")
    func quickConnectAuthorization() async throws {
        let (store, state) = try fixture([Data("true".utf8), Data("true".utf8)])
        #expect(await store.authorizeQuickConnect(code: "012345") == nil)
        await store.refreshQuickConnectAvailability()
        #expect(store.quickConnectEnabled)
        for invalid in ["", "12345", "1234567", "12 345", "12٣456"] {
            #expect(await store.authorizeQuickConnect(code: invalid) == nil)
        }
        state.suspendNextWrite()
        let first = Task { await store.authorizeQuickConnect(code: "012345") }
        while !state.hasSuspendedWrite {
            await Task.yield()
        }
        #expect(await store.authorizeQuickConnect(code: "012345") == nil)
        state.finishSuspendedWrite(accepted: true)
        #expect(await first.value == .authorized)
        #expect(state.requests.count == 2)
        let authorization = try #require(state.requests.last)
        #expect(authorization.url?.path == "/QuickConnect/Authorize")
        #expect(authorization.httpMethod == "POST")
        #expect(authorization.url?.query == "code=012345&userId=user")
        #expect(authorization.value(forHTTPHeaderField: "Authorization")?.contains("Token=token") == true)
    }

    @Test("Quick Connect honors server rejections, disabled state, uncertain results and session retirement")
    func quickConnectFailures() async throws {
        let (store, state) = try fixture(["false", "true", "false", "unreadable"].map { Data($0.utf8) })
        await store.refreshQuickConnectAvailability()
        #expect(!store.quickConnectEnabled)
        #expect(await store.authorizeQuickConnect(code: "012345") == nil)
        await store.refreshQuickConnectAvailability()
        #expect(await store.authorizeQuickConnect(code: "012345") == .rejected)
        #expect(await store.authorizeQuickConnect(code: "012345") == .unconfirmed)
        store.invalidate()
        #expect(await store.authorizeQuickConnect(code: "012345") == nil)
        #expect(state.requests.count == 4)
    }

    private func fixture(_ data: [Data], codes: [Int]? = nil, verificationUserID: String = "user", verificationPassword: String = "current") throws -> (UserProfileStore, ProfileResponseState) {
        let state = ProfileResponseState(responses: data, statusCodes: codes, verificationUserID: verificationUserID, verificationPassword: verificationPassword)
        let id = UUID().uuidString
        ProfileURLProtocol.states.withLock { $0[id] = state }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileURLProtocol.self]
        configuration.httpAdditionalHeaders = [ProfileURLProtocol.header: id]
        let client = try JellyfinClient(configuration: .init(url: #require(URL(string: "https://jellyfin.example.com")), accessToken: "token", client: "GusTests", deviceName: "Tests", deviceID: "device", version: "1"), sessionConfiguration: configuration)
        return (UserProfileStore(client: client, userID: "user", verificationSessionConfiguration: configuration), state)
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
    private var recordedVerification: [URLRequest] = []
    private let verificationUserID: String
    private let verificationPassword: String

    var verificationRequests: [URLRequest] {
        lock.withLock { recordedVerification }
    }

    private var statusCodes: [Int]
    private var suspendsNextWrite = false
    private var suspendedResponse: ((Data, Int), (Result<(Data, Int), Error>) -> Void)?
    init(responses: [Data], statusCodes: [Int]?, verificationUserID: String, verificationPassword: String) {
        self.verificationUserID = verificationUserID
        self.verificationPassword = verificationPassword
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
            guard suspendsNextWrite, request.httpMethod == "POST",
                  request.url?.path != "/Users/AuthenticateByName", request.url?.path != "/Sessions/Logout" else { return false }
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
        switch request.url?.path {
        case "/Users/AuthenticateByName":
            recordedVerification.append(request)
            let body = try JSONDecoder().decode(AuthenticateUserByName.self, from: request.httpBody ?? Data())
            guard body.pw == verificationPassword else { return (Data(), 401) }
            return try (JSONEncoder().encode(AuthenticationResult(accessToken: "verified", user: UserDto(id: verificationUserID))), 200)
        case "/Sessions/Logout":
            recordedVerification.append(request)
            return (Data(), 204)
        default:
            recorded.append(request)
        }
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
