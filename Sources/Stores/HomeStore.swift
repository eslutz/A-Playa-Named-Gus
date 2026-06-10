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
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return } // navigated away mid-load
            logger.error("Home load failed: \(gusError.localizedDescription, privacy: .public)")
            state = .failed(gusError.localizedDescription)
        }
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
