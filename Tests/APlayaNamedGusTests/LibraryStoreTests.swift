import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@Suite("Library store helpers")
struct LibraryStoreTests {
    @Test("builds paged library parameters with total counts download metadata and rich fields")
    func buildsPagedLibraryParameters() {
        let parameters = LibraryRequest.parameters(
            userID: "user-1",
            parentID: "library-1",
            startIndex: 60,
            limit: 60
        )

        #expect(parameters.userID == "user-1")
        #expect(parameters.parentID == "library-1")
        #expect(parameters.startIndex == 60)
        #expect(parameters.limit == 60)
        #expect(parameters.isRecursive == false)
        #expect(parameters.sortOrder == [.ascending])
        #expect(parameters.sortBy == [.sortName])
        #expect(parameters.enableUserData == true)
        #expect(parameters.enableImages == true)
        #expect(parameters.enableTotalRecordCount == true)
        #expect(parameters.fields == LibraryRequest.metadataFields)
        #expect(parameters.fields?.contains(.canDownload) == true)
        #expect(parameters.fields?.contains(.mediaStreams) == true)
        #expect(parameters.fields?.contains(.chapters) == true)
    }

    @Test("applies status filters and sort options to library parameters")
    func appliesStatusFiltersAndSortOptions() {
        let parameters = LibraryRequest.parameters(
            userID: "user-1",
            parentID: "library-1",
            startIndex: 0,
            limit: 60,
            filter: LibraryFilterState(sort: .recentlyAdded, status: .unplayed)
        )

        #expect(parameters.sortOrder == [.descending])
        #expect(parameters.sortBy == [.dateCreated])
        #expect(parameters.filters == [.isUnplayed])
    }

    @Test("builds resumable and random filter parameters")
    func buildsResumableAndRandomFilterParameters() {
        let parameters = LibraryRequest.parameters(
            userID: "user-1",
            parentID: "library-1",
            startIndex: 0,
            limit: 60,
            filter: LibraryFilterState(sort: .random, status: .resumable)
        )

        #expect(parameters.sortOrder == nil)
        #expect(parameters.sortBy == [.random])
        #expect(parameters.filters == [.isResumable])
    }

    @Test("status filters do not include favorites")
    func statusFiltersDoNotIncludeFavorites() {
        #expect(LibraryStatusFilter.allCases.map(\.rawValue).contains("favorites") == false)
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
                    items: [libraryItem(id: "filtered-0")],
                    startIndex: 0,
                    totalRecordCount: 1
                )
            ),
        ])

        let store = try LibraryStore(
            library: libraryItem(id: "library-1"),
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
    range.map { libraryItem(id: "\(prefix)-\($0)") }
}

private func libraryItem(id: String) -> BaseItemDto {
    BaseItemDto(id: id, name: id, type: .movie)
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

private struct StubbedLibraryItemsResponse {
    var result: BaseItemDtoQueryResult
    var delayNanoseconds: UInt64 = 0
}

private struct RecordedLibraryItemsRequest: Equatable {
    var startIndex: Int?
    var filters: String?
}

private final class LibraryItemsURLProtocol: URLProtocol {
    private static let state = LibraryItemsURLProtocolState()
    private var loadingTask: Task<Void, Never>?

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
            loadingTask = Task { [weak self] in
                guard let self else { return }
                do {
                    if response.delayNanoseconds > 0 {
                        try await Task.sleep(nanoseconds: response.delayNanoseconds)
                    }

                    let data = try JSONEncoder().encode(response.result)
                    guard let url = request.url,
                          let httpResponse = HTTPURLResponse(
                              url: url,
                              statusCode: 200,
                              httpVersion: nil,
                              headerFields: ["Content-Type": "application/json"]
                          )
                    else {
                        throw URLError(.badURL)
                    }

                    client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: data)
                    client?.urlProtocolDidFinishLoading(self)
                } catch {
                    client?.urlProtocol(self, didFailWithError: error)
                }
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
    }
}

private final class LibraryItemsURLProtocolState {
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
            startIndex: queryItems.first(where: { $0.name == "startIndex" })?.value.flatMap(Int.init),
            filters: queryItems.first(where: { $0.name == "filters" })?.value
        )
    }
}
