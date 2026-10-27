import Foundation
@testable import Gus
import JellyfinAPI
import os
import Testing

@Suite("Library store helpers", .serialized)
struct LibraryStoreTests {
    @Test("iPhone music browse requests albums and artists without video playlists")
    func musicScope() {
        let query = LibraryRequest.parameters(scope: .musicLibrary(parentID: "music"), startIndex: 60, limit: 60)
        #expect(query.parentID == "music")
        #expect(query.includeTypes == [.musicAlbum, .musicArtist])
        #expect(query.isRecursive)
        #expect(query.startIndex == 60)
        #expect(LibraryGridScope.musicLibrary(parentID: "music").storeIdentity != LibraryGridScope.category(.music).storeIdentity)
    }

    @Test("photo albums and all photos query separate paged scopes")
    func photoScopes() {
        let albums = LibraryRequest.parameters(scope: .photoLibrary(parentID: "photos", albums: true), startIndex: 60, limit: 60)
        let images = LibraryRequest.parameters(scope: .photoLibrary(parentID: "photos", albums: false), startIndex: 0, limit: 60)
        #expect(albums.parentID == "photos")
        #expect(albums.includeTypes == [.photoAlbum])
        #expect(images.includeTypes == [.photo])
        #expect(albums.isRecursive)
        #expect(albums.startIndex == 60)
        #expect(LibraryGridScope.photoLibrary(parentID: "photos", albums: true).storeIdentity != LibraryGridScope.photoLibrary(parentID: "photos", albums: false).storeIdentity)
        let mapped = JellyfinMediaItemMapper.mediaItem(from: BaseItemDto(id: "album", name: "Pictures", type: .photoAlbum))
        #expect(mapped.type == .photoAlbum)
    }

    @Test("builds paged provider library queries")
    func buildsPagedLibraryQuery() {
        let query = LibraryRequest.parameters(
            scope: .library(mediaItem(id: "library-1")),
            startIndex: 60,
            limit: 60
        )

        #expect(query.parentID == "library-1")
        #expect(query.startIndex == 60)
        #expect(query.limit == 60)
        #expect(query.isRecursive == false)
        #expect(query.sort == .name)
        #expect(query.statusFilter == .all)
    }

    @Test("builds recursive provider category queries")
    func buildsRecursiveCategoryQuery() {
        let query = LibraryRequest.parameters(
            scope: .category(.movies),
            startIndex: 0,
            limit: 60
        )

        #expect(query.parentID == nil)
        #expect(query.includeTypes == [.movie])
        #expect(query.startIndex == 0)
        #expect(query.limit == 60)
        #expect(query.isRecursive == true)
        #expect(query.sort == .name)
        #expect(query.statusFilter == .all)
    }

    @Test("applies status filters and sort options to library queries")
    func appliesStatusFiltersAndSortOptions() {
        let query = LibraryRequest.parameters(
            scope: .library(mediaItem(id: "library-1")),
            startIndex: 0,
            limit: 60,
            filter: LibraryFilterState(sort: .recentlyAdded, status: .unplayed)
        )

        #expect(query.sort == .recentlyAdded)
        #expect(query.statusFilter == .unplayed)
    }

    @Test("builds resumable and random filter queries")
    func buildsResumableAndRandomFilterQueries() {
        let query = LibraryRequest.parameters(
            scope: .library(mediaItem(id: "library-1")),
            startIndex: 0,
            limit: 60,
            filter: LibraryFilterState(sort: .random, status: .resumable)
        )

        #expect(query.sort == .random)
        #expect(query.statusFilter == .resumable)
    }

    @Test("status filters do not include favorites")
    func statusFiltersDoNotIncludeFavorites() {
        #expect(LibraryStatusFilter.allCases.map(\.rawValue).contains("favorites") == false)
    }

    @MainActor
    @Test("provider item queries omit sort parameters when unsorted")
    func providerItemQueriesOmitSortParametersWhenUnsorted() async throws {
        LibraryItemsURLProtocol.configure(responses: [
            .init(result: BaseItemDtoQueryResult(items: [], totalRecordCount: 0)),
        ])

        let session = try libraryTestSession()

        _ = try await session.mediaProvider.items(query: MediaItemQuery(
            searchTerm: "psych",
            startIndex: 0,
            limit: 20,
            isRecursive: true,
            sort: nil
        ))

        let request = try #require(LibraryItemsURLProtocol.recordedRequests.first)
        #expect(request.searchTerm == "psych")
        #expect(request.sortBy == nil)
        #expect(request.sortOrder == nil)
    }

