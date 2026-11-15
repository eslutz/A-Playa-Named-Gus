import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("Navigation ownership")
struct NavigationOwnershipTests {
    @Test("live destinations reuse stores while released stores free their media and preserve filters")
    func retainedChoicesWithoutRetainedRows() async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemsHandler = { _ in MediaItemPage(items: [], totalRecordCount: 0) }
        let session = try SessionStore(client: JellyfinClientFactory.makeClient(url: #require(URL(string: "https://example.invalid"))), user: StoredUser(id: "u", name: "User", serverID: "s"), server: ServerConnection(id: "s", name: "Server", url: #require(URL(string: "https://example.invalid"))), mediaProvider: provider)
        let navigation = RootNavigationState()
        let scope = LibraryGridScope.category(.movies)
        var store: LibraryStore? = navigation.libraryStore(for: scope, session: session)
        weak let weakStore = store
        #expect(navigation.libraryStore(for: scope, session: session) === store)
        let filter = LibraryFilterState(sort: .rating, status: .unplayed)
        await store?.applyFilter(filter)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        store = nil
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(weakStore == nil)
        let replacement = navigation.libraryStore(for: scope, session: session)
        #expect(replacement.filter == filter)
    }

    @Test("factories do not start unowned requests and canceled view loads release stores")
    func viewOwnedLoading() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var started = false
        var canceled = false
        provider.itemsHandler = { _ in
            started = true
            do { try await Task.sleep(for: .seconds(100)) }
            catch { canceled = true; throw error }
            return .init(items: [], totalRecordCount: 0)
        }
        let navigation = RootNavigationState()
        let active = try makeSession(provider)
        var store: LibraryStore? = navigation.libraryStore(for: .category(.movies), session: active)
        weak let weakStore = store
        #expect(!started)
        var loading: Task<Void, Never>? = Task { [store] in
            if let store {
                await store.load()
            }
        }
        try await waitUntil { started }
        store = nil
        loading?.cancel()
        await loading?.value
        loading = nil
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(canceled)
        #expect(weakStore == nil)
    }

