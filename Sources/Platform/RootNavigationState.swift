import Observation
import SwiftUI

/// Session-scoped state survives replacement of tab and split-view layouts.
@MainActor @Observable
final class RootNavigationState {
    static let moreID = "gus.more"
    static let searchID = "gus.search"
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
        if let state = searches[id] {
            return state
        }
        let state = SectionSearchState()
        searches[id] = state
        refreshedAt[.search(id)] = contentRevision
        return state
    }

    func libraryStore(for scope: LibraryGridScope, session: SessionStore) -> LibraryStore {
        if let store = libraries[scope.storeIdentity]?.value {
            return store
        }
        libraries = libraries.filter { $0.value.value != nil }
        let key = scope.storeIdentity
        let store = LibraryStore(scope: scope, session: session, initialFilter: libraryFilters[key]) { [weak self] filter in
            self?.libraryFilters[key] = filter
        }
        libraries[key] = StoreReference(store)
        refreshedAt[.library(key)] = contentRevision
        return store
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
    func refreshCachedContent() async {
        contentRevision += 1
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
            guard let store = searches[id]?.store else { return false }
            return !store.state.isLoading && !store.isRefreshing && !store.isLoadingNextPage
        }
    }

    private func performRefresh(_ content: VisibleContent) async {
        guard visibleOwners.values.contains(content), !Task.isCancelled else { return }
        switch content {
        case .home: await home?.refresh()
        case .collections: await collections?.load(force: true)
        case let .library(id): await libraries[id]?.value?.load()
        case let .detail(id): await currentDetail(id)?.load()
        case let .search(id):
            if let store = searches[id]?.store, !store.query.isEmpty {
                await store.search(store.query)
            }
        }
    }

    func pathBinding(for id: String) -> Binding<NavigationPath> {
        Binding(get: { self.paths[id] ?? NavigationPath() }, set: { self.paths[id] = $0 })
    }

    func scrollBinding(for id: String) -> Binding<String?> {
        Binding(get: { self.scrollAnchors[id] }, set: { self.scrollAnchors[id] = $0 })
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

    func adopt(_ route: AppRoute) {
        switch route {
        case .home: selectedSectionID = NavigationSectionPreference.homeID
        case .libraries: selectedSectionID = NavigationSectionPreference.librariesID
        case .downloaded: selectedSectionID = NavigationSectionPreference.downloadedID
        case .settings: selectedSectionID = NavigationSectionPreference.settingsID
        case .search:
            #if os(iOS)
                selectedSectionID = Self.searchID
            #else
                break
            #endif
        }
    }
}

@MainActor @Observable
final class SectionSearchState {
    @ObservationIgnored private weak var currentStore: SearchStore?
    var store: SearchStore? {
        currentStore
    }

    var text = ""
    var isPresented = false
    var showsList = false
    private var owners: Set<UUID> = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    private var requestedText: String?

    /// The view owns results; this account-scoped object retains only field and
    /// presentation choices plus a non-owning lookup for adaptive replacement.
    func acquireStore(session: SessionStore, owner: UUID) -> SearchStore {
        let result: SearchStore
        if let currentStore {
            result = currentStore
        } else {
            result = SearchStore(session: session); requestedText = nil
        }
        retain(result, owner: owner)
        return result
    }

    func retain(_ store: SearchStore, owner: UUID) {
        currentStore = store
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