    @MainActor
    @Test("provider item queries keep explicit name sort parameters")
    func providerItemQueriesKeepExplicitNameSortParameters() async throws {
        LibraryItemsURLProtocol.configure(responses: [
            .init(result: BaseItemDtoQueryResult(items: [], totalRecordCount: 0)),
        ])

        let session = try libraryTestSession()

        _ = try await session.mediaProvider.items(query: MediaItemQuery(
            parentID: "library-1",
            startIndex: 0,
            limit: 20,
            sort: .name
        ))

        let request = try #require(LibraryItemsURLProtocol.recordedRequests.first)
        #expect(request.parentID == "library-1")
        #expect(request.sortBy == "SortName")
        #expect(request.sortOrder == "Ascending")
    }

    @MainActor
    @Test("ignores stale next page responses after filter changes")
    func ignoresStaleNextPageResponsesAfterFilterChanges() async throws {
        LibraryItemsURLProtocol.configure(responses: [
            .init(
                result: BaseItemDtoQueryResult(
                    items: libraryItems(prefix: "old", range: 0 ..< 60),
                    startIndex: 0,
                    totalRecordCount: 120
                )
            ),
            .init(
                result: BaseItemDtoQueryResult(
                    items: libraryItems(prefix: "stale", range: 60 ..< 120),
                    startIndex: 60,
                    totalRecordCount: 120
                ),
                delayNanoseconds: 200_000_000
            ),
            .init(
                result: BaseItemDtoQueryResult(
                    items: [libraryDTO(id: "filtered-0")],
                    startIndex: 0,
                    totalRecordCount: 1
                )
            ),
        ])

        let store = try LibraryStore(
            scope: .library(mediaItem(id: "library-1")),
            session: libraryTestSession()
        )

        await store.load()
        #expect(store.items.count == 60)

        let pagingTrigger = try #require(store.items.last)
        let pagingTask = Task { @MainActor in
            await store.loadMoreIfNeeded(currentItem: pagingTrigger)
        }

        try await LibraryItemsURLProtocol.waitForRecordedRequestCount(2)
        await store.applyFilter(LibraryFilterState(status: .unplayed))
        await pagingTask.value

        #expect(store.items.map(\.id) == ["filtered-0"])
        #expect(store.isLoading == false)

        let requests = LibraryItemsURLProtocol.recordedRequests
        #expect(requests.map(\.startIndex) == [0, 60, 0])
        #expect(requests.last?.filters == "IsUnplayed")
    }
}

private func libraryItems(prefix: String, range: Range<Int>) -> [BaseItemDto] {
    range.map { libraryDTO(id: "\(prefix)-\($0)") }
}

private func libraryDTO(id: String) -> BaseItemDto {
    BaseItemDto(id: id, name: id, type: .movie)
}

private func mediaItem(id: String) -> MediaItem {
    MediaItem(id: id, name: id, type: .movie)
}

@MainActor
private func libraryTestSession() throws -> SessionStore {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LibraryItemsURLProtocol.self]
    let client = try JellyfinClient(
        configuration: .init(
            url: #require(URL(string: "https://jellyfin.example.com")),
            accessToken: "token",
            client: "GusTests",
            deviceName: "Tests",
            deviceID: "test-device",
            version: "1"
        ),
        sessionConfiguration: configuration
    )

    return try SessionStore(
        client: client,
        user: StoredUser(id: "user-1", name: "User", serverID: "server-1"),
        server: ServerConnection(id: "server-1", name: "Server", url: #require(URL(string: "https://jellyfin.example.com")))
    )
}

private struct StubbedLibraryItemsResponse: Sendable {
    var result: BaseItemDtoQueryResult
    var delayNanoseconds: UInt64 = 0
}

private struct RecordedLibraryItemsRequest: Equatable {
    var parentID: String?
    var searchTerm: String?
    var startIndex: Int?
    var filters: String?
    var sortBy: String?
    var sortOrder: String?
}