    @Test("only visible contexts refresh and dirty Back-stack contexts refresh on revisit")
    func refreshVisibility() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var reads: [String: Int] = [:]
        provider.itemsHandler = { query in
            reads[query.parentID ?? "", default: 0] += 1
            return .init(items: [], totalRecordCount: 0)
        }
        let navigation = RootNavigationState()
        let active = try makeSession(provider)
        let firstScope = LibraryGridScope.library(.init(id: "first"))
        let secondScope = LibraryGridScope.library(.init(id: "second"))
        let first = navigation.libraryStore(for: firstScope, session: active)
        let second = navigation.libraryStore(for: secondScope, session: active)
        await first.load(); await second.load()
        let oldOwner = UUID(), replacementOwner = UUID()
        navigation.setVisible(.library(firstScope.storeIdentity), owner: oldOwner)
        navigation.setVisible(.library(firstScope.storeIdentity), owner: replacementOwner)
        navigation.setHidden(owner: oldOwner)
        await navigation.refreshCachedContent()
        #expect(reads["first"] == 2)
        #expect(reads["second"] == 1)
        navigation.setHidden(owner: replacementOwner)
        await navigation.refreshCachedContent()
        #expect(reads["first"] == 2)
        let secondOwner = UUID()
        navigation.setVisible(.library(secondScope.storeIdentity), owner: secondOwner)
        await navigation.refreshVisible(.library(secondScope.storeIdentity))
        #expect(reads["second"] == 2)
        #expect(navigation.libraryStore(for: firstScope, session: active) === first)
    }

    @Test("leaving the last visible owner cancels its suspended refresh")
    func cancelsInvisibleRefresh() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.itemsHandler = { _ in .init(items: [], totalRecordCount: 0) }
        let navigation = RootNavigationState()
        let scope = LibraryGridScope.category(.movies)
        let store = try navigation.libraryStore(for: scope, session: makeSession(provider))
        await store.load()
        var started = false, canceled = false
        provider.itemsHandler = { _ in
            started = true
            do { try await Task.sleep(for: .seconds(100)) }
            catch { canceled = true; throw error }
            return .init(items: [], totalRecordCount: 0)
        }
        let owner = UUID()
        navigation.setVisible(.library(scope.storeIdentity), owner: owner)
        let refreshing = Task { await navigation.refreshCachedContent() }
        try await waitUntil { started }
        navigation.setHidden(owner: owner)
        await refreshing.value
        #expect(canceled)
        #expect(!store.isLoading)
    }

    @Test("collection refresh stops when its last visible surface leaves")
    func cancelsInvisibleCollectionRefresh() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var started = false, canceled = false
        provider.collectionPageHandler = { _, _ in
            started = true
            do { try await Task.sleep(for: .seconds(100)) }
            catch { canceled = true; throw error }
            return .init(items: [], totalRecordCount: 0)
        }
        let navigation = RootNavigationState()
        let store = try navigation.collectionStore(session: makeSession(provider))
        let owner = UUID()
        navigation.setVisible(.collections, owner: owner)
        let refresh = Task { await navigation.refreshCachedContent() }
        try await waitUntil { started }
        navigation.setHidden(owner: owner)
        await refresh.value
        #expect(canceled)
        #expect(store.state == .idle)
    }

    @Test("search result pages belong to alive views while navigation keeps only lightweight choices")
    func searchOwnershipAndBack() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var reads = 0
        provider.itemsHandler = { query in
            reads += 1
            let end = min(query.startIndex + query.limit, 51)
            return .init(items: (query.startIndex ..< end).map { .init(id: "item-\($0)", name: "Item", officialRating: "G", type: .movie) }, totalRecordCount: 51)
        }
        let active = try makeSession(provider)
        let navigation = RootNavigationState()
        let state = navigation.searchState(for: "movies")
        let firstOwner = UUID(), backOwner = UUID()
        var store: SearchStore? = state.acquireStore(session: active, owner: firstOwner)
        weak let weakStore = store
        await store?.search("Psych")
        await store?.continueSearching()
        #expect(store?.results.count == 51)
        state.text = "Psych"
        state.showsList = true
        state.updateQuery()
        state.release(owner: firstOwner)
        // A native Back-stack view still owns its @State result store.
        let backStore = state.acquireStore(session: active, owner: backOwner)
        #expect(backStore === store)
        #expect(backStore.results.count == 51 && reads == 2)
        state.release(owner: backOwner)
        store = nil
        #expect(state.text == "Psych" && state.showsList)
        #expect(weakStore != nil) // this scope's live Back view still owns backStore
    }

    @Test("released search holders cancel requests and free heavy result state")
    func releasedSearchStore() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var started = false, canceled = false
        provider.itemsHandler = { _ in
            started = true
            do { try await Task.sleep(for: .seconds(100)) }
            catch { canceled = true; throw error }
            return .init(items: [], totalRecordCount: 0)
        }
        let state = RootNavigationState().searchState(for: "movies")
        state.text = "Psych"
        let owner = UUID()
        var store: SearchStore? = try state.acquireStore(session: makeSession(provider), owner: owner)
        weak let weakStore = store
        try await waitUntil { started }
        state.release(owner: owner)
        store = nil
        try await waitUntil { canceled && weakStore == nil }
        #expect(state.text == "Psych")
    }

    @Test("replacement detail work cancels only after the last visible owner leaves or its lease expires", arguments: [false, true])
    func replacementDetailOwnership(expireSession: Bool) async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var started = false, canceled = false
        provider.similarItemsHandler = { _ in
            started = true
            do { try await Task.sleep(for: .seconds(100)) }
            catch { canceled = true; throw error }
            return []
        }
        provider.specialFeaturesHandler = { _ in [] }
        let session = try makeSession(provider)
        let navigation = RootNavigationState()
        var store: ItemDetailStore? = navigation.detailStore(for: MediaItem(id: "old", type: .movie), session: session)
        weak let weakStore = store
        let replacement = MediaItem(id: "new", type: .movie)
        store?.acceptResolvedMetadata(replacement)
        let content = RootNavigationState.VisibleContent.detail(ItemRef(item: replacement).id)
        let departingOwner = UUID(), liveOwner = UUID()
        navigation.setVisible(content, owner: departingOwner)
        navigation.setVisible(content, owner: liveOwner)
        try await waitUntil { started }
        navigation.setHidden(owner: departingOwner)
        #expect(!canceled)
        if expireSession {
            session.invalidate()
        } else {
            navigation.setHidden(owner: liveOwner)
        }
        store = nil
        try await waitUntil { canceled && weakStore == nil }
    }

    @Test("lease expiry cancels season and episode requests before the view leaves", arguments: [false, true])
    func seriesLeaseCancellation(waitingForSeasons: Bool) async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var started = false, canceled = false
        provider.seasonsHandler = {
            if waitingForSeasons {
                started = true
                do { try await Task.sleep(for: .seconds(100)) }
                catch { canceled = true; throw error }
            }
            return [MediaItem(id: "season", indexNumber: 1, type: .season)]
        }
        provider.episodesHandler = { _ in
            started = true
            do { try await Task.sleep(for: .seconds(100)) }
            catch { canceled = true; throw error }
            return .init(items: [], totalRecordCount: 0)
        }
        let session = try makeSession(provider)
        var store: SeriesDetailStore? = SeriesDetailStore(series: MediaItem(id: "series", type: .series), session: session)
        weak let weakStore = store
        var loading: Task<Void, Never>? = Task { [store] in
            if let store {
                await store.loadSeasons()
            }
        }
        try await waitUntil { started }
        session.invalidate()
        await loading?.value
        loading = nil
        store = nil
        try await waitUntil { canceled && weakStore == nil }
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0 ..< 2000 {
            if predicate() {
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(predicate(), "Timed out awaiting the ownership boundary")
    }

    private func makeSession(_ provider: FakeMediaProviderSession) throws -> SessionStore {
        let url = try #require(URL(string: "https://example.invalid"))
        return SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: .init(id: "u", name: "User", serverID: "s"), server: .init(id: "s", name: "Server", url: url), mediaProvider: provider)
    }
}
