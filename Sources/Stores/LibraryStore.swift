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

enum LibraryGridScope: Hashable {
    case related(RelatedSearch)

    static func genre(id: String, name: String) -> Self {
        .related(RelatedSearch(kind: .genre, id: id, name: name))
    }

    case library(MediaItem)
    case category(NavigationCategory)
    case photoLibrary(parentID: String?, albums: Bool)
    case musicLibrary(parentID: String?)
    case latest(LatestMediaKind)

    var title: String {
        switch self {
        case let .library(library):
            return library.name ?? String(localized: "Library", comment: "Fallback library title")
        case let .category(category):
            return category.title
        case .photoLibrary:
            return String(localized: "Photos")
        case .musicLibrary:
            return String(localized: "Music")
        case let .related(target): return target.name
        case let .latest(kind): return kind.title
        }
    }

    var systemImage: String {
        switch self {
        case let .library(library):
            return library.librarySymbol
        case let .category(category):
            return category.systemImage
        case .photoLibrary:
            return "photo"
        case .musicLibrary:
            return "music.note"
        case let .related(target): return target.kind.systemImage
        case .latest: return "clock"
        }
    }

    var parentID: String? {
        switch self {
        case let .library(library):
            return library.id
        case .category, .latest, .related:
            return nil
        case let .photoLibrary(parentID, _), let .musicLibrary(parentID):
            return parentID
        }
    }

    var relatedSearch: RelatedSearch? {
        if case let .related(target) = self {
            return target
        }
        return nil
    }

    var groupsBookSeries: Bool {
        switch self {
        case let .library(library): library.collectionType == .books
        case let .category(category): category == .books || category == .audiobooks
        default: false
        }
    }

    var includeTypes: [MediaItemType]? {
        switch self {
        case .library:
            return groupsBookSeries ? [.book, .audioBook] : nil
        case let .category(category):
            return category.includeTypes
        case let .photoLibrary(_, albums):
            return albums ? [.photoAlbum] : [.photo]
        case .musicLibrary:
            return [.musicAlbum, .musicArtist]
        case .related:
            return [.movie, .series, .episode, .book, .audioBook, .musicAlbum, .audio, .video, .trailer, .recording, .photo]
        case let .latest(kind): return kind.includeTypes
        }
    }

    var isRecursive: Bool {
        switch self {
        case .library:
            return groupsBookSeries
        case .category, .photoLibrary, .musicLibrary, .latest, .related:
            return true
        }
    }

    fileprivate var cacheIdentity: String {
        switch self {
        case .library: "library:" + storeIdentity
        case .category: "category:" + storeIdentity
        default: storeIdentity
        }
    }

    var storeIdentity: String {
        switch self {
        case let .library(library):
            return library.id ?? library.name ?? library.collectionType?.rawValue ?? "library"
        case let .category(category):
            return category.id
        case let .photoLibrary(parentID, albums):
            return "photos:" + (parentID ?? "all") + (albums ? ":albums" : ":images")
        case let .musicLibrary(parentID):
            return "music:" + (parentID ?? "all")
        case let .related(target): return target.identityKey
        case let .latest(kind): return "latest:" + kind.rawValue
        }
    }
}

enum LibraryRequest {
    static let pageSize = 60

