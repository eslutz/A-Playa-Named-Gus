import Foundation
@testable import Gus
import Testing

@Suite("Search store helpers")
struct SearchStoreTests {
    @Test("one draft supports natural submit, keyword fallback and shared preference changes")
    @MainActor func unifiedSearchDraft() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = SearchHistoryStore(scope: .init(serverID: "s", userID: "u"), defaults: defaults)
        let root = RootNavigationState(searchHistory: history)
        let search = root.globalSearch
        root.editSearchText("mystery movies", naturalSearchEnabled: true)
        #expect(search.natural.submission == nil && search.typed.text.isEmpty)
        search.submit(naturalSearchEnabled: true, history: history)
        #expect(search.natural.submission != nil && history.entries.isEmpty)
        root.useKeywordSearchForCurrentDrafts()
        #expect(search.natural.submission == nil && search.displaysKeywords)
        #expect(search.text == "mystery movies" && search.typed.text == search.text)
        search.typed.selectedResult(.init(id: "m", name: "Movie", type: .movie), for: search.text, in: history)
        #expect(history.entries.isEmpty)
        root.editSearchText("mystery dramas", naturalSearchEnabled: true)
        #expect(search.displaysKeywords && search.typed.text == "mystery dramas")
        search.typed.selectedResult(.init(id: "m", name: "Movie", type: .movie), for: search.text, in: history)
        #expect(history.entries.isEmpty)
        search.submit(naturalSearchEnabled: true, history: history)
        #expect(search.natural.submission != nil && !search.displaysKeywords)
        search.searchByKeyword(recordingIn: history)
        #expect(search.natural.submission == nil && search.typed.text == search.text)
        #expect(history.entries == [.typed("mystery dramas")])
        root.editSearchText("mystery movies before 2001", naturalSearchEnabled: true)
        #expect(!search.displaysKeywords && search.natural.submission == nil && search.typed.text.isEmpty)
        root.replaySearch(.typed("Title"))
        #expect(root.globalSearch.displaysKeywords && root.globalSearch.text == "Title")
    }

    @Test("keyword submission reveals the results until the draft changes")
    @MainActor func submittedKeywordClosesSuggestions() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = SearchHistoryStore(scope: .init(serverID: "s", userID: "u"), defaults: defaults)
        let search = GlobalSearchSession()
        search.edit("Lantern", naturalSearchEnabled: false)
        #expect(search.showsDraftSuggestions)
        search.submit(naturalSearchEnabled: false, history: history)
        #expect(!search.showsDraftSuggestions && search.typed.text == "Lantern")
        search.edit("Lantern", naturalSearchEnabled: false)
        #expect(!search.showsDraftSuggestions)
        search.edit("Lanterns", naturalSearchEnabled: false)
        #expect(search.showsDraftSuggestions)
    }

    @Test("Clear Results finalizes eligible keyword history before native dismissal and cancels a pending natural search")
    @MainActor func clearResults() async throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = try #require(URL(string: "https://example.invalid"))
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.itemsHandler = { _ in .init(items: [], totalRecordCount: 0) }
        let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: .init(id: "u", name: "User", serverID: "s"), server: .init(id: "s", name: "Server", url: url), mediaProvider: provider, historyDefaults: defaults)
        let history = session.searchHistory
        let root = RootNavigationState(searchHistory: history)
        let search = root.globalSearch
        let owner = UUID()
        root.editSearchText("Lantern")
        let store = search.typed.acquireStore(session: session, owner: owner)
        await store.search("Lantern")
        search.typed.isPresented = true
        root.clearSearchResults {
            #expect(history.entries == [.typed("Lantern")])
            root.editSearchText("")
        }
        #expect(search.text.isEmpty && search.typed.text.isEmpty && !search.typed.isPresented)
        #expect(store.state == .idle)
        search.typed.release(owner: owner)
        root.editSearchText("Something to watch", naturalSearchEnabled: true)
        search.submit(naturalSearchEnabled: true, history: history)
        #expect(search.natural.submission != nil)
        root.clearSearchResults()
        #expect(search.natural.submission == nil && search.text.isEmpty)
        #expect(history.entries == [.typed("Lantern")])
    }

    @Test("suggestions deduplicate, exclude the current text and limit visible completions")
    @MainActor func nativeCompletions() {
        let terms = ["sci", "SCI", "Sci-fi", "SCI-FI", "Comedy", "Sci-Fi Series"]
        #expect(SearchCompletions.matching(" sci ", candidates: terms) == ["Sci-fi", "Sci-Fi Series"])
        #expect(SearchCompletions.matching(" ", candidates: terms).isEmpty)
        #expect(SearchCompletions.matching("s", candidates: (1 ... 12).map { "Series \($0)" }).count == 6)
    }

    @Test("cloud and shelf consent are separate and persist only for their account")
    @MainActor func scopedIntelligencePreferences() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scope = AccountScope(serverID: "a", userID: "user")
        let prefs = GusIntelligencePreferences(scope: scope, defaults: defaults)
        #expect(!prefs.cloudEnabled && !prefs.recommendationsEnabled)
        prefs.recommendationsEnabled = true
        #expect(!prefs.cloudEnabled)
        let restored = GusIntelligencePreferences(scope: scope, defaults: defaults)
        #expect(restored.recommendationsEnabled && !restored.cloudEnabled)
        restored.cloudEnabled = true
        let other = GusIntelligencePreferences(scope: .init(serverID: "b", userID: "user"), defaults: defaults)
        #expect(!other.cloudEnabled && !other.recommendationsEnabled)
        other.recommendationsEnabled = true
        GusIntelligencePreferences.delete(scope: scope, defaults: defaults)
        let removed = GusIntelligencePreferences(scope: scope, defaults: defaults)
        #expect(!removed.cloudEnabled && !removed.recommendationsEnabled)
        #expect(GusIntelligencePreferences(scope: .init(serverID: "b", userID: "user"), defaults: defaults).recommendationsEnabled)
    }

    @Test("recent searches keep the newest twenty distinct intents for one server and user")
    @MainActor func recentSearches() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let scope = AccountScope(serverID: "one", userID: "user")
        let history = SearchHistoryStore(scope: scope, defaults: defaults)
        let genre = RelatedSearch(kind: .genre, id: "42", name: "Horror")
        let studio = RelatedSearch(kind: .studio, id: "42", name: "Horror")
        for index in 1 ... 20 {
            history.record(.typed("Query " + String(index)))
        }
        history.record(.typed("  Horror  "))
        history.record(.related(genre))
        history.record(.related(studio))
        history.record(.typed("HORROR"))
        history.record(.related(.init(kind: .genre, id: "42", name: "Renamed")))
        history.record(.typed("  "))
        history.record(.related(.init(kind: .studio, name: "Unresolved")))
        #expect(history.entries.count == 20)
        #expect(history.entries.last == .typed("Query 4"))
        #expect(Array(history.entries.prefix(3)) == [.related(.init(kind: .genre, id: "42", name: "Renamed")), .typed("HORROR"), .related(studio)])

        let restored = SearchHistoryStore(scope: scope, defaults: defaults)
        #expect(restored.entries == history.entries)
        restored.remove(.related(genre))
        restored.remove(.typed(" horror "))
        #expect(restored.entries.first == .related(studio))
        let other = SearchHistoryStore(scope: .init(serverID: "two", userID: "user"), defaults: defaults)
        let otherUser = SearchHistoryStore(scope: .init(serverID: "one", userID: "other"), defaults: defaults)
        #expect(other.entries.isEmpty && otherUser.entries.isEmpty)
        other.record(.typed("Unrelated"))
        restored.clear()
        #expect(SearchHistoryStore(scope: scope, defaults: defaults).entries.isEmpty)
        #expect(other.entries == [.typed("Unrelated")])
    }

    @Test("editing queries is transient, while leaving, submitting and opening results record completion")
    @MainActor func completedSearches() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.itemsHandler = { _ in .init(items: [], totalRecordCount: 0) }
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: .init(id: "u", name: "User", serverID: "s"), server: .init(id: "s", name: "Server", url: url), mediaProvider: provider, historyDefaults: defaults)
        let state = SectionSearchState(retainsResults: true)
        let owner = UUID()
        let store = state.acquireStore(session: session, owner: owner)
        let history = session.searchHistory
        state.text = "Ho"
        await store.search(state.text)
        state.text = "Horror"
        state.completeLoadedSearch(in: history)
        #expect(history.entries.isEmpty)
        await store.search(state.text)
        state.selectedResult(.init(id: "h", name: "Horror", type: .genre), for: store.query, in: history)
        state.completeLoadedSearch(in: history)
        #expect(history.entries == [.related(.init(kind: .genre, id: "h", name: "Horror")), .typed("Horror")])
        state.text = "Explicit"
        state.submitSearch(to: history)
        #expect(history.entries.first == .typed("Explicit"))
        state.text = "Finished"
        await store.search(state.text)
        state.text = ""
        #expect(history.entries.first == .typed("Finished"))
        state.replayTyped("Horror", in: history)
        #expect(state.text == "Horror" && history.entries.first == .typed("Horror"))
        history.remove(.typed("Horror"))
        await store.search("Horror")
        state.release(owner: owner)
        state.completeLoadedSearch(in: history)
        #expect(!history.entries.contains(.typed("Horror")))
        #expect(state.store === store)
    }

    @Test("loading a longer saved history persists only the latest twenty completed queries")
    @MainActor func trimsPreviouslySavedHistory() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scope = AccountScope(serverID: "server", userID: "user")
        SearchHistoryStore(scope: scope, defaults: defaults).record(.typed("First"))
        let key = try #require(defaults.persistentDomain(forName: suite)?.keys.first)
        let queries = (1 ... 50).map { SearchHistoryEntry.typed("Query " + String($0)) }
        let saved = [.typed("  Query 1  "), .typed("QUERY 1"), .related(.init(kind: .studio, name: "Unknown"))] + queries
        try defaults.set(JSONEncoder().encode(saved), forKey: key)

        let loaded = SearchHistoryStore(scope: scope, defaults: defaults)
        #expect(loaded.entries == Array(queries.prefix(20)))
        let stored = try #require(defaults.data(forKey: key))
        #expect(try JSONDecoder().decode([SearchHistoryEntry].self, from: stored) == loaded.entries)
    }

    @Test("global Search retains its loaded result pages across removal and reattachment of the surface")
    @MainActor func globalSearchRetainsPages() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var requests = 0
        provider.itemsHandler = { _ in
            requests += 1
            return .init(items: [.init(id: "movie", name: "Movie", officialRating: "G", type: .movie)], totalRecordCount: 1)
        }
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: .init(id: "u", name: "User", serverID: "s"), server: .init(id: "s", name: "Server", url: url), mediaProvider: provider, historyDefaults: defaults)
        let state = SectionSearchState(retainsResults: true)
        let owner = UUID()
        var first: SearchStore? = state.acquireStore(session: session, owner: owner)
        weak let retained = first
        await first?.search("Movie")
        state.text = "Movie"
        state.release(owner: owner)
        first = nil
        #expect(retained != nil)
        let replacementOwner = UUID()
        var replacement: SearchStore? = state.acquireStore(session: session, owner: replacementOwner)
        #expect(replacement === retained && replacement?.query == "Movie")
        #expect(replacement?.results.compactMap(\.id) == ["movie"] && requests == 1)
        state.release(owner: replacementOwner)
        state.text = ""
        #expect(session.searchHistory.entries == [.typed("Movie")])
        #expect(replacement?.results.isEmpty == true)
        replacement = nil
        #expect(retained == nil)
    }

    @Test("an empty continuation below the remembered total preserves search results and retries the raw offset")
    @MainActor func incompleteContinuationRetry() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var fail = true
        var offsets: [Int] = []
        provider.itemsHandler = { query in
            offsets.append(query.startIndex)
            if query.startIndex == 0 {
                return .init(items: [.init(id: "a"), .init(id: "b")], totalRecordCount: 3)
            }
            return .init(items: fail ? [] : [.init(id: "c")], totalRecordCount: nil)
        }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: .init(id: "u", name: "User", serverID: "s"), server: .init(id: "s", name: "Server", url: url), mediaProvider: provider)
        let store = SearchStore(session: session, limit: 2, admits: { _ in true })
        await store.search("Psych")
        await store.continueSearching()
        #expect(store.results.compactMap(\.id) == ["a", "b"])
        #expect(store.state == .loaded && store.canLoadMore && store.pageError != nil)
        fail = false
        await store.continueSearching()
        #expect(offsets == [0, 2, 2])
        #expect(store.results.compactMap(\.id) == ["a", "b", "c"])
        #expect(!store.canLoadMore && store.pageError == nil)
    }

    @Test("failed same-query refresh retains complete results and retries from the first page")
    @MainActor func retainedRefreshRetry() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var phase = 0
        var offsets: [Int] = []
        provider.itemsHandler = { query in
            offsets.append(query.startIndex)
            if phase == 1 {
                throw URLError(.notConnectedToInternet)
            }
            let ids = phase == 2 ? ["updated-a", "updated-b"] : ["a", "b", "c"]
            let end = min(query.startIndex + query.limit, ids.count)
            return .init(items: ids[query.startIndex ..< end].map { .init(id: $0, type: .movie) }, totalRecordCount: ids.count)
        }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: .init(id: "u", name: "User", serverID: "s"), server: .init(id: "s", name: "Server", url: url), mediaProvider: provider)
        let store = SearchStore(session: session, limit: 2, admits: { _ in true })
        await store.search("Psych")
        await store.continueSearching()
        #expect(store.results.compactMap(\.id) == ["a", "b", "c"])
        #expect(!store.canLoadMore)

        phase = 1
        await store.search(store.query)
        #expect(store.state == .loaded && !store.isRefreshing)
        #expect(store.refreshError != nil && store.pageError == nil)
        #expect(store.results.compactMap(\.id) == ["a", "b", "c"])
        #expect(!store.canLoadMore)

        phase = 2
        await store.search(store.query)
        #expect(offsets == [0, 2, 0, 0])
        #expect(store.results.compactMap(\.id) == ["updated-a", "updated-b"])
        #expect(store.refreshError == nil && store.pageError == nil && !store.canLoadMore)
    }

    @Test("builds recursive provider search queries")
    func buildsSearchQuery() {
        let query = MediaItemQuery(
            searchTerm: "psych",
            startIndex: 25,
            limit: 50,
            isRecursive: true
        )

        #expect(query.searchTerm == "psych")
        #expect(query.startIndex == 25)
        #expect(query.limit == 50)
        #expect(query.isRecursive == true)
        #expect(query.sort == nil)
    }

    @Test("resets paging when the query changes")
    func resetsPagingForNewQuery() {
        var paging = Paging(pageSize: 50, prefetchThreshold: 1)

        paging.replaceResults(receivedCount: 50, totalRecordCount: 125)
        #expect(paging.nextStartIndex == 50)
        #expect(paging.canLoadMore)

        paging.reset()
        #expect(paging.nextStartIndex == 0)
        #expect(!paging.canLoadMore)
    }

    @Test("stops paging when the server returns fewer items than requested")
    func stopsPagingOnShortPage() {
        var paging = Paging(pageSize: 50, prefetchThreshold: 1)

        paging.replaceResults(receivedCount: 12, totalRecordCount: nil)

        #expect(paging.nextStartIndex == 12)
        #expect(!paging.canLoadMore)
    }
}
