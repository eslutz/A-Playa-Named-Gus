import Observation
import SwiftUI

/// Session-scoped state survives replacement of tab and split-view layouts.
@MainActor @Observable
final class RootNavigationState {
    static let moreID = "gus.more"
    static let searchID = "gus.search"
    let searchHistory: SearchHistoryStore?
    let globalSearch = GlobalSearchSession()
    private(set) var relatedResults: [UUID: RelatedSearchResults] = [:]

    var sheetPath: [GusRoute] = [] {
        didSet {
            #if os(tvOS)
                tvFocus.navigationChanged(section: "gus.detailSheet", from: oldValue.count, to: sheetPath.count)
            #endif
            routesChanged(from: oldValue, to: sheetPath, in: nil)
        }
    }

    init(searchHistory: SearchHistoryStore? = nil) {
        self.searchHistory = searchHistory
    }

    var selectedSectionID = NavigationSectionPreference.homeID
    #if os(iOS)
        var sidebarVisibility: NavigationSplitViewVisibility?
    #else
        var sidebarVisibility = NavigationSplitViewVisibility.automatic
    #endif
    var paths: [String: [GusRoute]] = [:] {
        didSet {
            for section in Set(oldValue.keys).union(paths.keys) {
                let before = oldValue[section] ?? []
                let after = paths[section] ?? []
                guard before != after else { continue }
                #if os(tvOS)
                    tvFocus.navigationChanged(section: section, from: before.count, to: after.count)
                #endif
                routesChanged(from: before, to: after, in: section)
            }
        }
    }

    private var lastOverflowSection: String?
    private var displayedOverflowIDs: [String] = []

    var scrollAnchors: [String: String] = [:]
    private(set) var returningDetailViewport: DetailViewportReturn?
    private var detailAnchors: [DetailStackPosition: (key: String, anchor: String)] = [:]
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
    var detailItem: ItemRef? {
        didSet {
            if detailItem != oldValue {
                resetDetailPath()
            }
        }
    }

    var downloadSearch = ""
    var downloadFilter = DownloadedLibraryFilter.all
    var isDownloadSearchPresented = false
    private var collections: CollectionStore?

    private func resetDetailPath() {
        sheetPath = []
        returningDetailViewport = nil
        detailAnchors = detailAnchors.filter { position, _ in
            if case .sheet = position.stack {
                return false
            }
            return true
        }
    }

