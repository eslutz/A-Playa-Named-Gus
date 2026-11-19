import Foundation
@testable import Gus
import JellyfinAPI
import os
import Testing

@Suite("Library store helpers", .serialized)
struct LibraryStoreTests {
    @MainActor
    @Test func genreBrowseUsesGenreIDAndFiltersMembers() async throws {
        let genre = JellyfinMediaItemMapper.mediaItem(from: BaseItemDto(id: "horror", name: "Horror", type: .genre))
        #expect(genre.type == .genre)
        #expect(genre.gusTVPlaybackTarget(nextUp: [], episodes: []) == nil)
        LibraryItemsURLProtocol.configure(responses: [
            .init(result: .init(items: [
                BaseItemDto(id: "allowed", type: .movie),
                BaseItemDto(id: "restricted", type: .movie),
            ], totalRecordCount: 2)),
        ])
        let scope = LibraryGridScope.genre(id: "horror", name: "Horror")
        let store = try LibraryStore(scope: scope, session: libraryTestSession(), admits: { $0.id == "allowed" })
        await store.load()
        #expect(store.items.compactMap(\.id) == ["allowed"])
        let request = try #require(LibraryItemsURLProtocol.recordedRequests.first)
        #expect(request.genreIDs == "horror")
        #expect(request.parentID == nil)
    }

    @MainActor
    @Test("a filtered multi-page series opens all accessible volumes")
    func bookSeriesMembershipAcrossPages() async throws {
        let first = BaseItemDto(id: "first", indexNumber: 1, name: "Z book", seriesName: "Fixture Saga", type: .book)
        let second = BaseItemDto(id: "second", indexNumber: 2, name: "A book", seriesName: "  fixture  saga ", type: .book)
        let hidden = BaseItemDto(id: "hidden", indexNumber: 3, name: "Restricted", seriesName: "Fixture Saga", type: .book)
        LibraryItemsURLProtocol.configure(responses: [
            .init(result: .init(items: [second], totalRecordCount: 1)),
            .init(result: .init(items: [second, hidden], totalRecordCount: 3)),
            .init(result: .init(items: [first], totalRecordCount: 3)),
        ])
        let store = try LibraryStore(scope: .category(.books), session: libraryTestSession(), admits: { $0.id != "hidden" }, initialFilter: .init(status: .unplayed))
        await store.load()
        #expect(store.hasCompleteBookCatalog)
        #expect(store.items.compactMap(\.id) == ["second"])
        #expect(store.bookEntries.count == 1)
        guard case let .series(series)? = store.bookEntries.first else { Issue.record("Missing series"); return }
        #expect(series.members.compactMap(\.id) == ["first", "second"])
        #expect(LibraryItemsURLProtocol.recordedRequests.map(\.startIndex) == [0, 0, 2])
        #expect(LibraryItemsURLProtocol.recordedRequests.map(\.filters) == ["IsUnplayed", nil, nil])
    }

    @MainActor
    @Test("a failed later page leaves available titles browsable and prevents edits")
    func incompleteBookSeries() async throws {
        let book = BaseItemDto(id: "first", name: "Volume 1", seriesName: "Saga", type: .book)
        LibraryItemsURLProtocol.configure(responses: [
            .init(result: .init(items: [book], totalRecordCount: 2)),
            .init(result: .init(items: [], totalRecordCount: 2)),
            .init(result: .init(items: [book], totalRecordCount: 1)),
        ])
        let store = try LibraryStore(scope: .category(.books), session: libraryTestSession())
        await store.load()
        #expect(store.state == .loaded)
        #expect(!store.hasCompleteBookCatalog && store.refreshError != nil)
        #expect(store.bookEntries.count == 1)
        await store.load()
        #expect(store.hasCompleteBookCatalog)
        #expect(store.refreshError == nil)
    }

    @Test("format, series IDs, and untagged titles have separate identities")
    func bookShelfIdentities() {
        let standalone = MediaItem(id: "alone", name: "Standalone", seriesName: "  ", type: .book)
        let book = MediaItem(id: "book", name: "Book", seriesID: "AAA", seriesName: "Saga", type: .book)
        let unrelated = MediaItem(id: "other", name: "Other", seriesID: "BBB", seriesName: "Saga", type: .book)
        let audio = MediaItem(id: "audio", indexNumber: 9, name: "Audio 1", productionYear: 2021, seriesName: "Saga", type: .audioBook)
        let newer = MediaItem(id: "newer", indexNumber: 1, name: "Audio 2", productionYear: 2022, seriesName: "SAGA", type: .audioBook)
        let items = [standalone, book, unrelated, newer, audio]
        let rows = BookSeriesCatalog(items).entries(visible: items, sortByName: false)
        #expect(rows.count == 4)
        guard case let .series(series)? = rows.last else { Issue.record("Missing audiobook series"); return }
        #expect(series.members.compactMap(\.id) == ["audio", "newer"])
    }

    @Test("name-only volumes join a uniquely identified series while editions remain separate")
    func mixedSeriesIdentifiers() throws {
        let identified = MediaItem(id: "ed1", name: "Shared Title", seriesID: "AAA", seriesName: "Saga", type: .book)
        let unnamedID = MediaItem(id: "ed2", name: "Shared Title", seriesName: "saga", type: .book)
        let legacyKey = try #require(BookSeriesKey(item: unnamedID))
        var catalog = BookSeriesCatalog([identified, unnamedID])
        #expect(catalog.entries(visible: catalog.books, sortByName: true).count == 1)
        #expect(catalog.series(legacyKey)?.members.compactMap(\.id) == ["ed1", "ed2"])
        var otherSeries = identified
        otherSeries.id = "other"
        otherSeries.seriesID = "BBB"
        catalog = BookSeriesCatalog([identified, unnamedID, otherSeries])
        #expect(catalog.entries(visible: catalog.books, sortByName: true).count == 3)
        #expect(catalog.series(legacyKey)?.members.compactMap(\.id) == ["ed2"])
    }

