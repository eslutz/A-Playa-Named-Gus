import Foundation
import JellyfinAPI
import Observation
import OSLog

struct HomeLatestSection: Identifiable {
    let id: String
    let title: String
    let items: [BaseItemDto]
}

enum LatestMediaRequest {
    static func parameters(userID: String, library: BaseItemDto, limit: Int = 12) -> Paths.GetLatestMediaParameters {
        Paths.GetLatestMediaParameters(
            userID: userID,
            parentID: library.id,
            fields: [.primaryImageAspectRatio],
            enableImages: true,
            enableUserData: true,
            limit: limit,
            isGroupItems: library.collectionType == .tvshows
        )
    }
}

enum LatestMediaDisplayMapper {
    static func displayItems(from items: [BaseItemDto], libraryCollectionType: CollectionType?) -> [BaseItemDto] {
        guard libraryCollectionType == .tvshows else {
            return items
        }

        var seenSeriesIDs: Set<String> = []
        return items.compactMap { item in
            let displayItem = item.latestTVDisplayItem
            guard let id = displayItem.id else { return displayItem }
            guard seenSeriesIDs.insert(id).inserted else { return nil }
            return displayItem
        }
    }
}

/// Loads the signed-in user's library views and "Continue Watching" items.
///
/// Pattern reference: Swiftfin's `HomeViewModel` (`Paths.getUserViews` +
/// `Paths.getResumeItems`).
@MainActor
@Observable
final class HomeStore {
    private(set) var state: LoadState = .idle
    private(set) var libraries: [BaseItemDto] = []
    private(set) var resumeItems: [BaseItemDto] = []
    private(set) var nextUpItems: [BaseItemDto] = []
    private(set) var latestSections: [HomeLatestSection] = []

    private let session: SessionStore
    private let logger = Logger(category: .home)

    init(session: SessionStore) {
        self.session = session
    }

    func load() async {
        state = .loading
        do {
            async let views = loadLibraries()
            async let resume = loadResume()
            async let nextUp = loadNextUp()
            libraries = try await views
            resumeItems = try await resume
            nextUpItems = try await nextUp
            latestSections = try await loadLatestSections(for: libraries)
            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return } // navigated away mid-load
            logger.error("Home load failed: \(gusError.localizedDescription, privacy: .public)")
            state = .failed(gusError.localizedDescription)
        }
    }

    private func loadLibraries() async throws -> [BaseItemDto] {
        let parameters = Paths.GetUserViewsParameters(userID: session.user.id)
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await session.client.send(Paths.getUserViews(parameters: parameters))
        }
        return response.value.items ?? []
    }

    private func loadResume() async throws -> [BaseItemDto] {
        let parameters = Paths.GetResumeItemsParameters(
            userID: session.user.id,
            limit: 20,
            fields: [.primaryImageAspectRatio],
            enableUserData: true,
            includeItemTypes: [.movie, .episode],
            enableImages: true
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await session.client.send(Paths.getResumeItems(parameters: parameters))
        }
        return response.value.items ?? []
    }

    private func loadNextUp() async throws -> [BaseItemDto] {
        let parameters = Paths.GetNextUpParameters(
            userID: session.user.id,
            startIndex: 0,
            limit: 20,
            fields: [.primaryImageAspectRatio],
            enableImages: true,
            enableUserData: true,
            enableTotalRecordCount: true,
            enableResumable: true
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await session.client.send(Paths.getNextUp(parameters: parameters))
        }
        return response.value.items ?? []
    }

    private func loadLatestSections(for libraries: [BaseItemDto]) async throws -> [HomeLatestSection] {
        var sections: [HomeLatestSection] = []

        for library in libraries.prefix(6) {
            guard let parentID = library.id else { continue }
            let parameters = LatestMediaRequest.parameters(userID: session.user.id, library: library)
            let response = try await NetworkRetryPolicy.idempotent.run {
                try await session.client.send(Paths.getLatestMedia(parameters: parameters))
            }
            let items = LatestMediaDisplayMapper.displayItems(from: response.value, libraryCollectionType: library.collectionType)
            if !items.isEmpty {
                sections.append(
                    HomeLatestSection(
                        id: parentID,
                        title: String(
                            localized: "Recently Added \(library.name ?? "Library")",
                            comment: "Home latest media section title, e.g. Recently Added Movies"
                        ),
                        items: items
                    )
                )
            }
        }

        return sections
    }
}
