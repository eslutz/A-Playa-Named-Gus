import Foundation
import Observation
import OSLog

/// Global Jellyfin item search with cancellable, paginated loads.
@MainActor
@Observable
final class SearchStore {
    private(set) var state: LoadState = .idle
    private(set) var results: [MediaItem] = []
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

        let diagnostics = DiagnosticsHub.shared
        diagnostics.record(.searchRequested)
        let searchInterval = diagnostics.beginInterval("Search")
        await loadPage(startIndex: 0, replaceResults: true)
        diagnostics.endInterval("Search", searchInterval)
    }

    func loadMoreIfNeeded(currentItem item: MediaItem) async {
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
            let query = MediaItemQuery(
                searchTerm: query,
                startIndex: startIndex,
                limit: paging.pageSize,
                isRecursive: true,
                sort: nil
            )
            let page = try await session.mediaProvider.items(query: query)

            let admitted = ContentRatingGate.filter(page.items)
            if shouldReplaceResults {
                results = admitted
                paging.replaceResults(receivedCount: page.items.count, totalRecordCount: page.totalRecordCount)
            } else {
                results.append(contentsOf: admitted)
                paging.appendResults(receivedCount: page.items.count, totalRecordCount: page.totalRecordCount)
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