    func presentDetail(_ item: ItemRef) {
        if detailItem == item {
            resetDetailPath()
        } else {
            detailItem = item
        }
    }

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
        let filterKey = scope.storeIdentity
        let key = searchResults?.storeKey ?? filterKey
        let store = LibraryStore(scope: scope, session: session, initialFilter: libraryFilters[filterKey]) { [weak self] filter in
            self?.libraryFilters[filterKey] = filter
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

    func selectSection(_ id: String) {
        let next = id == "gus.tv.search" ? Self.searchID : id
        guard next != selectedSectionID else { return }
        returningDetailViewport = nil
        if selectedSectionID == Self.searchID {
            if let searchHistory {
                globalSearch.typed.completeLoadedSearch(in: searchHistory)
            }
            globalSearch.typed.isPresented = false
            if globalSearch.natural.state == .loading {
                globalSearch.natural.resetResults()
            }
        }
        selectedSectionID = next
    }

    func openRelatedSearch(_ target: RelatedSearch, viewport: DetailScrollLocation? = nil) {
        if selectedSectionID == Self.searchID {
            if let searchHistory {
                globalSearch.typed.completeLoadedSearch(in: searchHistory)
            }
            globalSearch.typed.isPresented = false
        }
        let results = RelatedSearchResults(target: target, originatingViewport: viewport)
        relatedResults[results.id] = results
        if let resolved = results.resolved {
            searchHistory?.record(.related(resolved))
        }
        if detailItem != nil {
            sheetPath.append(.related(results.id))
        } else {
            paths[selectedSectionID, default: []].append(.related(results.id))
        }
    }

    func detailPosition(in stack: DetailNavigationStack?) -> DetailStackPosition? {
        guard let stack else { return nil }
        switch stack {
        case let .sheet(id):
            guard detailItem?.id == id else { return nil }
            return .init(stack: stack, depth: sheetPath.count)
        case let .section(id):
            return .init(stack: stack, depth: paths[id]?.count ?? 0)
        }
    }

    func takeReturningViewport(at position: DetailStackPosition?, key: String) -> DetailScrollLocation? {
        guard let request = returningDetailViewport, request.position == position, request.location.key == key else { return nil }
        returningDetailViewport = nil
        return request.location
    }

    func rememberDetailAnchor(_ anchor: String, at position: DetailStackPosition?, key: String) {
        guard let position, detailPosition(in: position.stack) == position else { return }
        detailAnchors[position] = (key, anchor)
    }

    func detailAnchor(at position: DetailStackPosition?, key: String) -> String? {
        guard let position, let saved = detailAnchors[position], saved.key == key else { return nil }
        return saved.anchor
    }

    /// A native pop can skip several pages using the Back menu. Restore only
    /// the viewport belonging to the detail immediately below the removed branch.
    func routesChanged(from old: [GusRoute], to new: [GusRoute], in sectionID: String?) {
        guard old != new else { return }
        let stack = sectionID.map(DetailNavigationStack.section) ?? detailItem.map { .sheet(itemID: $0.id) }
        if let stack, !old.isEmpty, !new.starts(with: old) {
            let commonDepth = zip(old, new).prefix(while: ==).count
            detailAnchors = detailAnchors.filter { $0.key.stack != stack || $0.key.depth <= commonDepth }
        }
        let visibleSection = detailItem == nil ? selectedSectionID : nil
        if sectionID == visibleSection {
            if let stack, new.count < old.count, old.starts(with: new), case let .related(id) = old[new.count],
               let location = relatedResults[id]?.originatingViewport
            {
                returningDetailViewport = .init(position: .init(stack: stack, depth: new.count), location: location)
            } else {
                returningDetailViewport = nil
            }
        }
        for case let .related(id) in old where !new.contains(.related(id)) {
            guard !sheetPath.contains(.related(id)), !paths.values.contains(where: { $0.contains(.related(id)) }),
                  let results = relatedResults.removeValue(forKey: id) else { continue }
            results.discard()
            #if os(tvOS)
                tvFocus.discardResults(context: results.storeKey)
                scrollAnchors[results.storeKey] = nil
            #endif
            let content = VisibleContent.library(results.storeKey)
            libraries[results.storeKey] = nil
            refreshedAt[content] = nil
            refreshTasks.removeValue(forKey: content)?.cancel()
            refreshTokens[content] = nil
        }
    }

    func showsSearchResults(_ viewport: SearchResultsViewport) -> Bool {
        let path = detailItem == nil ? paths[selectedSectionID] ?? [] : sheetPath
        if case let .related(id)? = path.last {
            return relatedResults[id]?.viewport === viewport
        }
        return detailItem == nil && selectedSectionID == Self.searchID && path.isEmpty && globalSearch.typed.viewport === viewport
    }

    func clearSearchResults(dismissField: () -> Void = {}) {
        if let searchHistory {
            globalSearch.typed.completeLoadedSearch(in: searchHistory)
        }
        dismissField()
        globalSearch.typed.isPresented = false
        globalSearch.edit("", naturalSearchEnabled: false)
    }

    func replaySearch(_ entry: SearchHistoryEntry) {
        guard let searchHistory else { return }
        switch entry {
        case let .related(target):
            openRelatedSearch(target)
        case let .typed(text):
            clearSearchResults()
            globalSearch.edit(text, naturalSearchEnabled: false)
            globalSearch.searchByKeyword(recordingIn: searchHistory)
        }
    }

    func editSearchText(_ text: String, naturalSearchEnabled: Bool = false) {
        globalSearch.edit(text, naturalSearchEnabled: naturalSearchEnabled)
    }

    func useKeywordSearchForCurrentDrafts() {
        globalSearch.applyKeywordPreference()
    }

    func pathBinding(for id: String) -> Binding<[GusRoute]> {
        Binding(get: { self.paths[id] ?? [] }, set: { path in
            guard self.selectedSectionID == id else { return }
            self.accept(path, for: id)
        })
    }

    /// Keep section history independent of its placement in tabs, More, or the sidebar.
    func morePathBinding(overflowIDs: [String]) -> Binding<[GusRoute]> {
        let owner = selectedSectionID
        return Binding(get: {
            let selected = self.selectedSectionID
            let section = overflowIDs.contains(selected) ? selected : self.lastOverflowSection
            if selected != Self.moreID, let section, overflowIDs.contains(section) {
                return [.section(section)] + (self.paths[section] ?? [])
            }
            return self.paths[Self.moreID] ?? []
        }, set: { path in
            let selected = self.selectedSectionID
            // A tab or layout change can retire this stack before SwiftUI delivers its last write.
            guard self.displayedOverflowIDs == overflowIDs, selected == owner,
                  selected == Self.moreID || overflowIDs.contains(selected) else { return }
            if case let .section(section) = path.first {
                guard overflowIDs.contains(section) else { return }
                if selected == section {
                    self.accept(Array(path.dropFirst()), for: section)
                } else if selected == Self.moreID {
                    self.lastOverflowSection = section
                    self.selectSection(section)
                }
            } else if overflowIDs.contains(selected) {
                guard path.isEmpty else { return }
                self.paths[selected] = []
                self.lastOverflowSection = nil
                self.selectSection(Self.moreID)
            } else {
                self.accept(path, for: Self.moreID)
            }
        })
    }

    func rememberOverflowSelection(in overflowIDs: [String]) {
        displayedOverflowIDs = overflowIDs
        if overflowIDs.contains(selectedSectionID) {
            lastOverflowSection = selectedSectionID
        } else if let lastOverflowSection, !overflowIDs.contains(lastOverflowSection) {
            self.lastOverflowSection = nil
        }
    }

    func useSidebar() {
        displayedOverflowIDs = []
        if selectedSectionID == Self.moreID {
            selectSection(NavigationSectionPreference.homeID)
        }
    }

    func selectMoreTab(overflowIDs: [String]) {
        guard !overflowIDs.contains(selectedSectionID) else { return }
        if let lastOverflowSection, overflowIDs.contains(lastOverflowSection) {
            selectSection(lastOverflowSection)
        } else {
            selectSection(Self.moreID)
        }
    }

    private func accept(_ path: [GusRoute], for section: String) {
        let previous = paths[section] ?? []
        guard path != previous else { return }
        paths[section] = path
        if path.count == previous.count + 1, path.starts(with: previous),
           case let .searchResult(ref, query) = path.last, let searchHistory
        {
            globalSearch.typed.selectedResult(ref.item, for: query, in: searchHistory)
        }
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

    #endif

    func reconcileTabSelection(sectionIDs: [String], overflowIDs: [String], librariesLoaded: Bool) {
        rememberOverflowSelection(in: overflowIDs)
        guard selectedSectionID != Self.searchID, !sectionIDs.contains(selectedSectionID) else { return }
        if selectedSectionID == Self.moreID {
            if overflowIDs.isEmpty {
                selectSection(sectionIDs.first ?? NavigationSectionPreference.homeID)
            }
        } else if librariesLoaded {
            // A hidden section can still be in scene restoration from a previous launch.
            selectSection(overflowIDs.isEmpty ? sectionIDs.first ?? NavigationSectionPreference.homeID : Self.moreID)
        }
    }

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

/// Fixed settings and request destinations in a signed-in stack.
enum AppScreen: Hashable {
    case downloads
    case navigationSettings
    case seerrRequests
    case seerrSettings
    case clientLogs
    #if !os(tvOS)
        case libraryIntelligence
    #endif
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
