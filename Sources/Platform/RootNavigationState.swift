import Observation
import SwiftUI

/// Session-scoped state survives replacement of tab and split-view layouts.
@MainActor @Observable
final class RootNavigationState {
    static let moreID = "gus.more"
    static let searchID = "gus.search"
    let searchHistory: SearchHistoryStore?
    var globalSearch = GlobalSearchSession()
    private(set) var keptSearch: GlobalSearchSession?
    var hasSearchReturn: Bool {
        globalSearch.detailOrigin != nil
    }

    var sheetPath = NavigationPath()

    init(searchHistory: SearchHistoryStore? = nil) {
        self.searchHistory = searchHistory
    }

    var selectedSectionID = NavigationSectionPreference.homeID
    #if os(iOS)
        var sidebarVisibility = NavigationSplitViewVisibility.doubleColumn
    #else
        var sidebarVisibility = NavigationSplitViewVisibility.automatic
    #endif
    var paths: [String: NavigationPath] = [:] {
        didSet {
            #if os(tvOS)
                for section in Set(oldValue.keys).union(paths.keys) {
                    tvFocus.navigationChanged(section: section, from: oldValue[section]?.count ?? 0, to: paths[section]?.count ?? 0)
                }
            #endif
        }
    }

    var scrollAnchors: [String: String] = [:]
    var returningDetailViewport: DetailScrollLocation?
    var libraryListModes: [String: Bool] = [:]
    var photoAlbumModes: [String: Bool] = [:]
    var librariesShowGrid = false
    var isProfilePresented = false
    /// Owned by this signed-in tree, so another account never inherits focus.
    var tvFocus = TVFocusMemory()
    var home: HomeStore? {
        didSet { refreshedAt[.home] = contentRevision }
    }

    var playerItem: ItemRef?
    var detailItem: ItemRef?
    var downloadSearch = ""
    var downloadFilter = DownloadedLibraryFilter.all
    var isDownloadSearchPresented = false
    private var collections: CollectionStore?

    func collectionStore(session: SessionStore) -> CollectionStore {
        if let collections, collections.session === session {
            return collections
        }
        collections?.invalidate()
        let store = CollectionStore(session: session)
        collections = store
        refreshedAt[.collections] = contentRevision
        session.registerCollectionStore(store)
        return store
    }

    private var searches: [String: SectionSearchState] = [:]
    /// Destinations own heavy stores. The root retains only small navigation
    /// choices after a destination leaves, so browsing does not retain every item.
    private final class StoreReference<Value: AnyObject> {
        weak var value: Value?
        init(_ value: Value) {
            self.value = value
        }
    }

    private var libraries: [String: StoreReference<LibraryStore>] = [:]
    private var details: [String: StoreReference<ItemDetailStore>] = [:]
    private var libraryFilters: [String: LibraryFilterState] = [:]
    private var selectedSeasons: [String: String] = [:]

    func searchState(for id: String) -> SectionSearchState {
        if id == Self.searchID {
            return globalSearch.typed
        }
        if let state = searches[id] {
            return state
        }
        let state = SectionSearchState()
        searches[id] = state
        refreshedAt[.search(id)] = contentRevision
        return state
    }

    func libraryStore(for scope: LibraryGridScope, session: SessionStore, searchResults: RelatedSearchResults? = nil) -> LibraryStore {
        if let pages = searchResults?.pages {
            return pages
        }
        if searchResults == nil, let store = libraries[scope.storeIdentity]?.value {
            return store
        }
        libraries = libraries.filter { $0.value.value != nil }
        let key = scope.storeIdentity
        let store = LibraryStore(scope: scope, session: session, initialFilter: libraryFilters[key]) { [weak self] filter in
            self?.libraryFilters[key] = filter
        }
        searchResults?.pages = store
        libraries[key] = StoreReference(store)
        refreshedAt[.library(key)] = contentRevision
        return store
    }

