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

    private let admits: (MediaItem) -> Bool
    private let session: SessionStore
    private let logger = Logger(category: .search)
    private var generation = 0
    private var pageTask: Task<MediaItemPage, Error>?
    private(set) var pageError: String?
    private var paging: Paging

    init(session: SessionStore, limit: Int = 50, admits: @escaping (MediaItem) -> Bool = { ContentRatingGate.admitsStored($0) }) {
        self.session = session
        self.admits = admits
        self.paging = Paging(pageSize: limit, prefetchThreshold: 1)
    }

    var canLoadMore: Bool {
        paging.canLoadMore
    }

    func reset() {
        generation += 1
        pageTask?.cancel()
        pageError = nil
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

        generation += 1
        pageTask?.cancel()
        pageError = nil
        isLoadingNextPage = false
        query = normalizedQuery
        paging.reset()
        results = []
        state = .loading

        let diagnostics = DiagnosticsHub.shared
        diagnostics.record(.searchRequested)
        let searchInterval = diagnostics.beginInterval("Search")
        await loadPage(replaceResults: true, requestGeneration: generation, requestQuery: query)
        diagnostics.endInterval("Search", searchInterval)
    }

    func loadMoreIfNeeded(currentItem item: MediaItem) async {
        guard canLoadMore, !isLoadingNextPage, state == .loaded else { return }
        guard let index = results.firstIndex(where: { $0.id == item.id }),
              paging.shouldLoadMore(currentIndex: index, loadedCount: results.count)
        else { return }

        await continueSearching()
    }

    func continueSearching() async {
        guard canLoadMore, !isLoadingNextPage, state == .loaded else { return }
        let currentGeneration = generation
        isLoadingNextPage = true
        defer {
            if generation == currentGeneration {
                isLoadingNextPage = false
            }
        }
        await loadPage(replaceResults: false, requestGeneration: currentGeneration, requestQuery: query)
    }

    private func loadPage(replaceResults: Bool, requestGeneration: Int, requestQuery: String) async {
        var replace = replaceResults
        pageError = nil
        do {
            // Bound restricted-page scans; the user can explicitly continue a long scan.
            for _ in 0 ..< 3 {
                try Task.checkCancellation()
                guard requestGeneration == generation else { return }
                let startIndex = replace ? 0 : paging.nextStartIndex
                let request = MediaItemQuery(
                    searchTerm: requestQuery,
                    startIndex: startIndex,
                    limit: paging.pageSize,
                    isRecursive: true,
                    sort: nil
                )
                let task = Task { try await session.mediaProvider.items(query: request) }
                pageTask = task
                let page = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                try Task.checkCancellation()
                guard requestGeneration == generation else { return }
                let admitted = page.items.filter(admits)
                if replace {
                    results = admitted
                    paging.replaceResults(receivedCount: page.items.count, totalRecordCount: page.totalRecordCount)
                } else {
                    results.append(contentsOf: admitted)
                    paging.appendResults(receivedCount: page.items.count, totalRecordCount: page.totalRecordCount)
                }
                replace = false
                state = .loaded
                if !admitted.isEmpty || !canLoadMore {
                    break
                }
            }
        } catch {
            guard requestGeneration == generation else { return }
            let gusError = GusError(from: error)
            if gusError.isCancellation {
                if state == .loading {
                    state = .idle
                }; return
            }
            gusError.handleIfUnauthorized(session: session)
            logger.error("Search failed: \(gusError.localizedDescription, privacy: .private)")
            if replaceResults, results.isEmpty {
                state = .failed(gusError.localizedDescription)
            } else {
                pageError = gusError.localizedDescription
            }
        }
    }
}
