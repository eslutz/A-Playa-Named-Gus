import Foundation
import JellyfinAPI
import Observation
import OSLog

struct SearchRequest {
    static let metadataFields: [ItemFields] = [
        .primaryImageAspectRatio,
        .overview,
        .genres,
        .people,
        .studios,
        .taglines,
    ]

    static func parameters(
        userID: String,
        query: String,
        startIndex: Int,
        limit: Int
    ) -> Paths.GetItemsParameters {
        Paths.GetItemsParameters(
            userID: userID,
            startIndex: startIndex,
            limit: limit,
            isRecursive: true,
            searchTerm: query.trimmingCharacters(in: .whitespacesAndNewlines),
            fields: metadataFields,
            enableUserData: true,
            enableTotalRecordCount: true,
            enableImages: true
        )
    }
}

struct SearchPaging {
    let limit: Int
    private(set) var nextStartIndex = 0
    private(set) var canLoadMore = false

    init(limit: Int) {
        self.limit = limit
    }

    mutating func reset() {
        nextStartIndex = 0
        canLoadMore = false
    }

    mutating func replaceResults(count: Int, totalRecordCount: Int?) {
        nextStartIndex = count
        canLoadMore = hasMoreResults(loadedCount: count, receivedCount: count, totalRecordCount: totalRecordCount)
    }

    mutating func appendResults(count: Int, totalRecordCount: Int?) {
        nextStartIndex += count
        canLoadMore = hasMoreResults(
            loadedCount: nextStartIndex,
            receivedCount: count,
            totalRecordCount: totalRecordCount
        )
    }

    private func hasMoreResults(
        loadedCount: Int,
        receivedCount: Int,
        totalRecordCount: Int?
    ) -> Bool {
        if let totalRecordCount {
            return loadedCount < totalRecordCount
        }
        return receivedCount >= limit
    }
}

/// Global Jellyfin item search with cancellable, paginated loads.
@MainActor
@Observable
final class SearchStore {
    private(set) var state: LoadState = .idle
    private(set) var results: [BaseItemDto] = []
    private(set) var query = ""
    private(set) var isLoadingNextPage = false

    private let session: SessionStore
    private let logger = Logger(category: .search)
    private var paging: SearchPaging

    init(session: SessionStore, limit: Int = 50) {
        self.session = session
        self.paging = SearchPaging(limit: limit)
    }

    var canLoadMore: Bool {
        paging.canLoadMore
    }

    func reset() {
        query = ""
        results = []
        paging.reset()
        state = .idle
        isLoadingNextPage = false
    }

    func search(_ rawQuery: String) async {
        let normalizedQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            reset()
            return
        }

        query = normalizedQuery
        paging.reset()
        results = []
        state = .loading

        await loadPage(startIndex: 0, replaceResults: true)
    }

    func loadMoreIfNeeded(currentItem item: BaseItemDto) async {
        guard canLoadMore, !isLoadingNextPage, state == .loaded else { return }
        guard item.id == results.last?.id else { return }

        isLoadingNextPage = true
        await loadPage(startIndex: paging.nextStartIndex, replaceResults: false)
        isLoadingNextPage = false
    }

    private func loadPage(startIndex: Int, replaceResults shouldReplaceResults: Bool) async {
        do {
            let parameters = SearchRequest.parameters(
                userID: session.user.id,
                query: query,
                startIndex: startIndex,
                limit: paging.limit
            )
            let response = try await session.client.send(Paths.getItems(parameters: parameters))
            let items = response.value.items ?? []

            if shouldReplaceResults {
                results = items
                paging.replaceResults(count: items.count, totalRecordCount: response.value.totalRecordCount)
            } else {
                results.append(contentsOf: items)
                paging.appendResults(count: items.count, totalRecordCount: response.value.totalRecordCount)
            }

            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            logger.error("Search failed: \(gusError.localizedDescription, privacy: .public)")
            state = .failed(gusError.localizedDescription)
        }
    }
}
