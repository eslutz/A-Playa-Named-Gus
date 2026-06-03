import Foundation
import JellyfinAPI
import Observation
import OSLog

enum LibraryRequest {
    static let pageSize = 60
    static let metadataFields: [ItemFields] = [
        .primaryImageAspectRatio,
        .overview,
        .canDownload,
        .mediaStreams,
        .chapters,
    ]

    static func parameters(
        userID: String,
        parentID: String?,
        startIndex: Int,
        limit: Int
    ) -> Paths.GetItemsParameters {
        Paths.GetItemsParameters(
            userID: userID,
            startIndex: startIndex,
            limit: limit,
            isRecursive: false,
            sortOrder: [.ascending],
            parentID: parentID,
            fields: metadataFields,
            sortBy: [.sortName],
            enableUserData: true,
            enableTotalRecordCount: true,
            enableImages: true
        )
    }
}

/// Loads the items inside a single library (a `BaseItemDto` of kind `collectionFolder`).
///
/// Pattern reference: Swiftfin paginated `Paths.getItems(parentID:)` queries.
@MainActor
@Observable
final class LibraryStore {
    private(set) var state: LoadState = .idle
    private(set) var items: [BaseItemDto] = []
    private(set) var isLoadingNextPage = false

    let library: BaseItemDto
    private let session: SessionStore
    private let logger = Logger(category: .library)
    private var paging = Paging(pageSize: LibraryRequest.pageSize, prefetchThreshold: 12)

    init(library: BaseItemDto, session: SessionStore) {
        self.library = library
        self.session = session
    }

    var title: String {
        library.name ?? "Library"
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading
        paging.reset()
        do {
            try await loadPage(startIndex: 0, replaceResults: true)
        } catch {
            handle(error)
        }
    }

    var canLoadMore: Bool {
        paging.canLoadMore
    }

    func loadMoreIfNeeded(currentItem item: BaseItemDto) async {
        guard canLoadMore, !isLoadingNextPage, state == .loaded else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              paging.shouldLoadMore(currentIndex: index, loadedCount: items.count)
        else { return }

        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        do {
            try await loadPage(startIndex: paging.nextStartIndex, replaceResults: false)
        } catch {
            handle(error)
        }
    }

    private func loadPage(startIndex: Int, replaceResults: Bool) async throws {
        let parameters = LibraryRequest.parameters(
            userID: session.user.id,
            parentID: library.id,
            startIndex: startIndex,
            limit: paging.pageSize
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await session.client.send(Paths.getItems(parameters: parameters))
        }
        let page = response.value.items ?? []
        if replaceResults {
            items = page
            paging.replaceResults(receivedCount: page.count, totalRecordCount: response.value.totalRecordCount)
        } else {
            items.append(contentsOf: page)
            paging.appendResults(receivedCount: page.count, totalRecordCount: response.value.totalRecordCount)
        }
        state = .loaded
    }

    private func handle(_ error: Error) {
        let gusError = GusError(from: error)
        guard !gusError.isCancellation else { return } // navigated away mid-load
        logger.error("Library load failed: \(gusError.localizedDescription, privacy: .public)")
        state = .failed(gusError.localizedDescription)
    }
}
