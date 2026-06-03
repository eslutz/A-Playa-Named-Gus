import Foundation
import JellyfinAPI
import Observation
import OSLog

/// Loads the items inside a single library (a `BaseItemDto` of kind `collectionFolder`).
///
/// Pattern reference: Swiftfin paginated `Paths.getItems(parentID:)` queries.
@MainActor
@Observable
final class LibraryStore {
    private(set) var state: LoadState = .idle
    private(set) var items: [BaseItemDto] = []

    let library: BaseItemDto
    private let session: SessionStore
    private let logger = Logger(category: .library)

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
        do {
            let parameters = Paths.GetItemsParameters(
                userID: session.user.id,
                startIndex: 0,
                limit: 300,
                isRecursive: false,
                sortOrder: [.ascending],
                parentID: library.id,
                fields: [.primaryImageAspectRatio, .overview],
                sortBy: [.sortName],
                enableUserData: true,
                enableImages: true
            )
            let response = try await session.client.send(Paths.getItems(parameters: parameters))
            items = response.value.items ?? []
            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return } // navigated away mid-load
            logger.error("Library load failed: \(gusError.localizedDescription, privacy: .public)")
            state = .failed(gusError.localizedDescription)
        }
    }
}