/// Keep Foundation's non-Sendable protocol on its callback boundary; delayed
/// responses use a separately synchronized delivery object.
private final class LibraryItemsURLProtocol: URLProtocol {
    private static let state = LibraryItemsURLProtocolState()
    private struct LoadingState {
        var task: Task<Void, Never>?
        var delivery: LibraryItemsResponseDelivery?
    }

    private let taskStorage = OSAllocatedUnfairLock(initialState: LoadingState())

    static var recordedRequests: [RecordedLibraryItemsRequest] {
        state.recordedRequests
    }

    static func configure(responses: [StubbedLibraryItemsResponse]) {
        state.configure(responses: responses)
    }

    static func waitForRecordedRequestCount(_ count: Int) async throws {
        for _ in 0 ..< 100 {
            if recordedRequests.count >= count {
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        Issue.record("Timed out waiting for \(count) recorded library requests")
        throw URLError(.timedOut)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path == "/Items"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let response = try Self.state.response(for: request)
            let delivery = LibraryItemsResponseDelivery(owner: self)
            let url = request.url
            taskStorage.withLock { $0.delivery = delivery }
            let task = Task { @Sendable in
                do {
                    if response.delayNanoseconds > 0 {
                        try await Task.sleep(nanoseconds: response.delayNanoseconds)
                    }
                    try Task.checkCancellation()
                    let data = try JSONEncoder().encode(response.result)
                    guard let url,
                          let httpResponse = HTTPURLResponse(
                              url: url,
                              statusCode: 200,
                              httpVersion: nil,
                              headerFields: ["Content-Type": "application/json"]
                          )
                    else {
                        throw URLError(.badURL)
                    }
                    delivery.withOwner { owner in
                        owner.client?.urlProtocol(owner, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                        owner.client?.urlProtocol(owner, didLoad: data)
                        owner.client?.urlProtocolDidFinishLoading(owner)
                    }
                } catch {
                    delivery.withOwner { owner in
                        owner.client?.urlProtocol(owner, didFailWithError: error)
                    }
                }
            }
            taskStorage.withLock {
                if $0.delivery === delivery {
                    $0.task = task
                } else {
                    task.cancel()
                }
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        let loading = taskStorage.withLock { state in
            let loading = state
            state = LoadingState()
            return loading
        }
        loading.delivery?.cancel()
        loading.task?.cancel()
    }
}

/// The weak Foundation handle is accessed only while holding this lock. Delivery
/// and cancellation are serialized; recursive locking permits synchronous client
/// callbacks to cancel their own request without deadlocking.
private final class LibraryItemsResponseDelivery: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private weak var owner: LibraryItemsURLProtocol?

    init(owner: LibraryItemsURLProtocol) {
        self.owner = owner
    }

    func withOwner(_ body: (LibraryItemsURLProtocol) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard let owner else { return }
        body(owner)
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        owner = nil
    }
}

/// All response/request mutations are serialized by lock, including snapshots.
private final class LibraryItemsURLProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [StubbedLibraryItemsResponse] = []
    private var requests: [RecordedLibraryItemsRequest] = []

    var recordedRequests: [RecordedLibraryItemsRequest] {
        lock.withLock { requests }
    }

    func configure(responses: [StubbedLibraryItemsResponse]) {
        lock.withLock {
            self.responses = responses
            requests = []
        }
    }

    func response(for request: URLRequest) throws -> StubbedLibraryItemsResponse {
        lock.lock()
        defer { lock.unlock() }

        requests.append(Self.recordedRequest(from: request))
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return responses.removeFirst()
    }

    private static func recordedRequest(from request: URLRequest) -> RecordedLibraryItemsRequest {
        let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return RecordedLibraryItemsRequest(
            parentID: queryValue("parentID", in: queryItems),
            searchTerm: queryValue("searchTerm", in: queryItems),
            startIndex: queryValue("startIndex", in: queryItems).flatMap(Int.init),
            filters: queryValue("filters", in: queryItems),
            sortBy: queryValue("sortBy", in: queryItems),
            sortOrder: queryValue("sortOrder", in: queryItems)
        )
    }

    private static func queryValue(_ name: String, in queryItems: [URLQueryItem]) -> String? {
        queryItems.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