    /// An ebook may also be visible in a second, library-specific shelf.
    /// Refresh the edited snapshot immediately and reload hidden shelves on return.
    func refreshBookShelves(afterEditing store: LibraryStore) async {
        let affected = libraries.compactMap { key, reference -> VisibleContent? in
            guard let other = reference.value, other !== store, other.scope.groupsBookSeries else { return nil }
            return .library(key)
        }
        for content in affected {
            forceRefresh.insert(content)
            refreshedAt[content] = contentRevision - 1
        }
        await store.load(superseding: true)
        for content in affected {
            await refreshVisible(content)
        }
    }

    func detailStore(for item: MediaItem, session: SessionStore) -> ItemDetailStore {
        let current = item.id.flatMap { session.references.updates[$0] } ?? item
        let key = ItemRef(item: current).id
        if current.id != item.id {
            details.removeValue(forKey: ItemRef(item: item).id)
        }
        if let store = details[key]?.value {
            return store
        }
        details = details.filter { $0.value.value != nil }
        let store = ItemDetailStore(item: current, session: session, initialSeasonID: selectedSeasons[key]) { [weak self] seasonID in
            self?.selectedSeasons[key] = seasonID
        }
        details[key] = StoreReference(store)
        refreshedAt[.detail(key)] = contentRevision
        return store
    }

    enum VisibleContent: Hashable {
        case home, collections
        case library(String), detail(String), search(String)
    }

    private var forceRefresh = Set<VisibleContent>()
    private var lastForegroundRevision: Int?
    private var contentRevision = 0
    private var refreshedAt: [VisibleContent: Int] = [:]
    private var visibleOwners: [UUID: VisibleContent] = [:]
    @ObservationIgnored private var refreshTasks: [VisibleContent: Task<Void, Never>] = [:]
    private var refreshTokens: [VisibleContent: UUID] = [:]

    func setVisible(_ content: VisibleContent, owner: UUID) {
        visibleOwners[owner] = content
    }

    func setHidden(owner: UUID) {
        guard let content = visibleOwners.removeValue(forKey: owner), !visibleOwners.values.contains(content) else { return }
        if content == .collections {
            collections?.cancelForegroundLoads()
        }
        if case let .detail(id) = content, let detail = currentDetail(id) {
            if let season = detail.seriesStore?.selectedSeasonID {
                selectedSeasons[id] = season
            }
            if detail.cancelForegroundLoads() {
                refreshedAt[content] = min(refreshedAt[content] ?? contentRevision, contentRevision - 1)
            }
        }
        if let task = refreshTasks.removeValue(forKey: content) {
            task.cancel()
            refreshTokens[content] = nil
            // A canceled refresh remains dirty for the next visible owner.
            if contentRevision > 0 {
                refreshedAt[content] = min(refreshedAt[content] ?? 0, contentRevision - 1)
            }
        }
    }

    /// Invalidate all contexts, but perform network work only for visible owners.
    /// Back-stack choices and scroll/focus anchors remain lightweight root state.
    func refreshCachedContent(ifStale: Bool = false) async {
        contentRevision += 1
        lastForegroundRevision = ifStale ? contentRevision : nil
        for content in Set(visibleOwners.values) {
            guard !Task.isCancelled else { return }
            await refreshVisible(content)
        }
    }

