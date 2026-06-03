@testable import Gus
import JellyfinAPI
import Testing

@Suite("Search store helpers")
struct SearchStoreTests {
    @Test("builds recursive item search parameters with rich metadata fields")
    func buildsSearchParameters() {
        let parameters = SearchRequest.parameters(
            userID: "user-1",
            query: " psych ",
            startIndex: 25,
            limit: 50
        )

        #expect(parameters.userID == "user-1")
        #expect(parameters.searchTerm == "psych")
        #expect(parameters.startIndex == 25)
        #expect(parameters.limit == 50)
        #expect(parameters.isRecursive == true)
        #expect(parameters.enableUserData == true)
        #expect(parameters.enableImages == true)
        #expect(parameters.enableTotalRecordCount == true)
        #expect(parameters.fields == SearchRequest.metadataFields)
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
