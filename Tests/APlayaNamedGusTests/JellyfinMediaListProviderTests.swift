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

    @Test("Virtual library types outside the OpenAPI enum keep every visible library")
    func extendedLibraryTypes() async throws {
        let fixture = try NativeListFixture(jsonResponses: [(#"""
        {"Items":[
          {"Id":"one","Name":"Movies","Type":"CollectionFolder","CollectionType":"movies"},
          {"Id":"two","Name":"Collections","Type":"UserView","CollectionType":"moviecollection","ImageTags":{"Primary":"art"},"MediaType":"PluginMedia"}
        ],"TotalRecordCount":2}
        """#, 200)])
        let libraries = try await fixture.provider.userViews()
        #expect(libraries.compactMap(\.id) == ["one", "two"])
        #expect(libraries.map(\.collectionType) == [.movies, .unknown])
        #expect(libraries.last?.imageTags["Primary"] == "art")
        #expect(fixture.state.requests.count == 1)
    }

    @Test("A newer person kind and an offset-less timestamp preserve collection members and ratings")
    func compatibleMemberMetadata() async throws {
        let fixture = try NativeListFixture(jsonResponses: [(#"""
        {"Items":[
          {"Id":"one","Name":"Feature","Type":"Movie","OfficialRating":"R","PremiereDate":"2025-08-03T18:24:59.1234567",
           "People":[{"Name":"Reader","Type":"Narrator","Role":"Narration"}],"UserData":{"PlayedPercentage":30}},
          {"Id":"two","Type":"Series","PremiereDate":"2025-08-03T14:24:59.1234567-04:00"}
        ],"TotalRecordCount":2}
        """#, 200)])
        let page = try await fixture.provider.collectionMembers(id: itemID, startIndex: 0, limit: 200)
        #expect(page.items.compactMap(\.id) == ["one", "two"])
        #expect(page.totalRecordCount == 2)
        #expect(page.items.first?.officialRating == "R")
        #expect(page.items.first?.people.first?.name == "Reader")
        #expect(page.items.first?.userData?.playedPercentage == 30)
        #expect(try page.items.first?.premiereDate == Date("2025-08-03T18:24:59.1234567Z", strategy: .iso8601))
        #expect(fixture.state.requests.count == 1)
    }

    @Test("Compatibility never conceals malformed rating data")
    func malformedMemberFailsPage() async throws {
        let fixture = try NativeListFixture(jsonResponses: [(#"{"Items":[{"Id":"one","CollectionType":"moviecollection","OfficialRating":false}]}"#, 200)])
        await #expect(throws: DecodingError.self) {
            try await fixture.provider.collectionMembers(id: itemID, startIndex: 0, limit: 200)
        }
    }

    @Test("A missing collection result cannot confirm an empty collection or a deletion")
    func missingCollectionRows() async throws {
        let fixture = try NativeListFixture(jsonResponses: [("{}", 200), (#"{"TotalRecordCount":0}"#, 200)])
        defer { fixture.finish() }
        await #expect(throws: GusError.self) { try await fixture.provider.collectionPage(startIndex: 0, limit: 200) }
        #expect(try await fixture.provider.collectionMembers(id: itemID, startIndex: 0, limit: 200).items.isEmpty)
    }

    @Test("Playlist loading fetches every page and preserves duplicate occurrence order")
    func playlistPagination() async throws {
        let list = ServerMediaListID.string(listID)
        let members = (0 ..< 200).map { index in
            BaseItemDto(id: itemID, playlistItemID: String(format: "b%031x", index + 1), type: .movie)
        }
        let fixture = try NativeListFixture(responses: [
            BaseItemDto(id: list, imageTags: ["Primary": "cover-tag"], name: "Weekend", type: .playlist),
            PlaylistUserPermissions(canEdit: true, userID: "user"),
            BaseItemDtoQueryResult(items: members, totalRecordCount: 201),
            BaseItemDtoQueryResult(items: [BaseItemDto(id: itemID, playlistItemID: String(format: "b%031x", 255), type: .audio)], totalRecordCount: 201),
        ])
        let result = try await fixture.provider.mediaList(id: listID, kind: .playlist)
        #expect(result.coverItem.id == list)
        #expect(result.coverItem.imageTags["Primary"] == "cover-tag")
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

    @Test("Collection-management permission does not grant metadata or artwork editing")
    func collectionPolicy() async throws {
        let fixture = try NativeListFixture(responses: [
            UserDto(policy: UserPolicy(authenticationProviderID: "provider", enableCollectionManagement: true, isAdministrator: false, passwordResetProviderID: "reset")),
            BaseItemDto(canDelete: false, id: ServerMediaListID.string(listID), name: "Collection", type: .boxSet),
        ])
        let result = try await fixture.provider.collectionCapabilities(id: ServerMediaListID.string(listID))
        #expect(result.create && result.addMembers && result.removeMembers)
        #expect(!result.editMetadata && !result.editArtwork && !result.delete)
        #expect(fixture.state.requests[0].url?.path == "/Users/user")
        #expect(fixture.state.requests[1].url?.path == "/Items/\(ServerMediaListID.string(listID))")
    }

    @Test("A successful creation without a usable collection ID has an unknown outcome", arguments: ["{}", "{\"Id\":\"invalid\"}"])
    func missingCreatedCollectionID(response: String) async throws {
        let fixture = try NativeListFixture(jsonResponses: [(response, 200)])
        defer { fixture.finish() }
        await #expect(throws: DecodingError.self) {
            try await fixture.provider.createCollection(name: "Reading", itemIDs: [itemID])
        }
        #expect(fixture.state.requests.count == 1)
    }

    @Test("Collection metadata updates preserve unedited fields")
    func collectionMetadataPreservation() async throws {
        let id = ServerMediaListID.string(listID)
        let original = """
        {"Id":"\(id)","Name":"Old","Type":"BoxSet","Overview":"Old description","Genres":["Fantasy"],"Taglines":["Preserved"]}
        """
        let updated = original.replacingOccurrences(of: "Old", with: "New")
        let fixture = try NativeListFixture(jsonResponses: [seriesUser(admin: true), (original, 200), ("", 204), (updated, 200)])
        defer { fixture.finish() }
        try await fixture.provider.editMediaListMetadata(
            .collection(id),
            name: "New",
            expectedName: "Old",
            overview: "New description",
            expectedOverview: "Old description"
        )
        let write = try #require(fixture.state.requests.first { $0.httpMethod == "POST" })
        let body = try JSONSerialization.jsonObject(with: bodyData(write)) as? [String: Any]
        #expect(body?["Name"] as? String == "New")
        #expect(body?["Overview"] as? String == "New description")
        #expect(body?["Genres"] as? [String] == ["Fantasy"])
        #expect(body?["Taglines"] as? [String] == ["Preserved"])
    }

    private func seriesUser(admin: Bool) throws -> (String, Int) {
        let user = UserDto(policy: UserPolicy(authenticationProviderID: "provider", enableCollectionManagement: true, isAdministrator: admin, passwordResetProviderID: "reset"))
        return try (String(decoding: JSONEncoder().encode(user), as: UTF8.self), 200)
    }

    @Test("Playlist descriptions use elevated item metadata and preserve unrelated fields")
    func playlistDescriptionWrite() async throws {
        let id = ServerMediaListID.string(listID)
        let original = """
        {"Id":"\(id)","Name":"Playlist","Type":"Playlist","Overview":"Before","FutureMetadata":{"Field":"Preserved"}}
        """
        let cleared = original.replacingOccurrences(of: "Before", with: "")
        let fixture = try NativeListFixture(jsonResponses: [
            seriesUser(admin: true), (#"{"CanEdit":true}"#, 200), (original, 200), ("", 204), (cleared, 200),
        ])
        defer { fixture.finish() }
        try await fixture.provider.editMediaListMetadata(
            .playlist(listID),
            name: nil,
            expectedName: "Playlist",
            overview: "",
            expectedOverview: "Before"
        )
        let write = try #require(fixture.state.requests.first { $0.httpMethod == "POST" })
        #expect(write.url?.path == "/Items/\(id)")
        let body = try #require(JSONSerialization.jsonObject(with: bodyData(write)) as? NSDictionary)
        let expected = try #require(JSONSerialization.jsonObject(with: Data(cleared.utf8)) as? NSDictionary)
        #expect(body == expected)
    }

    @Test("A changed collection description is preserved without a write")
    func collectionDescriptionConflict() async throws {
        let original = """
        {"Id":"\(itemID)","Name":"Collection","Type":"BoxSet","Overview":"Someone else's update"}
        """
        let fixture = try NativeListFixture(jsonResponses: [seriesUser(admin: true), (original, 200)])
        defer { fixture.finish() }
        await #expect(throws: GusError.self) {
            try await fixture.provider.editMediaListMetadata(
                .collection(itemID),
                name: nil,
                expectedName: "Collection",
                overview: "My edit",
                expectedOverview: "Before"
            )
        }
        #expect(fixture.state.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test("Removing a playlist cover deletes only Primary and confirms the updated tag")
    func playlistCoverRemoval() async throws {
        let id = ServerMediaListID.string(listID)
        let original = """
        {"Id":"\(id)","Name":"Playlist","Type":"Playlist","ImageTags":{"Primary":"old","Thumb":"kept"}}
        """
        let cleared = original.replacingOccurrences(of: #""Primary":"old","#, with: "")
        let fixture = try NativeListFixture(jsonResponses: [
            seriesUser(admin: true), (#"{"CanEdit":true}"#, 200), (original, 200), ("", 204), (cleared, 200),
        ])
        defer { fixture.finish() }
        try await fixture.provider.editMediaListCover(.playlist(listID), change: .remove, expectedTag: "old")
        let write = try #require(fixture.state.requests.first { $0.httpMethod == "DELETE" })
        #expect(write.url?.path == "/Items/\(id)/Images/Primary")
        #expect(fixture.state.requests.last?.httpMethod == "GET")
    }

    @Test("Ebook series writes preserve the full item and confirm Jellyfin's response")
    func ebookSeriesWrite() async throws {
        let original = """
        {"Id":"\(itemID)","Name":"Book One","Type":"Book","IndexNumber":4,"SeriesName":"Original",
        "LockedFields":["Cast"],"FutureMetadata":{"Field":"Preserved"},"People":[{"Name":"Someone","Type":"FutureKind"}]}
        """
        let updated = original.replacingOccurrences(of: "Original", with: "New Name")
        let fixture = try NativeListFixture(jsonResponses: [
            (#"{"Version":"12.4.0"}"#, 200), seriesUser(admin: true), (original, 200), ("", 204), (updated, 200),
        ])
        defer { fixture.finish() }
        #expect(try await fixture.provider.canEditBookSeries())
        try await fixture.provider.setBookSeries(itemID: itemID, from: "Original", to: "New Name")
        let writes = fixture.state.requests.filter { $0.httpMethod == "POST" }
        let post = try #require(writes.first)
        #expect(writes.count == 1)
        #expect(post.url?.path == "/Items/\(itemID)")
        let expected = try #require(JSONSerialization.jsonObject(with: Data(updated.utf8)) as? NSDictionary)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData(post)) as? NSDictionary)
        #expect(expected == body)
        #expect(fixture.state.requests.last?.httpMethod == "GET")
    }

    @Test("Series removal sends an empty string and accepts a missing series on readback")
    func ebookSeriesRemoval() async throws {
        let clear = #"{"Id":"\#(itemID)","Name":"Book","Type":"Book"}"#
        let current = #"{"Id":"\#(itemID)","Name":"Book","Type":"Book","SeriesName":"Series"}"#
        let fixture = try NativeListFixture(jsonResponses: [
            (#"{"Version":"12.4"}"#, 200), seriesUser(admin: true), (current, 200), ("", 204), (clear, 200),
        ])
        defer { fixture.finish() }
        #expect(try await fixture.provider.canEditBookSeries())
        try await fixture.provider.setBookSeries(itemID: itemID, from: "Series", to: nil)
        let post = try #require(fixture.state.requests.first { $0.httpMethod == "POST" })
        let body = try #require(JSONSerialization.jsonObject(with: bodyData(post)) as? [String: Any])
        #expect(body["SeriesName"] as? String == "")
    }

    @Test("Unsupported servers and accounts cannot edit book series")
    func ebookSeriesPermissions() async throws {
        for (version, admin) in [("10.11.11", true), ("12.0-rc1", true), ("12.4.0", false)] {
            let fixture = try NativeListFixture(jsonResponses: [
                (#"{"Version":"\#(version)"}"#, 200), seriesUser(admin: admin),
            ])
            defer { fixture.finish() }
            #expect(try await !fixture.provider.canEditBookSeries())
            await #expect(throws: GusError.forbidden) {
                try await fixture.provider.setBookSeries(itemID: itemID, from: nil, to: "Series")
            }
            #expect(!fixture.state.requests.contains { $0.httpMethod == "POST" })
        }
    }

    @Test("A stale series membership or audiobook response blocks the metadata write")
    func ebookSeriesStaleOrUnsupportedItem() async throws {
        for kind in ["Book", "AudioBook"] {
            let fixture = try NativeListFixture(jsonResponses: [
                (#"{"Version":"12.4"}"#, 200), seriesUser(admin: true),
                (#"{"Id":"\#(itemID)","Type":"\#(kind)","Name":"Title","SeriesName":"Other"}"#, 200),
            ])
            defer { fixture.finish() }
            #expect(try await fixture.provider.canEditBookSeries())
            await #expect(throws: GusError.self) {
                try await fixture.provider.setBookSeries(itemID: itemID, from: nil, to: "New")
            }
            #expect(!fixture.state.requests.contains { $0.httpMethod == "POST" })
        }
    }

    @Test("An ignored edit surfaces a verification failure and never repeats the POST")
    func ebookSeriesIgnored() async throws {
        let book = #"{"Id":"\#(itemID)","Type":"Book","Name":"Unassigned"}"#
        let fixture = try NativeListFixture(jsonResponses: [
            (#"{"Version":"12.0"}"#, 200), seriesUser(admin: true), (book, 200), ("", 204), (book, 200),
        ])
        defer { fixture.finish() }
        #expect(try await fixture.provider.canEditBookSeries())
        await #expect(throws: GusError.self) {
            try await fixture.provider.setBookSeries(itemID: itemID, from: nil, to: "Series")
        }
        #expect(fixture.state.requests.filter { $0.httpMethod == "POST" }.count == 1)
    }

    @Test("The ebook editor offers name-only volumes and reserves ID-backed group names")
    func ebookSeriesAssignmentScope() {
        let scope = BookSeriesEditScope([
            MediaItem(id: "a", seriesID: "123", seriesName: "First Saga", type: .book),
            MediaItem(id: "b", seriesID: "456", seriesName: "FIRST   SAGA", type: .book),
            MediaItem(id: "c", seriesID: "789", seriesName: "Single ID", type: .book),
            MediaItem(id: "d", seriesName: "Name Only", type: .book),
            MediaItem(id: "e", seriesID: "00000000-0000-0000-0000-000000000000", type: .book),
            MediaItem(id: "f", seriesID: "123", seriesName: "Audio Only", type: .audioBook),
        ])
        #expect(scope.editableBooks.compactMap(\.id) == ["d", "e"])
        #expect(!scope.allowsAssignment(to: "  first Saga "))
        #expect(!scope.allowsAssignment(to: "Single ID"))
        #expect(scope.allowsAssignment(to: "Name Only"))
        #expect(scope.allowsAssignment(to: "Audio Only"))
    }

    @Test("An ID-backed volume cannot be moved, and an ID appearing on readback prevents a false success")
    func ebookSeriesIDVerification() async throws {
        let free = #"{"Id":"\#(itemID)","Type":"Book","Name":"Volume"}"#
        let grouped = #"{"Id":"\#(itemID)","Type":"Book","Name":"Volume","SeriesName":"Selected","SeriesId":"11111111111111111111111111111111"}"#
        for idBeforeWrite in [true, false] {
            let fixture = try NativeListFixture(jsonResponses: [
                (#"{"Version":"12.4"}"#, 200), seriesUser(admin: true),
                (idBeforeWrite ? grouped : free, 200), ("", 204), (grouped, 200),
            ])
            defer { fixture.finish() }
            #expect(try await fixture.provider.canEditBookSeries())
            await #expect(throws: GusError.self) {
                try await fixture.provider.setBookSeries(itemID: itemID, from: idBeforeWrite ? "Selected" : nil, to: idBeforeWrite ? "Moved" : "Selected")
            }
            #expect(fixture.state.requests.filter { $0.httpMethod == "POST" }.count == (idBeforeWrite ? 0 : 1))
        }
    }

    @Test("Artwork uses base64 JPEG through the SDK transport")
    func collectionArtworkRequest() async throws {
        let id = ServerMediaListID.string(listID)
        let original = """
        {"Id":"\(id)","Name":"Collection","Type":"BoxSet"}
        """
        let updated = """
        {"Id":"\(id)","Name":"Collection","Type":"BoxSet","ImageTags":{"Primary":"uploaded"}}
        """
        let fixture = try NativeListFixture(jsonResponses: [seriesUser(admin: true), (original, 200), ("", 204), (updated, 200)])
        defer { fixture.finish() }
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        try await fixture.provider.editMediaListCover(.collection(id), change: .replace(jpeg), expectedTag: nil)
        let request = try #require(fixture.state.requests.first { $0.httpMethod == "POST" })
        #expect(request.url?.path == "/Items/\(ServerMediaListID.string(listID))/Images/Primary")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        #expect(try bodyData(request) == jpeg.base64EncodedData())
    }

    @Test("A collection deletion cannot target a movie")
    func collectionDeletionRejectsMovie() async throws {
        let fixture = try NativeListFixture(responses: [BaseItemDto(canDelete: true, id: ServerMediaListID.string(listID), type: .movie)])
        await #expect(throws: GusError.notFound) { try await fixture.provider.deleteCollection(id: ServerMediaListID.string(listID)) }
        #expect(fixture.state.requests.count == 1)
        #expect(fixture.state.requests[0].httpMethod == "GET")
    }

    @Test("Collection members use media IDs rather than playlist occurrence IDs")
    func collectionMemberRequest() async throws {
        let id = ServerMediaListID.string(listID)
        let fixture = try NativeListFixture(responses: [BaseItemDto(id: id, type: .boxSet)], emptyResponses: 1)
        try await fixture.provider.removeCollectionMembers(id: id, itemIDs: [itemID])
        #expect(fixture.state.requests[1].url?.path == "/Collections/\(id)/Items")
        #expect(query(fixture.state.requests[1])["ids"] == itemID)
        #expect(query(fixture.state.requests[1])["entryIds"] == nil)
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
@Suite("Native Jellyfin Live TV availability")
struct JellyfinLiveTVProviderTests {
    enum Capability: CaseIterable, Sendable {
        case member, noTuner, otherUsers, noService, denied
    }

    enum Missing: CaseIterable, Sendable {
        case policy, permission, identity, wrongIdentity, enabledFlag, enabledUsers, nullUsers, malformedUsers
    }

    enum Status: CaseIterable, Sendable {
        case userUnauthorized, userForbidden, infoUnauthorized, infoForbidden
    }

    enum HeldRead: CaseIterable, Sendable {
        case user, info
        var path: String {
            self == .user ? "/Users/user" : "/LiveTv/Info"
        }
    }

    private let allowedUser = #"{"Id":"user","Policy":{"AuthenticationProviderId":"fixture-provider","PasswordResetProviderId":"fixture-reset","EnableLiveTvAccess":true,"EnableLiveTvManagement":false}}"#
    private let enabledInfo = #"{"IsEnabled":true,"EnabledUsers":["user"],"Services":[{"Name":"Emby"}]}"#

    @Test("Live TV capability uses actual permission and enabled-user JSON", arguments: Capability.allCases)
    func availabilityJSON(_ scenario: Capability) async throws {
        let user = scenario == .denied ? allowedUser.replacingOccurrences(of: "\"EnableLiveTvAccess\":true", with: "\"EnableLiveTvAccess\":false") : allowedUser
        let info: String = switch scenario {
        case .noTuner: #"{"IsEnabled":true,"EnabledUsers":[],"Services":[{"Name":"Emby"}]}"#
        case .otherUsers: #"{"IsEnabled":true,"EnabledUsers":["other"]}"#
        case .noService: #"{"IsEnabled":false,"EnabledUsers":[]}"#
        default: enabledInfo
        }
        let fixture = try NativeListFixture(jsonResponses: scenario == .denied ? [(user, 200)] : [(user, 200), (info, 200)])
        defer { fixture.finish() }
        let result = try await fixture.provider.liveTVAvailability()
        let expected: LiveTVAvailability = switch scenario {
        case .member: .enabled
        case .noTuner, .noService: .notConfigured
        case .otherUsers, .denied: .restricted
        }
        #expect(result == expected)
        #expect(fixture.state.requests.map { $0.url?.path } == (scenario == .denied ? ["/Users/user"] : ["/Users/user", "/LiveTv/Info"]))
        #expect(fixture.state.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test("Missing or malformed Live TV metadata never becomes a capability result", arguments: Missing.allCases)
    func incompleteJSON(_ scenario: Missing) async throws {
        var user = allowedUser
        var info = enabledInfo
        let failsDuringUser: Bool
        switch scenario {
        case .policy: user = #"{"Id":"user"}"#; failsDuringUser = true
        case .permission: user = allowedUser.replacingOccurrences(of: ",\"EnableLiveTvAccess\":true", with: ""); failsDuringUser = true
        case .identity: user = allowedUser.replacingOccurrences(of: "\"Id\":\"user\",", with: ""); failsDuringUser = true
        case .wrongIdentity: user = allowedUser.replacingOccurrences(of: "\"Id\":\"user\"", with: "\"Id\":\"other\""); failsDuringUser = true
        case .enabledFlag: info = #"{"EnabledUsers":["user"]}"#; failsDuringUser = false
        case .enabledUsers: info = #"{"IsEnabled":true}"#; failsDuringUser = false
        case .nullUsers: info = #"{"IsEnabled":true,"EnabledUsers":null}"#; failsDuringUser = false
        case .malformedUsers: info = #"{"IsEnabled":true,"EnabledUsers":"user"}"#; failsDuringUser = false
        }
        let fixture = try NativeListFixture(jsonResponses: failsDuringUser ? [(user, 200)] : [(user, 200), (info, 200)])
        defer { fixture.finish() }
        do {
            _ = try await fixture.provider.liveTVAvailability()
            Issue.record("Incomplete data must not become enabled, restricted or not configured")
        } catch {
            #expect(error is GusError)
            let failure = GusError(from: error)
            if scenario == .malformedUsers {
                guard case .unknown = failure else { Issue.record("Expected the SDK decoding failure"); return }
            } else {
                guard case .server = failure else { Issue.record("Expected an unverified server response"); return }
            }
        }
        #expect(fixture.state.requests.count == (failsDuringUser ? 1 : 2))
    }

    @Test("Live TV permission denial stays distinct from expired credentials", arguments: Status.allCases)
    func statusErrors(_ scenario: Status) async throws {
        let duringInfo = scenario == .infoUnauthorized || scenario == .infoForbidden
        let forbidden = scenario == .userForbidden || scenario == .infoForbidden
        let replies = (duringInfo ? [(allowedUser, 200)] : []) + [("", forbidden ? 403 : 401)]
        let fixture = try NativeListFixture(jsonResponses: replies)
        defer { fixture.finish() }
        if forbidden {
            #expect(try await fixture.provider.liveTVAvailability() == .restricted)
        } else {
            await #expect(throws: GusError.unauthorized) { try await fixture.provider.liveTVAvailability() }
        }
        #expect(fixture.state.requests.count == (duringInfo ? 2 : 1))
    }

    @Test("Canceling either Live TV read stops the transport and further capability work", arguments: HeldRead.allCases)
    func canceledRead(_ held: HeldRead) async throws {
        let fixture = try NativeListFixture(jsonResponses: [(allowedUser, 200), (enabledInfo, 200)], suspendedPaths: [held.path])
        let operation = Task { try await fixture.provider.liveTVAvailability() }
        defer { operation.cancel(); fixture.finish() }
        try await waitUntil { fixture.state.hasPending(path: held.path) }
        operation.cancel()
        do {
            _ = try await operation.value
            Issue.record("A canceled read must not publish availability")
        } catch { #expect(GusError(from: error) == .cancelled) }
        try await waitUntil { fixture.state.hasStopped(path: held.path) }
        #expect(fixture.state.requests.count == (held == .user ? 1 : 2))
    }

    @Test("Live TV reads share one 30-second budget instead of sequential read budgets")
    func combinedReadDeadline() async throws {
        let fixture = try NativeListFixture(jsonResponses: [(allowedUser, 200), (enabledInfo, 200)], suspendedPaths: ["/Users/user", "/LiveTv/Info"])
        let outcome = OSAllocatedUnfairLock(initialState: Result<LiveTVAvailability, GusError>?.none)
        let started = ContinuousClock.now
        let operation = Task {
            do {
                let value = try await fixture.provider.liveTVAvailability()
                outcome.withLock { $0 = .success(value) }
            } catch { outcome.withLock { $0 = .failure(GusError(from: error)) } }
        }
        defer { operation.cancel(); fixture.finish() }
        try await waitUntil { fixture.state.hasPending(path: "/Users/user") }
        // Spend part of the shared budget on the first actual HTTP read. An
        // instant first read cannot distinguish a total 30s from per-read 30s cap.
        try await Task.sleep(for: .seconds(10))
        fixture.state.release(path: "/Users/user")
        try await waitUntil { fixture.state.hasPending(path: "/LiveTv/Info") }
        let deadline = started + .seconds(35)
        while outcome.withLock({ $0 == nil }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let elapsed = started.duration(to: .now)
        let result = try #require(outcome.withLock { $0 }, "The total Live TV read budget did not finish by 35s")
        guard case let .failure(error) = result else { Issue.record("A held transport cannot confirm availability"); return }
        #expect(error == .timeout)
        #expect(elapsed >= .seconds(29) && elapsed < .seconds(35))
        try await waitUntil { fixture.state.hasStopped(path: "/LiveTv/Info") }
        #expect(fixture.state.requests.map { $0.url?.path } == ["/Users/user", "/LiveTv/Info"])
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "The expected HTTP fixture phase was not reached")
    }
}

@MainActor
private struct NativeListFixture {
    let provider: JellyfinMediaProviderSession
    let state: NativeListResponseState
    let stateID: String

    init(responses: [any Encodable], emptyResponses: Int = 0) throws {
        try self.init(data: responses.map { try JSONEncoder().encode($0) } + Array(repeating: Data(), count: emptyResponses))
    }

    init(emptyResponses: Int) throws {
        try self.init(data: Array(repeating: Data(), count: emptyResponses))
    }

    @MainActor
    init(statusCode: Int) throws {
        try self.init(data: [Data()], statusCodes: [statusCode])
    }

    init(jsonResponses: [(String, Int)], suspendedPaths: Set<String> = []) throws {
        try self.init(data: jsonResponses.map { Data($0.0.utf8) }, statusCodes: jsonResponses.map(\.1), suspendedPaths: suspendedPaths)
    }

    private init(data: [Data], statusCodes: [Int]? = nil, suspendedPaths: Set<String> = []) throws {
        let fixtureState = NativeListResponseState(responses: data, statusCodes: statusCodes, suspendedPaths: suspendedPaths)
        let fixtureID = UUID().uuidString
        state = fixtureState
        stateID = fixtureID
        NativeListURLProtocol.states.withLock { $0[fixtureID] = fixtureState }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativeListURLProtocol.self]
        configuration.httpAdditionalHeaders = [NativeListURLProtocol.header: stateID]
        provider = try JellyfinMediaProviderSession(client: JellyfinClient(configuration: .init(url: #require(URL(string: "https://jellyfin.example.com")), accessToken: "token", client: "GusTests", deviceName: "Tests", deviceID: "device", version: "1"), sessionConfiguration: configuration), userID: "user")
    }

    func finish() {
        state.releaseAll()
        NativeListURLProtocol.states.withLock { $0[stateID] = nil }
    }
}

private final class NativeListURLProtocol: URLProtocol {
    static let header = "X-Gus-Native-List-Fixture"
    static let states = OSAllocatedUnfairLock(initialState: [String: NativeListResponseState]())
    private let stopped = OSAllocatedUnfairLock(initialState: false)

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "jellyfin.example.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func stopLoading() {
        stopped.withLock { $0 = true }
        if let stateID = request.value(forHTTPHeaderField: Self.header), let state = Self.states.withLock({ $0[stateID] }) {
            state.recordStop(path: request.url?.path ?? "")
        }
    }

    override func startLoading() {
        do {
            let stateID = try #require(request.value(forHTTPHeaderField: Self.header))
            let state = try #require(Self.states.withLock { $0[stateID] })
            let response = try state.response(for: request)
            if state.suspendIfNeeded(path: request.url?.path ?? "", response: response, deliver: { [weak self] in self?.deliver($0) }) {
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

private final class NativeListResponseState: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Data]
    private var recorded: [URLRequest] = []
    private var statusCodes: [Int]
    private var suspendedPaths: Set<String>
    private var stoppedPaths: Set<String> = []
    private var pending: [String: (response: (Data, Int), deliver: (Result<(Data, Int), Error>) -> Void)] = [:]

    init(responses: [Data], statusCodes: [Int]?, suspendedPaths: Set<String> = []) {
        self.responses = responses
        self.statusCodes = statusCodes ?? responses.map { $0.isEmpty ? 204 : 200 }
        self.suspendedPaths = suspendedPaths
    }

    func suspendIfNeeded(path: String, response: (Data, Int), deliver: @escaping (Result<(Data, Int), Error>) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard suspendedPaths.contains(path), !stoppedPaths.contains(path) else { return false }
        pending[path] = (response, deliver)
        return true
    }

    func hasPending(path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pending[path] != nil
    }

    func hasStopped(path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stoppedPaths.contains(path)
    }

    func recordStop(path: String) {
        lock.lock(); defer { lock.unlock() }
        stoppedPaths.insert(path)
        pending.removeValue(forKey: path)
    }

    func release(path: String) {
        lock.lock()
        let reply = pending.removeValue(forKey: path)
        suspendedPaths.remove(path)
        lock.unlock()
        if let reply {
            reply.deliver(.success(reply.response))
        }
    }

    func releaseAll() {
        lock.lock()
        let replies = Array(pending.values)
        pending.removeAll()
        suspendedPaths.removeAll()
        lock.unlock()
        for reply in replies {
            reply.deliver(.failure(URLError(.cancelled)))
        }
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