    func refreshVisible(_ content: VisibleContent) async {
        while !Task.isCancelled, visibleOwners.values.contains(content), (refreshedAt[content] ?? 0) < contentRevision {
            if let task = refreshTasks[content] {
                await task.value; continue
            }
            // Initial/page work already in flight will call again when its
            // observable loading phase finishes, rather than starting duplicate work.
            guard canRefresh(content) else { return }
            let token = UUID()
            refreshedAt[content] = contentRevision
            refreshTokens[content] = token
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.performRefresh(content)
                if self.refreshTokens[content] == token {
                    self.refreshTasks[content] = nil
                    self.refreshTokens[content] = nil
                }
            }
            refreshTasks[content] = task
            await task.value
            if refreshTokens[content] == token {
                refreshTasks[content] = nil
                refreshTokens[content] = nil
            }
        }
    }

    private func currentDetail(_ id: String) -> ItemDetailStore? {
        details[id]?.value ?? details.values.compactMap(\.value).first { ItemRef(item: $0.item).id == id }
    }

    private func canRefresh(_ content: VisibleContent) -> Bool {
        switch content {
        case .home: return home?.state.isLoading == false
        case .collections: return collections?.state.isLoading == false
        case let .library(id): return libraries[id]?.value?.isLoading == false
        case let .detail(id): return currentDetail(id)?.state.isLoading == false
        case let .search(id):
            guard let store = searchState(for: id).store else { return false }
            return !store.state.isLoading && !store.isRefreshing && !store.isLoadingNextPage
        }
    }

    private func performRefresh(_ content: VisibleContent) async {
        guard visibleOwners.values.contains(content), !Task.isCancelled else { return }
        let ifStale = forceRefresh.remove(content) == nil && lastForegroundRevision == contentRevision
        switch content {
        case .home:
            if ifStale {
                await home?.loadIfNeeded()
            } else {
                await home?.refresh()
            }
        case .collections: await collections?.load(force: true)
        case let .library(id):
            if ifStale {
                await libraries[id]?.value?.loadIfNeeded()
            } else {
                await libraries[id]?.value?.load()
            }
        case let .detail(id): await currentDetail(id)?.load()
        case let .search(id):
            if let store = searchState(for: id).store, !store.query.isEmpty {
                await store.search(store.query)
            }
        }
    }

    /// Selecting Search after returning to a detail in its own stack resumes the kept results.
    func selectSection(_ id: String) {
        if selectedSectionID == Self.searchID, id != Self.searchID, let searchHistory {
            globalSearch.typed.completeLoadedSearch(in: searchHistory)
            globalSearch.typed.isPresented = false
            if globalSearch.natural.state == .loading {
                globalSearch.natural.resetResults()
            }
        }
        if id == Self.searchID {
            resumeKeptSearch()
        }
        selectedSectionID = id == "gus.tv.search" ? Self.searchID : id
    }

    func openRelatedSearch(_ target: RelatedSearch, focusContext: String? = nil, viewport: DetailScrollLocation? = nil) {
        if let searchHistory {
            globalSearch.typed.completeLoadedSearch(in: searchHistory)
        }
        let section = selectedSectionID
        globalSearch.typed.isPresented = false
        let origin = SearchDetailOrigin(
            section: section,
            path: paths[section] ?? NavigationPath(),
            sheet: detailItem,
            sheetPath: sheetPath,
            search: section == Self.searchID ? globalSearch : nil,
            scrollAnchors: scrollAnchors.filter { $0.key.hasPrefix("detail:") },
            viewport: viewport,
            focus: tvFocus,
            focusContext: focusContext
        )
        detailItem = nil
        returningDetailViewport = nil
        startRelated(target, from: origin)
    }

    private func startRelated(_ target: RelatedSearch, from origin: SearchDetailOrigin? = nil) {
        keptSearch = nil
        globalSearch = GlobalSearchSession(target: target)
        globalSearch.detailOrigin = origin
        if let related = globalSearch.related, let resolved = related.resolved {
            searchHistory?.record(.related(resolved))
        }
        paths[Self.searchID] = NavigationPath()
        selectedSectionID = Self.searchID
    }

    func backToSearchDetail() {
        guard let origin = globalSearch.detailOrigin else { return }
        globalSearch.detailOrigin = nil
        if let previous = origin.search {
            keptSearch = globalSearch
            globalSearch = previous
        }
        paths[origin.section] = origin.path
        selectedSectionID = origin.section
        sheetPath = origin.sheetPath
        detailItem = origin.sheet
        scrollAnchors.merge(origin.scrollAnchors) { _, original in original }
        returningDetailViewport = origin.viewport
        #if os(tvOS)
            tvFocus = origin.focus
            if let context = origin.focusContext {
                tvFocus.requestRestoration(context: context)
            }
        #endif
    }

    func resumeKeptSearch() {
        guard let keptSearch else { return }
        self.keptSearch = nil
        globalSearch = keptSearch
        paths[Self.searchID] = NavigationPath()
    }

    func closeSearchResults() {
        if let searchHistory {
            globalSearch.typed.completeLoadedSearch(in: searchHistory)
        }
        globalSearch.typed.isPresented = false
        globalSearch = GlobalSearchSession()
        keptSearch = nil
        paths[Self.searchID] = NavigationPath()
    }

    func replaySearch(_ entry: SearchHistoryEntry) {
        guard let searchHistory else { return }
        switch entry {
        case let .related(target): startRelated(target)
        case let .typed(text):
            closeSearchResults()
            globalSearch.edit(text, naturalSearchEnabled: false)
            globalSearch.searchByKeyword(recordingIn: searchHistory)
            selectedSectionID = Self.searchID
        }
    }

    /// Only an edit to the field replaces a related search. Tab selection and keyboard
    /// dismissal can change native presentation independently of the field's contents.
    func editSearchText(_ text: String, naturalSearchEnabled: Bool = false) {
        guard text != globalSearch.text else { return }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            globalSearch.related = nil
            globalSearch.detailOrigin = nil
            keptSearch = nil
        }
        globalSearch.edit(text, naturalSearchEnabled: naturalSearchEnabled)
    }

    /// A detail may have temporarily suspended another search in this window.
    func useKeywordSearchForCurrentDrafts() {
        var pending = [globalSearch, keptSearch].compactMap { $0 }
        while let search = pending.popLast() {
            if let previous = search.detailOrigin?.search {
                pending.append(previous)
            }
            search.applyKeywordPreference()
        }
    }

    func pathBinding(for id: String) -> Binding<NavigationPath> {
        Binding(get: { self.paths[id] ?? NavigationPath() }, set: { self.paths[id] = $0 })
    }

    func scrollBinding(for id: String) -> Binding<String?> {
        Binding(get: { self.scrollAnchors[id] }, set: { anchor in
            if self.scrollAnchors[id] != anchor {
                self.scrollAnchors[id] = anchor
            }
        })
    }

    /// Leave room for the native More and search tabs without losing account customization.
    static func iPhoneDirectSectionIDs(_ ids: [String], usesSavedOrder: Bool) -> [String] {
        let preferred = [NavigationSectionPreference.homeID, NavigationCategory.movies.id, NavigationCategory.tvshows.id]
        if usesSavedOrder {
            return Array(ids.prefix(3))
        }
        let initial = preferred.filter { ids.contains($0) }
        return Array((initial + ids.filter { !initial.contains($0) }).prefix(3))
    }

    #if os(visionOS)
        /// visionOS supports eight native tabs; reserve Search and, when needed, More.
        static func visionDirectSectionIDs(_ ids: [String]) -> [String] {
            ids.count > 7 ? Array(ids.prefix(6)) : ids
        }

        func reconcileVisionMoreSelection(sectionIDs: [String]) {
            guard selectedSectionID == Self.moreID, sectionIDs.count <= 7 else { return }
            selectedSectionID = sectionIDs.first ?? NavigationSectionPreference.homeID
        }
    #endif

    func adopt(_ route: AppRoute) {
        switch route {
        case .home: selectSection(NavigationSectionPreference.homeID)
        case .libraries: selectSection(NavigationSectionPreference.librariesID)
        case .downloaded: selectSection(NavigationSectionPreference.downloadedID)
        case .settings: selectSection(NavigationSectionPreference.settingsID)
        case .search:
            selectSection(Self.searchID)
        }
    }
}