    static func parameters(
        scope: LibraryGridScope,
        startIndex: Int,
        limit: Int,
        filter: LibraryFilterState = .default
    ) -> MediaItemQuery {
        MediaItemQuery(
            parentID: scope.parentID,
            genreID: scope.relatedSearch.flatMap { $0.kind == .genre ? $0.id : nil },
            studioID: scope.relatedSearch.flatMap { $0.kind == .studio ? $0.id : nil },
            personID: scope.relatedSearch.flatMap { $0.kind == .person ? $0.id : nil },
            includeTypes: scope.includeTypes,
            startIndex: startIndex,
            limit: limit,
            isRecursive: scope.isRecursive,
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
    private(set) var bookCatalog = BookSeriesCatalog([])
    private(set) var bookEntries: [BookShelfEntry] = []
    private(set) var hasCompleteBookCatalog = false

    private(set) var isLoadingNextPage = false
    private(set) var isRefreshing = false
    private(set) var refreshError: String?
    private(set) var filter = LibraryFilterState.default

    let scope: LibraryGridScope
    private let admits: (MediaItem) -> Bool
    private let session: SessionStore
    private let onFilterChanged: ((LibraryFilterState) -> Void)?
    private let logger = Logger(category: .library)
    private var paging = Paging(pageSize: LibraryRequest.pageSize, prefetchThreshold: 12)
    private var loadGeneration = 0
    private var pageTask: Task<MediaItemPage, Error>?
    private(set) var pageError: String?

    convenience init(library: MediaItem, session: SessionStore) {
        self.init(scope: .library(library), session: session)
    }

    init(scope: LibraryGridScope, session: SessionStore, admits: @escaping (MediaItem) -> Bool = { ContentRatingGate.admitsStored($0) }, initialFilter: LibraryFilterState? = nil, onFilterChanged: ((LibraryFilterState) -> Void)? = nil) {
        self.scope = scope
        self.session = session
        self.admits = admits
        self.onFilterChanged = onFilterChanged
        filter = initialFilter ?? .default
        if case .latest = scope, initialFilter == nil {
            filter.sort = .recentlyAdded
        }
        session.onInvalidation(of: self) { $0.invalidate() }
    }

    private func invalidate() {
        hasCompleteBookCatalog = false
        loadGeneration += 1
        pageTask?.cancel()
        isRefreshing = false
        isLoadingNextPage = false
    }

    var title: String {
        scope.title
    }

    var foregroundPhase: ForegroundLoadPhase {
        if let refreshError {
            return .failed(.refresh, refreshError)
        }
        return state.foregroundPhase(hasContent: !items.isEmpty, refreshing: isRefreshing, paging: isLoadingNextPage, pageError: pageError)
    }

    var isLoading: Bool {
        state.isLoading || isRefreshing || isLoadingNextPage
    }

    private struct FirstPage: Codable {
        let items: [MediaItem]
        let paging: Paging
    }

    private var savedAt: Date?
    private var restriction = BrowseSnapshotCache.restriction
    var matchesRestriction: Bool {
        restriction == BrowseSnapshotCache.restriction
    }

    private var cacheKey: String {
        "grid:" + scope.cacheIdentity + ":" + filter.sort.rawValue + ":" + filter.status.rawValue
    }

    private func clearSnapshot() {
        invalidate()
        items = []
        bookEntries = []
        bookCatalog = BookSeriesCatalog([])
        paging.reset()
        savedAt = nil
        refreshError = nil
        pageError = nil
        state = .idle
    }

    func loadIfNeeded() async {
        guard session.isActive else { return }
        let cache = session.browseCache
        if restriction != BrowseSnapshotCache.restriction ||
            savedAt.map({ !(0 ..< BrowseSnapshotCache.lifetime).contains(cache.now().timeIntervalSince($0)) }) == true
        {
            clearSnapshot()
            restriction = BrowseSnapshotCache.restriction
        }
        if state == .idle, let snapshot = cache.read(cacheKey, as: FirstPage.self) {
            savedAt = snapshot.savedAt
            items = snapshot.value.items.filter(admits)
            paging = snapshot.value.paging
            if scope.groupsBookSeries {
                bookCatalog = BookSeriesCatalog(items)
                bookEntries = bookCatalog.entries(visible: items, sortByName: filter.sort == .name)
            }
            state = .loaded
        }
        if let savedAt, cache.now().timeIntervalSince(savedAt) < 300, !scope.groupsBookSeries || hasCompleteBookCatalog {
            return
        }
        await load()
    }

    func load(superseding: Bool = false) async {
        guard session.isActive, superseding || !isLoading else { return }
        if restriction != BrowseSnapshotCache.restriction || savedAt.map({ !(0 ..< BrowseSnapshotCache.lifetime).contains(session.browseCache.now().timeIntervalSince($0)) }) == true {
            clearSnapshot()
            restriction = BrowseSnapshotCache.restriction
        }
        let partition = restriction
        let previousItems = items
        let previousPaging = paging
        let hasContent = !items.isEmpty
        loadGeneration += 1
        pageTask?.cancel()
        pageError = nil
        let generation = loadGeneration
        isLoadingNextPage = false
        isRefreshing = hasContent || savedAt != nil
        refreshError = nil
        if !hasContent, savedAt == nil {
            state = .loading
        }
        paging.reset()
        hasCompleteBookCatalog = false
        defer {
            if generation == loadGeneration {
                isRefreshing = false
            }
        }
        let diagnostics = DiagnosticsHub.shared
        diagnostics.record(.libraryLoadStarted)
        let loadInterval = diagnostics.beginInterval("LibraryLoad")
        defer { diagnostics.endInterval("LibraryLoad", loadInterval) }
        do {
            if scope.groupsBookSeries {
                // Opening a stack can remove the launching view's task. The
                // session/generation still owns this read for the pushed page.
                try await Task { try await self.loadBookCatalog(generation: generation) }.value
            } else if hasContent, previousPaging.nextStartIndex > LibraryRequest.pageSize {
                try await refreshLoadedPages(through: previousPaging.nextStartIndex, generation: generation)
            } else {
                try await scanPages(replaceResults: true, generation: generation)
            }
            guard generation == loadGeneration, session.isActive, partition == BrowseSnapshotCache.restriction else { return }
            savedAt = session.browseCache.now()
            if scope.groupsBookSeries || previousPaging.nextStartIndex <= LibraryRequest.pageSize || !hasContent {
                saveFirstPage(items, paging: paging)
            }
            diagnostics.record(.libraryLoadFinished(itemCount: items.count))
        } catch {
            guard generation == loadGeneration, session.isActive else { return }
            diagnostics.record(.libraryLoadFailed)
            if GusError(from: error).invalidatesBrowseSnapshot {
                session.browseCache.remove(cacheKey)
                clearSnapshot()
                handle(error)
                GusError(from: error).handleIfUnauthorized(session: session)
            } else if scope.groupsBookSeries, !hasContent, !items.isEmpty, !GusError(from: error).isCancellation {
                bookCatalog = BookSeriesCatalog(items)
                bookEntries = bookCatalog.entries(visible: items, sortByName: filter.sort == .name)
                state = .loaded
                refreshError = GusError(from: error).localizedDescription
            } else if hasContent {
                items = previousItems
                paging = previousPaging
                let failure = GusError(from: error)
                state = .loaded
                if !failure.isCancellation {
                    refreshError = failure.localizedDescription
                }
            } else {
                handle(error)
            }
        }
    }

    var canLoadMore: Bool {
        paging.canLoadMore
    }

    func applyFilter(_ filter: LibraryFilterState) async {
        guard self.filter != filter else { return }
        self.filter = filter
        onFilterChanged?(filter)
        clearSnapshot()
        await loadIfNeeded()
    }

    func loadMoreIfNeeded(currentItem item: MediaItem) async {
        guard canLoadMore, !isLoadingNextPage, !isRefreshing, state == .loaded,
              let index = items.firstIndex(where: { $0.id == item.id }),
              paging.shouldLoadMore(currentIndex: index, loadedCount: items.count)
        else { return }

        await continueSearching()
    }

    func continueSearching() async {
        guard canLoadMore, !isLoadingNextPage, !isRefreshing, state == .loaded else { return }
        let generation = loadGeneration
        isLoadingNextPage = true
        pageError = nil
        defer {
            if generation == loadGeneration {
                isLoadingNextPage = false
            }
        }
        do { try await scanPages(replaceResults: false, generation: generation) }
        catch {
            guard generation == loadGeneration, session.isActive else { return }
            let failure = GusError(from: error)
            if failure.invalidatesBrowseSnapshot {
                session.browseCache.remove(cacheKey)
                clearSnapshot()
                handle(error)
                failure.handleIfUnauthorized(session: session)
            } else if !failure.isCancellation {
                pageError = failure.localizedDescription
            }
        }
    }

    /// An inline series can span pages. Keep a complete unfiltered catalog for
    /// navigation and editing even when the visible shelf has a status filter.
    private func loadBookCatalog(generation: Int) async throws {
        let selection = filter
        let savePartial = items.isEmpty
        var received = 0
        defer {
            if generation == loadGeneration {
                isLoadingNextPage = false
            }
        }
        var queryFilter = selection
        if queryFilter.sort == .random {
            queryFilter.sort = .name
        }
        let visible = try await bookPages(filter: queryFilter, generation: generation) { page in
            guard savePartial, generation == self.loadGeneration else { return }
            let additions = page.dropFirst(received).filter(self.admits)
            received = page.count
            let needsPreview = self.items.isEmpty
            self.items.append(contentsOf: additions)
            if needsPreview, !self.items.isEmpty {
                self.bookCatalog = BookSeriesCatalog(self.items)
                self.bookEntries = self.bookCatalog.entries(visible: self.items, sortByName: selection.sort == .name)
                self.isLoadingNextPage = true
                self.state = .loaded
            }
        }
        let catalog = selection.status == .all ? visible : try await bookPages(filter: .default, generation: generation)
        try Task.checkCancellation()
        guard generation == loadGeneration, session.isActive, matchesRestriction else { throw CancellationError() }
        bookCatalog = BookSeriesCatalog(catalog.filter(admits))
        if selection.status == .all {
            items = bookCatalog.books
        } else {
            let byID = Dictionary(uniqueKeysWithValues: bookCatalog.books.compactMap { item in item.id.map { ($0, item) } })
            items = visible.compactMap { item in item.id.flatMap { byID[$0] } }
        }
        bookEntries = bookCatalog.entries(visible: items, sortByName: selection.sort == .name)
        if selection.sort == .random {
            bookEntries.shuffle()
        }
        state = .loaded
        hasCompleteBookCatalog = true
        index(items)
    }

    private func bookPages(filter: LibraryFilterState, generation: Int, didLoadPage: (([MediaItem]) -> Void)? = nil) async throws -> [MediaItem] {
        var count = 0
        let catalog = try await MediaPageLoader.collect(didLoadPage: didLoadPage) { offset, limit in
            try Task.checkCancellation()
            guard generation == self.loadGeneration, self.session.isActive, self.matchesRestriction else { throw CancellationError() }
            var query = LibraryRequest.parameters(scope: self.scope, startIndex: offset, limit: limit, filter: filter)
            query.metadataOnly = true
            let task = Task { try await self.session.mediaProvider.items(query: query) }
            self.pageTask = task
            let page = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard generation == self.loadGeneration, self.session.isActive, self.matchesRestriction else { throw CancellationError() }
            count += page.items.count
            return page
        }
        guard catalog.count == count, catalog.allSatisfy({ $0.id != nil }) else {
            throw GusError.server(String(localized: "The server returned an incomplete collection. Try again."))
        }
        return catalog
    }

    private func scanPages(replaceResults: Bool, generation: Int) async throws {
        var replace = replaceResults
        for _ in 0 ..< 3 {
            try Task.checkCancellation()
            guard generation == loadGeneration, session.isActive else { return }
            let before = replace ? 0 : items.count
            try await loadPage(startIndex: replace ? 0 : paging.nextStartIndex, replaceResults: replace, generation: generation)
            guard generation == loadGeneration, session.isActive else { return }
            replace = false
            if items.count > before || !canLoadMore {
                break
            }
        }
    }

    private func saveFirstPage(_ items: [MediaItem], paging: Paging) {
        let preview = items.prefix(LibraryRequest.pageSize).map(\.browseSnapshotItem)
        session.browseCache.write(FirstPage(items: preview, paging: paging), key: cacheKey)
    }

    /// Stage a deep grid refresh so a visible card on page two never disappears
    /// while the first page is being replaced. Persist only the initial page.
    private func refreshLoadedPages(through depth: Int, generation: Int) async throws {
        var refreshed: [MediaItem] = []
        var cursor = Paging(pageSize: LibraryRequest.pageSize, prefetchThreshold: 12)
        var firstPage: FirstPage?
        repeat {
            let query = LibraryRequest.parameters(scope: scope, startIndex: cursor.nextStartIndex, limit: cursor.pageSize, filter: filter)
            let task = Task { try await session.mediaProvider.items(query: query) }
            pageTask = task
            let page = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard generation == loadGeneration, session.isActive, restriction == BrowseSnapshotCache.restriction else { throw CancellationError() }
            let total = try MediaPageLoader.validatedTotal(for: page, startIndex: cursor.nextStartIndex, previousTotal: cursor.totalRecordCount)
            let filtered = page.items.filter(admits)
            let display: [MediaItem]
            if case let .latest(kind) = scope {
                display = kind.displayItems(filtered)
            } else {
                display = filtered
            }
            refreshed += MediaPageLoader.unique(display, after: refreshed)
            cursor.appendResults(receivedCount: page.items.count, totalRecordCount: total)
            if firstPage == nil {
                firstPage = FirstPage(items: refreshed, paging: cursor)
            }
        } while cursor.canLoadMore && cursor.nextStartIndex < depth
        if let firstPage {
            saveFirstPage(firstPage.items, paging: firstPage.paging)
        }
        items = refreshed
        paging = cursor
        index(refreshed)
        state = .loaded
    }

    private func loadPage(startIndex: Int, replaceResults: Bool, generation: Int) async throws {
        if let target = scope.relatedSearch, target.id?.isEmpty != false {
            throw GusError.notFound
        }
        let query = LibraryRequest.parameters(
            scope: scope,
            startIndex: startIndex,
            limit: paging.pageSize,
            filter: filter
        )
        let task = Task { try await session.mediaProvider.items(query: query) }
        pageTask = task
        let page = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try Task.checkCancellation()
        guard generation == loadGeneration, session.isActive, restriction == BrowseSnapshotCache.restriction else { throw CancellationError() }
        let total = try MediaPageLoader.validatedTotal(for: page, startIndex: startIndex, previousTotal: replaceResults ? nil : paging.totalRecordCount)

        let admitted: [MediaItem]
        if case let .latest(kind) = scope {
            let existing = replaceResults ? [] : items
            admitted = MediaPageLoader.unique(kind.displayItems(page.items.filter(admits)), after: existing)
        } else {
            admitted = MediaPageLoader.unique(page.items.filter(admits), after: replaceResults ? [] : items)
        }
        if replaceResults {
            items = admitted
            paging.replaceResults(receivedCount: page.items.count, totalRecordCount: total)
        } else {
            items.append(contentsOf: admitted)
            paging.appendResults(receivedCount: page.items.count, totalRecordCount: total)
        }
        state = .loaded
        index(admitted)
    }

    private func index(_ admitted: [MediaItem]) {
        let serverID = session.server.id
        let userID = session.user.id
        Task.detached(priority: .background) {
            SpotlightIndexer.index(admitted, serverID: serverID, userID: userID)
        }
    }

    private func handle(_ error: Error) {
        let gusError = GusError(from: error)
        guard !gusError.isCancellation else {
            if state == .loading {
                state = .idle
            }; return
        }
        logger.error("Library load failed: \(gusError.localizedDescription, privacy: .private)")
        state = .failed(gusError.localizedDescription)
    }
}
