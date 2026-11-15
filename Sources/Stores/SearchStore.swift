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
    private(set) var isRefreshing = false

    private let admits: (MediaItem) -> Bool
    private let includeTypes: [MediaItemType]?
    private let session: SessionStore
    private let logger = Logger(category: .search)
    private var generation = 0
    private var pageTask: Task<MediaItemPage, Error>?
    private(set) var pageError: String?
    private(set) var refreshError: String?
    private var paging: Paging
    private var refreshPaging: Paging?
    private var refreshResults: [MediaItem]?

    init(session: SessionStore, limit: Int = 50, includeTypes: [MediaItemType]? = nil, admits: @escaping (MediaItem) -> Bool = { ContentRatingGate.admitsStored($0) }) {
        self.includeTypes = includeTypes
        self.session = session
        self.admits = admits
        self.paging = Paging(pageSize: limit, prefetchThreshold: 1)
        session.onInvalidation(of: self) { $0.reset() }
    }

    var foregroundPhase: ForegroundLoadPhase {
        if let refreshError {
            return .failed(.refresh, refreshError)
        }
        return state.foregroundPhase(hasContent: !results.isEmpty, refreshing: isRefreshing, paging: isLoadingNextPage, pageError: pageError)
    }

    var canLoadMore: Bool {
        paging.canLoadMore
    }

    /// Hidden search holders stop reads while keeping their loaded Back-stack
    /// rows, raw continuation offset and stable query identity intact.
    func cancelForegroundLoad() {
        generation += 1
        pageTask?.cancel()
        pageTask = nil
        if isRefreshing {
            if let refreshResults {
                results = refreshResults
            }
            if let refreshPaging {
                paging = refreshPaging
            }
        }
        refreshResults = nil
        refreshPaging = nil
        isRefreshing = false
        isLoadingNextPage = false
        state = results.isEmpty ? .idle : .loaded
    }

    func reset() {
        generation += 1
        pageTask?.cancel()
        pageError = nil
        refreshError = nil
        query = ""
        refreshResults = nil
        refreshPaging = nil
        isRefreshing = false
        results = []
        paging.reset()
        state = .idle
        isLoadingNextPage = false
    }

    func search(_ rawQuery: String) async {
        guard session.isActive else { return }
        let normalizedQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            reset()
            return
        }

        if normalizedQuery == query, state == .loading {
            return
        }
        let refreshing = normalizedQuery == query && !results.isEmpty
        let previousResults = results
        let previousPaging = paging
        refreshResults = refreshing ? results : nil
        refreshPaging = refreshing ? paging : nil
        generation += 1
        let requestGeneration = generation
        pageTask?.cancel()
        pageError = nil
        refreshError = nil
        isLoadingNextPage = false
        isRefreshing = refreshing
        defer {
            if requestGeneration == generation {
                isRefreshing = false
                refreshResults = nil
                refreshPaging = nil
            }
        }
        query = normalizedQuery
        paging.reset()
        if !refreshing {
            results = []; state = .loading
        }

        let diagnostics = DiagnosticsHub.shared
        diagnostics.record(.searchRequested)
        let searchInterval = diagnostics.beginInterval("Search")
        await loadPage(replaceResults: true, requestGeneration: requestGeneration, requestQuery: normalizedQuery)
        if requestGeneration == generation, refreshing, refreshError != nil {
            results = previousResults
            paging = previousPaging
        }
        diagnostics.endInterval("Search", searchInterval)
    }

    func loadMoreIfNeeded(currentItem item: MediaItem) async {
        guard canLoadMore, !isRefreshing, !isLoadingNextPage, state == .loaded,
              let index = results.firstIndex(where: { $0.id == item.id }),
              paging.shouldLoadMore(currentIndex: index, loadedCount: results.count)
        else { return }

        await continueSearching()
    }

    func continueSearching() async {
        guard canLoadMore, !isRefreshing, !isLoadingNextPage, state == .loaded else { return }
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
        refreshError = nil
        do {
            // Bound restricted-page scans; the user can explicitly continue a long scan.
            for _ in 0 ..< 3 {
                try Task.checkCancellation()
                guard requestGeneration == generation, session.isActive else { return }
                let startIndex = replace ? 0 : paging.nextStartIndex
                let request = MediaItemQuery(
                    searchTerm: requestQuery,
                    includeTypes: includeTypes,
                    startIndex: startIndex,
                    limit: paging.pageSize,
                    isRecursive: true,
                    sort: nil
                )
                let task = Task { try await session.mediaProvider.items(query: request) }
                pageTask = task
                let page = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                try Task.checkCancellation()
                guard requestGeneration == generation, session.isActive else { return }
                let total = try MediaPageLoader.validatedTotal(for: page, startIndex: startIndex, previousTotal: replace ? nil : paging.totalRecordCount)
                let admitted = MediaPageLoader.unique(page.items.filter(admits), after: replace ? [] : results)
                if replace {
                    results = admitted
                    paging.replaceResults(receivedCount: page.items.count, totalRecordCount: total)
                } else {
                    results.append(contentsOf: admitted)
                    paging.appendResults(receivedCount: page.items.count, totalRecordCount: total)
                }
                replace = false
                state = .loaded
                if !admitted.isEmpty || !canLoadMore {
                    break
                }
            }
        } catch {
            guard requestGeneration == generation, session.isActive else { return }
            let gusError = GusError(from: error)
            if gusError.isCancellation {
                if state == .loading {
                    state = .idle
                }; return
            }
            gusError.handleIfUnauthorized(session: session)
            logger.error("Search failed: \(gusError.localizedDescription, privacy: .private)")
            if replaceResults, isRefreshing {
                refreshError = gusError.localizedDescription
                state = .loaded
            } else if replaceResults, results.isEmpty {
                state = .failed(gusError.localizedDescription)
            } else {
                pageError = gusError.localizedDescription
            }
        }
    }
}
