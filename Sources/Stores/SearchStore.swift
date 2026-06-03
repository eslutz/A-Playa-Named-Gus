import Foundation
import JellyfinAPI
import Observation
import OSLog

enum SearchRequest {
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
    private var paging: Paging

    init(session: SessionStore, limit: Int = 50) {
        self.session = session
        self.paging = Paging(pageSize: limit, prefetchThreshold: 1)
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
        guard let index = results.firstIndex(where: { $0.id == item.id }),
              paging.shouldLoadMore(currentIndex: index, loadedCount: results.count)
        else { return }

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
                limit: paging.pageSize
            )
            let response = try await NetworkRetryPolicy.idempotent.run {
                try await session.client.send(Paths.getItems(parameters: parameters))
            }
            let items = response.value.items ?? []

            if shouldReplaceResults {
                results = items
                paging.replaceResults(receivedCount: items.count, totalRecordCount: response.value.totalRecordCount)
            } else {
                results.append(contentsOf: items)
                paging.appendResults(receivedCount: items.count, totalRecordCount: response.value.totalRecordCount)
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
