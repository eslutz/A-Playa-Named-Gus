import Foundation
@testable import Gus
import Testing

@Suite("Search store helpers")
struct SearchStoreTests {
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
