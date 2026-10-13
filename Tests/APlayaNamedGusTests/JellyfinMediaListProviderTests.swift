import Foundation
@testable import Gus
import JellyfinAPI
import os
import Testing

@MainActor
@Suite("Native Jellyfin list requests")
struct JellyfinMediaListProviderTests {
    let listID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    let itemID = "c0000000000000000000000000000001"
    let entryID = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!

    @Test("Playlist loading fetches every page and preserves duplicate occurrence order")
    func playlistPagination() async throws {
        let list = ServerMediaListID.string(listID)
        let members = (0 ..< 200).map { index in
            BaseItemDto(id: itemID, playlistItemID: String(format: "b%031x", index + 1), type: .movie)
        }
        let fixture = try NativeListFixture(responses: [
            BaseItemDto(id: list, name: "Weekend", type: .playlist),
            PlaylistUserPermissions(canEdit: true, userID: "user"),
            BaseItemDtoQueryResult(items: members, totalRecordCount: 201),
            BaseItemDtoQueryResult(items: [BaseItemDto(id: itemID, playlistItemID: String(format: "b%031x", 255), type: .audio)], totalRecordCount: 201),
        ])
        let result = try await fixture.provider.mediaList(id: listID, kind: .playlist)
        #expect(result.canEdit)
        #expect(result.entriesLoaded)
        #expect(result.entries.count == 201)
        #expect(result.entries.last?.item.type == .audio)
        #expect(result.entries.first?.id == entryID)
        let requests = fixture.state.requests
        #expect(requests[2].url?.path == "/Playlists/\(list)/Items")
        #expect(query(requests[3])["startIndex"] == "200")
        #expect(query(requests[3])["userId"] == "user")
    }

    @Test("Read-only sharing remains readable without edit controls")
    func readOnlyPlaylist() async throws {
        let fixture = try NativeListFixture(responses: [
            BaseItemDto(id: ServerMediaListID.string(listID), name: "Shared", type: .playlist),
            PlaylistUserPermissions(canEdit: false, userID: "user"),
            BaseItemDtoQueryResult(items: [], totalRecordCount: 0),
        ])
        let result = try await fixture.provider.mediaList(id: listID, kind: .playlist)
        #expect(!result.canEdit)
        #expect(result.entriesLoaded)
    }

    @Test("Playlist mutation addresses occurrence ID in compact format and rename preserves membership")
    func playlistMutationRequests() async throws {
        let fixture = try NativeListFixture(emptyResponses: 3)
        try await fixture.provider.removeFromMediaList(id: listID, kind: .playlist, entryIDs: [entryID])
        try await fixture.provider.moveMediaListEntry(id: listID, entryID: entryID, to: 4)
        try await fixture.provider.renameMediaList(id: listID, kind: .playlist, name: "Renamed")
        let requests = fixture.state.requests
        #expect(query(requests[0])["entryIds"] == ServerMediaListID.string(entryID))
        #expect(requests[1].url?.path == "/Playlists/\(ServerMediaListID.string(listID))/Items/\(ServerMediaListID.string(entryID))/Move/4")
        let body = try JSONSerialization.jsonObject(with: bodyData(requests[2])) as? [String: Any]
        #expect(body?["Name"] as? String == "Renamed")
        #expect(body?["Ids"] == nil)
        #expect(body?["Users"] == nil)
        #expect(body?["IsPublic"] == nil)
    }

    @Test("Collections use BoxSet and current user policy rather than playlist ACL")
    func collectionPolicy() async throws {
        let fixture = try NativeListFixture(responses: [
            BaseItemDto(id: ServerMediaListID.string(listID), name: "Collection", type: .boxSet),
            UserDto(policy: UserPolicy(authenticationProviderID: "provider", enableCollectionManagement: false, isAdministrator: false, passwordResetProviderID: "reset")),
            BaseItemDtoQueryResult(items: [BaseItemDto(id: itemID, type: .movie)], totalRecordCount: 1),
        ])
        let result = try await fixture.provider.mediaList(id: listID, kind: .collection)
        #expect(!result.canEdit)
        #expect(result.entries.first?.id == ServerMediaListID.uuid(itemID))
        #expect(fixture.state.requests[1].url?.path == "/Users/user")
        #expect(query(fixture.state.requests[2])["parentId"] == ServerMediaListID.string(listID))
    }

