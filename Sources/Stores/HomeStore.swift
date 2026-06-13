import Foundation
import Observation
import OSLog

struct HomeLatestSection: Identifiable {
    let id: String
    let title: String
    let items: [MediaItem]
}

enum LatestMediaDisplayMapper {
    static func displayItems(from items: [MediaItem], libraryCollectionType: MediaCollectionType?) -> [MediaItem] {
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
    private(set) var libraries: [MediaItem] = []
    private(set) var resumeItems: [MediaItem] = []
    private(set) var nextUpItems: [MediaItem] = []
    private(set) var sharedWithYouTitle = String(
        localized: "Shared with You",
        comment: "Fallback title for Apple's Shared with You highlight collection"
    )
    private(set) var sharedWithYouItems: [MediaItem] = []
    private(set) var latestSections: [HomeLatestSection] = []

    private let session: SessionStore
    private let logger = Logger(category: .home)

    init(session: SessionStore) {
        self.session = session
    }

    func load() async {
        await load(showsLoadingState: true)
    }

    /// Reloads content in place. Already-loaded screens keep their content visible
    /// (no full-screen spinner flash) — used by pull-to-refresh and the post-playback
    /// revision bump.
    func refresh() async {
        await load(showsLoadingState: state != .loaded)
    }

    func loadSharedWithYou(links: [ContentLink], title: String) async {
        sharedWithYouTitle = title
        guard !links.isEmpty else {
            sharedWithYouItems = []
            return
        }

        let provider = session.mediaProvider
        let indexedItems = await withTaskGroup(of: (Int, MediaItem?).self) { group in
            for (index, link) in links.enumerated() {
                group.addTask { @MainActor in
                    do {
                        return try (index, await provider.item(id: link.itemID))
                    } catch {
                        return (index, nil)
                    }
                }
            }

            var collected: [(Int, MediaItem)] = []
            for await(index, item) in group {
                if let item {
                    collected.append((index, item))
                }
            }
            return collected
        }

        sharedWithYouItems = ContentRatingGate.filter(
            indexedItems.sorted { $0.0 < $1.0 }.map(\.1)
        )
    }

    private func load(showsLoadingState: Bool) async {
        if showsLoadingState {
            state = .loading
        }
        do {
            async let views = loadLibraries()
            async let resume = loadResume()
            async let nextUp = loadNextUp()
            libraries = try await views
            resumeItems = try await ContentRatingGate.filter(resume)
            nextUpItems = try await ContentRatingGate.filter(nextUp)
            latestSections = try await loadLatestSections(for: libraries)
            state = .loaded
            donateToSystemSearch()
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return } // navigated away mid-load
            logger.error("Home load failed: \(gusError.localizedDescription, privacy: .public)")
            state = .failed(gusError.localizedDescription)
        }
    }

    /// Donates the rating-gated home content to Core Spotlight (no-op where the
    /// platform lacks it) so library items surface in system search, and refreshes the
    /// optional tvOS Top Shelf snapshot when the app is signed with an App Group.
    private func donateToSystemSearch() {
        let items = resumeItems + nextUpItems + latestSections.flatMap(\.items)
        SpotlightIndexer.index(items, serverID: session.server.id, userID: session.user.id)

        #if os(tvOS)
            let provider = session.mediaProvider
            let shelfItems = (resumeItems + nextUpItems).prefix(8).compactMap { item -> TopShelfSnapshot.Item? in
                guard let id = item.id else { return nil }
                return TopShelfSnapshot.Item(
                    id: id,
                    title: item.displayTitle,
                    imageURL: provider.backdropImageURL(for: item, maxWidth: 1280),
                    playbackProgress: item.playbackProgress
                )
            }
            TopShelfSnapshot(items: Array(shelfItems)).save()
        #endif
    }

    private func loadLibraries() async throws -> [MediaItem] {
        try await session.mediaProvider.userViews()
    }

    private func loadResume() async throws -> [MediaItem] {
        try await session.mediaProvider.resumeItems(limit: 20)
    }

    private func loadNextUp() async throws -> [MediaItem] {
        try await session.mediaProvider.nextUpItems(seriesID: nil, limit: 20)
    }

    /// Fetches "Recently Added" rails for the first few libraries in parallel,
    /// preserving the library order in the returned sections.
    private func loadLatestSections(for libraries: [MediaItem]) async throws -> [HomeLatestSection] {
        let candidates = Array(libraries.prefix(6))
        let provider = session.mediaProvider

        let sectionsByIndex = try await withThrowingTaskGroup(
            of: (Int, HomeLatestSection?).self
        ) { group in
            for (index, library) in candidates.enumerated() {
                guard let parentID = library.id else { continue }
                group.addTask { @MainActor in
                    let latestItems = try await provider.latestMedia(in: library, limit: 12)
                    let items = ContentRatingGate.filter(
                        LatestMediaDisplayMapper.displayItems(from: latestItems, libraryCollectionType: library.collectionType)
                    )
                    guard !items.isEmpty else { return (index, nil) }
                    return (index, HomeLatestSection(
                        id: parentID,
                        title: String(
                            localized: "Recently Added \(library.name ?? "Library")",
                            comment: "Home latest media section title, e.g. Recently Added Movies"
                        ),
                        items: items
                    ))
                }
            }

            var collected: [(Int, HomeLatestSection)] = []
            for try await(index, section) in group {
                if let section {
                    collected.append((index, section))
                }
            }
            return collected
        }

        return sectionsByIndex.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
