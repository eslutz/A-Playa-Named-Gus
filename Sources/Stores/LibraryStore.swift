import Foundation
import JellyfinAPI
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

    var sortBy: [ItemSortBy] {
        switch self {
        case .name:
            return [.sortName]
        case .recentlyAdded:
            return [.dateCreated]
        case .releaseDate:
            return [.premiereDate]
        case .rating:
            return [.communityRating]
        case .random:
            return [.random]
        }
    }

    var sortOrder: [JellyfinAPI.SortOrder]? {
        switch self {
        case .name:
            return [.ascending]
        case .recentlyAdded, .releaseDate, .rating:
            return [.descending]
        case .random:
            return nil
        }
    }
}

enum LibraryStatusFilter: String, CaseIterable, Identifiable {
    case all
    case unplayed
    case played
    case favorites
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
        case .favorites:
            return String(localized: "Favorites", comment: "Library filter option")
        case .resumable:
            return String(localized: "In Progress", comment: "Library filter option")
        }
    }

    var filters: [ItemFilter]? {
        switch self {
        case .all:
            return nil
        case .unplayed:
            return [.isUnplayed]
        case .played:
            return [.isPlayed]
        case .favorites:
            return [.isFavorite]
        case .resumable:
            return [.isResumable]
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
    static let metadataFields: [ItemFields] = [
        .primaryImageAspectRatio,
        .overview,
        .canDownload,
        .mediaStreams,
        .chapters,
    ]

    static func parameters(
        userID: String,
        parentID: String?,
        startIndex: Int,
        limit: Int,
        filter: LibraryFilterState = .default
    ) -> Paths.GetItemsParameters {
        Paths.GetItemsParameters(
            userID: userID,
            startIndex: startIndex,
            limit: limit,
            isRecursive: false,
            sortOrder: filter.sort.sortOrder,
            parentID: parentID,
            fields: metadataFields,
            filters: filter.status.filters,
            sortBy: filter.sort.sortBy,
            enableUserData: true,
            enableTotalRecordCount: true,
            enableImages: true
        )
    }
}

/// Loads the items inside a single library (a `BaseItemDto` of kind `collectionFolder`).
///
/// Pattern reference: Swiftfin paginated `Paths.getItems(parentID:)` queries.
@MainActor
@Observable
final class LibraryStore {
    private(set) var state: LoadState = .idle
    private(set) var items: [BaseItemDto] = []
    private(set) var isLoadingNextPage = false
    private(set) var filter = LibraryFilterState.default

    let library: BaseItemDto
    private let session: SessionStore
    private let logger = Logger(category: .library)
    private var paging = Paging(pageSize: LibraryRequest.pageSize, prefetchThreshold: 12)
    private var loadGeneration = 0

    init(library: BaseItemDto, session: SessionStore) {
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
        do {
            try await loadPage(startIndex: 0, replaceResults: true, generation: generation)
        } catch {
            guard generation == loadGeneration else { return }
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

    func loadMoreIfNeeded(currentItem item: BaseItemDto) async {
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
        let parameters = LibraryRequest.parameters(
            userID: session.user.id,
            parentID: library.id,
            startIndex: startIndex,
            limit: paging.pageSize,
            filter: filter
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await session.client.send(Paths.getItems(parameters: parameters))
        }
        guard generation == loadGeneration else { return }

        let page = response.value.items ?? []
        if replaceResults {
            items = page
            paging.replaceResults(receivedCount: page.count, totalRecordCount: response.value.totalRecordCount)
        } else {
            items.append(contentsOf: page)
            paging.appendResults(receivedCount: page.count, totalRecordCount: response.value.totalRecordCount)
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