    @Test("audiobook stacks use unambiguous server metadata independently of editing permissions")
    func audiobookSeriesFromJellyfin() throws {
        let payload = #"""
        [
          {"Id":"a","Type":"AudioBook","Name":"Earlier","SeriesId":"aa","SeriesName":"Saga","IndexNumber":8,"ProductionYear":2021},
          {"Id":"b","Type":"AudioBook","Name":"Later","SeriesName":" saga ","IndexNumber":1,"ProductionYear":2022},
          {"Id":"c","Type":"AudioBook","Name":"Standalone","Album":"Saga","IndexNumber":2,"ParentIndexNumber":1}
        ]
        """#
        let items = try JellyfinMediaItemMapper.mediaItems(from: JSONDecoder().decode([BaseItemDto].self, from: Data(payload.utf8)))
        var catalog = BookSeriesCatalog(items)
        let entries = catalog.entries(visible: items, sortByName: false)
        #expect(entries.map(\.title) == ["Saga", "Standalone"])
        guard case let .series(saga) = entries.first else { Issue.record("Missing audiobook series"); return }
        #expect(saga.members.compactMap(\.id) == ["a", "b"])
        #expect(BookSeriesEditScope(items).editableBooks.isEmpty)

        var unrelated = items[0]
        unrelated.id = "d"
        unrelated.seriesID = "bb"
        catalog = BookSeriesCatalog(items + [unrelated])
        guard case let .title(unresolved) = catalog.entries(visible: [items[1]], sortByName: false).first else {
            Issue.record("A shared name cannot establish which audiobook series owns this title"); return
        }
        #expect(unresolved.id == "b")
    }

    @Test("volumes with only a series ID join named siblings of the same format")
    func volumesWithoutSeriesNames() throws {
        let unnamed = MediaItem(id: "first", indexNumber: 1, name: "First", seriesID: "AAA", type: .book)
        let named = MediaItem(id: "second", indexNumber: 2, name: "Second", seriesID: "AAA", seriesName: "Saga", type: .book)
        let audio = MediaItem(id: "audio", name: "Audio", seriesID: "AAA", seriesName: "  ", type: .audioBook)
        let catalog = BookSeriesCatalog([unnamed, named, audio])
        let key = try #require(BookSeriesKey(item: unnamed))
        let group = try #require(catalog.series(key))
        #expect(group.name == "Saga")
        #expect(group.members.compactMap(\.id) == ["first", "second"])
        #expect(catalog.entries(visible: catalog.books, sortByName: false).map(\.title) == ["Saga", "Audio"])
        let incomplete = BookSeriesCatalog([unnamed])
        #expect(incomplete.entries(visible: incomplete.books, sortByName: true).map(\.id) == ["first"])
    }

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
    @Test("a replacement filter supersedes an in-flight first page")
    func supersedesFirstPage() async throws {
        LibraryItemsURLProtocol.configure(responses: [
            .init(result: BaseItemDtoQueryResult(items: [libraryDTO(id: "old")], totalRecordCount: 1), delayNanoseconds: 200_000_000),
            .init(result: BaseItemDtoQueryResult(items: [libraryDTO(id: "filtered")], totalRecordCount: 1)),
        ])
        let store = try LibraryStore(scope: .category(.movies), session: libraryTestSession())
        let original = Task { await store.load() }
        try await LibraryItemsURLProtocol.waitForRecordedRequestCount(1)
        await store.applyFilter(LibraryFilterState(status: .unplayed))
        await original.value
        #expect(store.items.map(\.id) == ["filtered"])
        #expect(LibraryItemsURLProtocol.recordedRequests.map(\.filters) == [nil, "IsUnplayed"])
        #expect(!store.isLoading)
    }

    @MainActor
    @Test("overlapping pages advance raw offsets and an incomplete page retains retry at the same offset")
    func deduplicatesPages() async throws {
        LibraryItemsURLProtocol.configure(responses: [
            .init(result: BaseItemDtoQueryResult(items: libraryItems(prefix: "item", range: 0 ..< 60), totalRecordCount: 63)),
            .init(result: BaseItemDtoQueryResult(items: [libraryDTO(id: "item-59"), libraryDTO(id: "new")])),
            .init(result: BaseItemDtoQueryResult(items: [])),
            .init(result: BaseItemDtoQueryResult(items: [libraryDTO(id: "last")])),
        ])
        let store = try LibraryStore(scope: .category(.movies), session: libraryTestSession())
        await store.load()
        await store.continueSearching()
        #expect(store.items.count == 61)
        #expect(store.items.filter { $0.id == "item-59" }.count == 1)
        await store.continueSearching()
        #expect(store.items.count == 61 && store.canLoadMore)
        #expect(store.pageError != nil)
        await store.continueSearching()
        #expect(LibraryItemsURLProtocol.recordedRequests.map(\.startIndex) == [0, 60, 62, 62])
        #expect(store.items.count == 62 && !store.canLoadMore)
        #expect(store.items.last?.id == "last" && store.pageError == nil)
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
    var genreIDs: String?
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
            genreIDs: queryValue("genreIds", in: queryItems),
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