    @Test("A rejected edit is a permission error rather than an expired session")
    func editPermissionFailure() async throws {
        let fixture = try NativeListFixture(statusCode: 403)
        do {
            try await fixture.provider.renameMediaList(id: listID, kind: .playlist, name: "Rejected")
            Issue.record("The server rejected this edit")
        } catch {
            let error = GusError(from: error)
            #expect(error != .unauthorized)
            guard case .server = error else { Issue.record("Expected a permission message"); return }
        }
    }

    @Test("Creating repeated native playlist members rejects before the server can silently deduplicate")
    func repeatedCreateFails() async throws {
        let fixture = try NativeListFixture(responses: [PlaylistCreationResult(id: ServerMediaListID.string(listID))])
        do {
            _ = try await fixture.provider.createMediaList(name: "Repeated", kind: .playlist, itemIDs: [itemID, itemID])
            Issue.record("Repeated input must remain local rather than silently lose an occurrence")
        } catch {
            guard case .server = GusError(from: error) else { Issue.record("Expected the native duplicate limitation"); return }
        }
        #expect(fixture.state.requests.isEmpty)
    }

    @Test("Adding an existing member rejects rather than projecting a server-unsupported duplicate")
    func repeatedAddFails() async throws {
        let fixture = try NativeListFixture(responses: [
            BaseItemDto(id: ServerMediaListID.string(listID), name: "Existing", type: .playlist),
            PlaylistUserPermissions(canEdit: true, userID: "user"),
            BaseItemDtoQueryResult(items: [BaseItemDto(id: itemID, playlistItemID: itemID, type: .movie)], totalRecordCount: 1),
        ])
        do {
            try await fixture.provider.addToMediaList(id: listID, kind: .playlist, itemIDs: [itemID])
            Issue.record("An existing member must not be added again")
        } catch {
            guard case .server = GusError(from: error) else { Issue.record("Expected the native duplicate limitation"); return }
        }
        #expect(fixture.state.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    private func query(_ request: URLRequest) -> [String: String] {
        Dictionary((URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, value in value })
    }
}

@MainActor
private struct NativeListFixture {
    let provider: JellyfinMediaProviderSession
    let state: NativeListResponseState
    let stateID: String

    init(responses: [any Encodable]) throws {
        try self.init(data: responses.map { try JSONEncoder().encode($0) })
    }

    init(emptyResponses: Int) throws {
        try self.init(data: Array(repeating: Data(), count: emptyResponses))
    }

    @MainActor
    init(statusCode: Int) throws {
        try self.init(data: [Data()], statusCodes: [statusCode])
    }

    private init(data: [Data], statusCodes: [Int]? = nil) throws {
        let fixtureState = NativeListResponseState(responses: data, statusCodes: statusCodes)
        let fixtureID = UUID().uuidString
        state = fixtureState
        stateID = fixtureID
        NativeListURLProtocol.states.withLock { $0[fixtureID] = fixtureState }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativeListURLProtocol.self]
        configuration.httpAdditionalHeaders = [NativeListURLProtocol.header: stateID]
        provider = try JellyfinMediaProviderSession(client: JellyfinClient(configuration: .init(url: #require(URL(string: "https://jellyfin.example.com")), accessToken: "token", client: "GusTests", deviceName: "Tests", deviceID: "device", version: "1"), sessionConfiguration: configuration), userID: "user")
    }
}

private final class NativeListURLProtocol: URLProtocol {
    static let header = "X-Gus-Native-List-Fixture"
    static let states = OSAllocatedUnfairLock(initialState: [String: NativeListResponseState]())

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

private final class NativeListResponseState: @unchecked Sendable {
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
