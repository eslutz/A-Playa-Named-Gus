/// Shared page-state helper for Jellyfin list endpoints.
struct Paging: Equatable {
    let pageSize: Int
    let prefetchThreshold: Int
    private(set) var nextStartIndex = 0
    private(set) var canLoadMore = false
    private(set) var totalRecordCount: Int?

    init(pageSize: Int, prefetchThreshold: Int = 12) {
        self.pageSize = pageSize
        self.prefetchThreshold = prefetchThreshold
    }

    mutating func reset() {
        nextStartIndex = 0
        canLoadMore = false
        totalRecordCount = nil
    }

    mutating func replaceResults(receivedCount: Int, totalRecordCount: Int?) {
        nextStartIndex = receivedCount
        self.totalRecordCount = totalRecordCount
        canLoadMore = hasMoreResults(loadedCount: receivedCount, receivedCount: receivedCount, totalRecordCount: totalRecordCount)
    }

    mutating func appendResults(receivedCount: Int, totalRecordCount: Int?) {
        nextStartIndex += receivedCount
        self.totalRecordCount = totalRecordCount ?? self.totalRecordCount
        canLoadMore = hasMoreResults(loadedCount: nextStartIndex, receivedCount: receivedCount, totalRecordCount: self.totalRecordCount)
    }

    func shouldLoadMore(currentIndex: Int, loadedCount: Int) -> Bool {
        guard canLoadMore, loadedCount > 0 else { return false }
        return currentIndex >= max(loadedCount - prefetchThreshold, 0)
    }

    private func hasMoreResults(loadedCount: Int, receivedCount: Int, totalRecordCount: Int?) -> Bool {
        guard receivedCount > 0 else { return false }
        if let totalRecordCount {
            return loadedCount < totalRecordCount
        }
        return receivedCount >= pageSize
    }
}
