@testable import Gus
import Testing

@Suite("Search store helpers")
struct SearchStoreTests {
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
