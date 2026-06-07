@testable import Gus
import Testing

@Suite("Shared paging")
struct PagingTests {
    @Test("replaces results and prefetches within the configured threshold")
    func replacesResultsAndPrefetchesNearEnd() {
        var paging = Paging(pageSize: 60, prefetchThreshold: 12)

        paging.replaceResults(receivedCount: 60, totalRecordCount: 180)

        #expect(paging.pageSize == 60)
        #expect(paging.nextStartIndex == 60)
        #expect(paging.canLoadMore)
        #expect(!paging.shouldLoadMore(currentIndex: 47, loadedCount: 60))
        #expect(paging.shouldLoadMore(currentIndex: 48, loadedCount: 60))
        #expect(paging.shouldLoadMore(currentIndex: 59, loadedCount: 60))
    }

    @Test("appends pages and stops at the total record count")
    func appendsAndStopsAtTotalRecordCount() {
        var paging = Paging(pageSize: 60, prefetchThreshold: 12)

        paging.replaceResults(receivedCount: 60, totalRecordCount: 120)
        paging.appendResults(receivedCount: 60, totalRecordCount: 120)

        #expect(paging.nextStartIndex == 120)
        #expect(!paging.canLoadMore)
    }

    @Test("stops when a server without total count returns a short page")
    func stopsOnShortPageWithoutTotalCount() {
        var paging = Paging(pageSize: 60, prefetchThreshold: 12)

        paging.replaceResults(receivedCount: 31, totalRecordCount: nil)

        #expect(paging.nextStartIndex == 31)
        #expect(!paging.canLoadMore)
    }

    @Test("reset clears the next index and load-more state")
    func resetClearsState() {
        var paging = Paging(pageSize: 60, prefetchThreshold: 12)
        paging.replaceResults(receivedCount: 60, totalRecordCount: 180)

        paging.reset()

        #expect(paging.nextStartIndex == 0)
        #expect(!paging.canLoadMore)
    }
}
