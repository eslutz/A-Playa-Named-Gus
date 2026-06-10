import Foundation
import Observation
import OSLog

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case name
    case recentlyAdded
    case releaseDate
    case rating
    case random

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .name:
            return String(localized: "Name", comment: "Library sort option")
        case .recentlyAdded:
            return String(localized: "Recently Added", comment: "Library sort option")
        case .releaseDate:
            return String(localized: "Release Date", comment: "Library sort option")
        case .rating:
            return String(localized: "Rating", comment: "Library sort option")
        case .random:
            return String(localized: "Random", comment: "Library sort option")
        }
    }

    var mediaSort: MediaItemSort {
        switch self {
        case .name:
            return .name
        case .recentlyAdded:
            return .recentlyAdded
        case .releaseDate:
            return .releaseDate
        case .rating:
            return .rating
        case .random:
            return .random
        }
    }
}

enum LibraryStatusFilter: String, CaseIterable, Identifiable {
    case all
    case unplayed
    case played
    case resumable

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            return String(localized: "All", comment: "Library filter option")
        case .unplayed:
            return String(localized: "Unplayed", comment: "Library filter option")
        case .played:
            return String(localized: "Played", comment: "Library filter option")
        case .resumable:
            return String(localized: "In Progress", comment: "Library filter option")
        }
    }

    var mediaStatusFilter: MediaItemStatusFilter {
        switch self {
        case .all:
            return .all
        case .unplayed:
            return .unplayed
        case .played:
            return .played
        case .resumable:
            return .resumable
        }
    }
}

struct LibraryFilterState: Equatable {
    static let `default` = LibraryFilterState()

    var sort: LibrarySortOption = .name
    var status: LibraryStatusFilter = .all

    var hasActiveFilter: Bool {
        self != .default
    }
}

enum LibraryRequest {
    static let pageSize = 60

    static func parameters(
        parentID: String?,
        startIndex: Int,
        limit: Int,
        filter: LibraryFilterState = .default
    ) -> MediaItemQuery {
        MediaItemQuery(
            parentID: parentID,
            startIndex: startIndex,
            limit: limit,
            sort: filter.sort.mediaSort,
            statusFilter: filter.status.mediaStatusFilter
        )
    }
}

/// Loads the items inside a single library.
///
/// Pattern reference: Swiftfin paginated `Paths.getItems(parentID:)` queries.
@MainActor
@Observable
final class LibraryStore {
    private(set) var state: LoadState = .idle
    private(set) var items: [MediaItem] = []
    private(set) var isLoadingNextPage = false
    private(set) var filter = LibraryFilterState.default

    let library: MediaItem
    private let session: SessionStore
    private let logger = Logger(category: .library)
    private var paging = Paging(pageSize: LibraryRequest.pageSize, prefetchThreshold: 12)
    private var loadGeneration = 0

    init(library: MediaItem, session: SessionStore) {
        self.library = library
        self.session = session
    }

    var title: String {
        library.name ?? "Library"
    }

    var isLoading: Bool {
        state.isLoading || isLoadingNextPage
    }

    func load() async {
        guard state != .loading else { return }
        loadGeneration += 1
        let generation = loadGeneration
        isLoadingNextPage = false
        state = .loading
        paging.reset()
        let diagnostics = DiagnosticsHub.shared
        diagnostics.record(.libraryLoadStarted)
        let loadInterval = diagnostics.beginInterval("LibraryLoad")
        do {
            try await loadPage(startIndex: 0, replaceResults: true, generation: generation)
            diagnostics.endInterval("LibraryLoad", loadInterval)
            diagnostics.record(.libraryLoadFinished(itemCount: items.count))
        } catch {
            diagnostics.endInterval("LibraryLoad", loadInterval)
            guard generation == loadGeneration else { return }
            diagnostics.record(.libraryLoadFailed)
            handle(error)
        }
    }

    var canLoadMore: Bool {
        paging.canLoadMore
    }

    func applyFilter(_ filter: LibraryFilterState) async {
        guard self.filter != filter else { return }
        self.filter = filter
        await load()
    }

    func loadMoreIfNeeded(currentItem item: MediaItem) async {
        guard canLoadMore, !isLoadingNextPage, state == .loaded else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              paging.shouldLoadMore(currentIndex: index, loadedCount: items.count)
        else { return }

        let generation = loadGeneration
        isLoadingNextPage = true
        defer {
            if generation == loadGeneration {
                isLoadingNextPage = false
            }
        }

        do {
            try await loadPage(startIndex: paging.nextStartIndex, replaceResults: false, generation: generation)
        } catch {
            guard generation == loadGeneration else { return }
            handle(error)
        }
    }

    private func loadPage(startIndex: Int, replaceResults: Bool, generation: Int) async throws {
        let query = LibraryRequest.parameters(
            parentID: library.id,
            startIndex: startIndex,
            limit: paging.pageSize,
            filter: filter
        )
        let page = try await session.mediaProvider.items(query: query)
        guard generation == loadGeneration else { return }

        let admitted = ContentRatingGate.filter(page.items)
        if replaceResults {
            items = admitted
            paging.replaceResults(receivedCount: page.items.count, totalRecordCount: page.totalRecordCount)
        } else {
            items.append(contentsOf: admitted)
            paging.appendResults(receivedCount: page.items.count, totalRecordCount: page.totalRecordCount)
        }
        state = .loaded
    }

    private func handle(_ error: Error) {
        let gusError = GusError(from: error)
        guard !gusError.isCancellation else { return } // navigated away mid-load
        logger.error("Library load failed: \(gusError.localizedDescription, privacy: .public)")
        state = .failed(gusError.localizedDescription)
    }
}