@MainActor @Observable
final class SectionSearchState {
    @ObservationIgnored private weak var currentStore: SearchStore?
    private var retainedStore: SearchStore?
    @ObservationIgnored private weak var history: SearchHistoryStore?
    private let retainsResults: Bool
    var store: SearchStore? {
        retainedStore ?? currentStore
    }

    var scrollAnchor: String?
    private(set) var viewport = SearchResultsViewport()
    var text = "" {
        didSet {
            guard oldValue != text else { return }
            scrollAnchor = nil
            viewport = SearchResultsViewport()
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let history {
                    completeLoadedSearch(oldValue, in: history)
                }
                searchTask?.cancel()
                searchTask = nil
                store?.reset()
                retainedStore = nil
                requestedText = nil
            }
            lastCompletedQuery = nil
        }
    }

    var isPresented = false
    var showsList = false
    private var owners: Set<UUID> = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    private var requestedText: String?
    private var lastCompletedQuery: String?
    private var recordsTypedHistory = true

    /// Automatic fallback can search a natural-language prompt literally without
    /// adding its text to recents when the user later opens or leaves the results.
    func setKeywordText(_ value: String, recordsHistory: Bool) {
        text = value
        recordsTypedHistory = recordsHistory
        updateQuery()
    }

    init(retainsResults: Bool = false) {
        self.retainsResults = retainsResults
    }

    func submitSearch(to history: SearchHistoryStore) {
        recordTyped(text, in: history)
    }

    func completeLoadedSearch(in history: SearchHistoryStore) {
        completeLoadedSearch(text, in: history)
    }

    private func completeLoadedSearch(_ text: String, in history: SearchHistoryStore) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let store, store.state == .loaded, store.query == query, lastCompletedQuery != query else { return }
        recordTyped(query, in: history)
    }

    func selectedResult(_ item: MediaItem, for query: String, in history: SearchHistoryStore) {
        recordTyped(query, in: history)
        if item.type == .genre, let id = item.id {
            history.record(.related(.init(kind: .genre, id: id, name: item.displayTitle)))
        }
    }

    func replayTyped(_ query: String, in history: SearchHistoryStore) {
        text = query
        submitSearch(to: history)
        updateQuery()
    }

    private func recordTyped(_ text: String, in history: SearchHistoryStore) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard recordsTypedHistory, !query.isEmpty else { return }
        history.record(.typed(query))
        lastCompletedQuery = query
    }

    /// The single global search retains pages across section changes. Other
    /// holders retain only a weak lookup for adaptive replacement.
    func acquireStore(session: SessionStore, owner: UUID) -> SearchStore {
        let result: SearchStore
        if let currentStore {
            result = currentStore
        } else {
            result = SearchStore(session: session); requestedText = nil
        }
        history = session.searchHistory
        retain(result, owner: owner)
        return result
    }

    func retain(_ store: SearchStore, owner: UUID) {
        currentStore = store
        if retainsResults {
            retainedStore = store
        }
        owners.insert(owner)
        updateQuery()
    }

    func release(owner: UUID) {
        owners.remove(owner)
        guard owners.isEmpty else { return }
        searchTask?.cancel()
        searchTask = nil
        if let store, store.state.isLoading || store.isRefreshing || store.isLoadingNextPage {
            store.cancelForegroundLoad()
            requestedText = nil
        }
    }

    /// Debounced work has explicit visible owners and cannot retain a released
    /// search result store through the session's lightweight navigation registry.
    func updateQuery() {
        guard !owners.isEmpty, let store else { return }
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if query == store.query, store.state == .loaded || store.state == .loading {
            requestedText = query
            return
        }
        guard query != requestedText || store.state == .idle else { return }
        requestedText = query
        searchTask?.cancel()
        store.reset()
        guard !query.isEmpty else { return }
        searchTask = Task {
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }
            guard !Task.isCancelled else { return }
            await store.search(query)
        }
    }
}

