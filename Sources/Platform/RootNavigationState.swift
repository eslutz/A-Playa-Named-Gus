import Observation
import SwiftUI

/// Session-scoped state survives replacement of tab and split-view layouts.
@MainActor @Observable
final class RootNavigationState {
    static let moreID = "gus.more"
    var selectedSectionID = NavigationSectionPreference.homeID
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
    /// Owned by this signed-in tree, so another account never inherits focus.
    var tvFocus = TVFocusMemory()
    var home: HomeStore?
    var playerItem: ItemRef?
    var detailItem: ItemRef?
    var downloadSearch = ""
    var downloadFilter = DownloadedLibraryFilter.all
    var isDownloadSearchPresented = false
    private var searches: [String: SectionSearchState] = [:]
    private var libraries: [String: LibraryStore] = [:]
    private var details: [String: ItemDetailStore] = [:]

    func searchState(for id: String, session: SessionStore) -> SectionSearchState {
        if let state = searches[id] {
            return state
        }
        let state = SectionSearchState(store: SearchStore(session: session))
        searches[id] = state
        return state
    }

    func libraryStore(for scope: LibraryGridScope, session: SessionStore) -> LibraryStore {
        if let store = libraries[scope.storeIdentity] {
            return store
        }
        let store = LibraryStore(scope: scope, session: session)
        libraries[scope.storeIdentity] = store
        Task { await store.load() }
        return store
    }

    func detailStore(for item: MediaItem, session: SessionStore) -> ItemDetailStore {
        let current = item.id.flatMap { session.references.updates[$0] } ?? item
        let key = ItemRef(item: current).id
        if current.id != item.id {
            details.removeValue(forKey: ItemRef(item: item).id)
        }
        if let store = details[key] {
            return store
        }
        let store = ItemDetailStore(item: current, session: session)
        details[key] = store
        Task { await store.load() }
        return store
    }

    func refreshCachedContent() async {
        await home?.refresh()
        for store in libraries.values {
            guard !Task.isCancelled else { return }
            await store.load()
        }
        for search in searches.values {
            guard !Task.isCancelled else { return }
            if !search.text.isEmpty {
                await search.store?.search(search.text)
            }
        }
        for store in details.values {
            guard !Task.isCancelled else { return }
            await store.load()
        }
    }

    func pathBinding(for id: String) -> Binding<NavigationPath> {
        Binding(get: { self.paths[id] ?? NavigationPath() }, set: { self.paths[id] = $0 })
    }

    func scrollBinding(for id: String) -> Binding<String?> {
        Binding(get: { self.scrollAnchors[id] }, set: { self.scrollAnchors[id] = $0 })
    }

    static func directSectionIDs(_ ids: [String]) -> [String] {
        ids.count > 5 ? Array(ids.prefix(4)) : ids
    }

    func adopt(_ route: AppRoute) {
        switch route {
        case .home: selectedSectionID = NavigationSectionPreference.homeID
        case .libraries: selectedSectionID = NavigationSectionPreference.librariesID
        case .downloaded: selectedSectionID = NavigationSectionPreference.downloadedID
        case .settings: selectedSectionID = NavigationSectionPreference.settingsID
        case .search: break
        }
    }
}

@MainActor @Observable
final class SectionSearchState {
    var store: SearchStore?
    var text = ""
    var isPresented = false
    private var searchTask: Task<Void, Never>?
    private var requestedText: String?

    /// Debounce belongs to the session state, so rotation cannot cancel the current query.
    func updateQuery() {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != requestedText, let store else { return }
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

    init(store: SearchStore) {
        self.store = store
    }
}

/// Typed fixed destinations allow the shared NavigationPath to preserve Settings/Downloads.
enum AppScreen: Hashable {
    case downloads
    case navigationSettings
}