/// Typed fixed destinations allow the shared NavigationPath to preserve Settings/Downloads.
enum AppScreen: Hashable {
    case downloads
    case navigationSettings
    case seerrRequests
}

/// Visibility belongs to a concrete view instance so adaptive replacement cannot
/// let an outgoing owner hide the replacement that is already on screen.
private struct VisibleContentModifier: ViewModifier {
    @Environment(RootNavigationState.self) private var navigation
    @State private var owner = UUID()
    @State private var isVisible = false
    let content: RootNavigationState.VisibleContent
    let isLoading: Bool

    func body(content view: Content) -> some View {
        view
            .onAppear {
                isVisible = true
                navigation.setVisible(content, owner: owner)
                Task { await navigation.refreshVisible(content) }
            }
            .onDisappear { isVisible = false; navigation.setHidden(owner: owner) }
            .onChange(of: content) { _, current in
                guard isVisible else { return }
                navigation.setHidden(owner: owner)
                navigation.setVisible(current, owner: owner)
                Task { await navigation.refreshVisible(current) }
            }
            .onChange(of: isLoading) { _, loading in
                if !loading {
                    Task { await navigation.refreshVisible(content) }
                }
            }
    }
}

extension View {
    func gusVisibleContent(_ content: RootNavigationState.VisibleContent, isLoading: Bool) -> some View {
        modifier(VisibleContentModifier(content: content, isLoading: isLoading))
    }
}
