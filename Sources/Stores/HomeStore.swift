import Foundation
import Observation
import OSLog

struct HomeLatestSection: Identifiable, Sendable {
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
    private(set) var errorMessage: String?
    private(set) var unifiedNextUp: [NextUpEntry] = []
    private var savedIntents: [UpNextEntry] = []
    private var playlistCandidates: [NextUpPlaylistCandidate] = []
    private let activity: NextUpActivityStore
    private var resumeOffset = 0
    private var nextOffset = 0
    private var resumeHasMore = false
    private var nextHasMore = false
    private var loadGeneration = UUID()
    private(set) var isLoadingMore = false
    var hasMoreNextUp: Bool {
        resumeHasMore || nextHasMore
    }

    private let nextUpPageSize = 50
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

    init(session: SessionStore, activity: NextUpActivityStore = .shared) {
        self.session = session
        self.activity = activity
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

        let server = session.server
        let resolver = session.references
        let indexedItems = await withTaskGroup(of: (Int, MediaItem?).self) { group in
            for (index, link) in links.enumerated() {
                group.addTask {
                    do {
                        guard link.accepts(server: server) else { return (index, nil) }
                        let current = try await resolver.currentItem(MediaItem(providerKind: server.providerKind, id: link.itemID))
                        return (index, current)
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

    func updateNextUp(saved: [UpNextEntry], playlists: [NextUpPlaylistCandidate]) {
        savedIntents = saved.filter { $0.reference.scope == session.references.scope && ContentRatingGate.admitsStored($0.reference.item) }
        playlistCandidates = playlists
        rebuildNextUp()
        donateToSystemSearch()
    }

    private func rebuildNextUp() {
        let scope = session.references.scope
        unifiedNextUp = NextUpBuilder.build(
            resume: resumeItems, nextEpisodes: nextUpItems, saved: savedIntents,
            playlists: playlistCandidates, activity: activity.snapshot(scope: scope),
            firstSeenIDs: activity.firstSeenIDs(scope: scope)
        ).filter { !activity.isDismissed($0.id, scope: scope) }
        activity.remember(unifiedNextUp.map(\.id), scope: scope)
    }

    private func load(showsLoadingState: Bool) async {
        let generation = UUID()
        loadGeneration = generation
        isLoadingMore = false
        if showsLoadingState {
            state = .loading
        }
        // Independent failures preserve successful responses and usable cached
        // content. A failed latest-media rail cannot hide saved/offline intents.
        async let views = libraryResult()
        let resumeLimit = max(resumeOffset, nextUpPageSize)
        let nextLimit = max(nextOffset, nextUpPageSize)
        async let resume = resumeResult(startIndex: 0, limit: resumeLimit)
        async let next = nextUpResult(startIndex: 0, limit: nextLimit)
        let results = await(views, resume, next)
        guard !Task.isCancelled, session.references.isActive, loadGeneration == generation else { return }
        var errors: [GusError] = []
        switch results.0 {
        case let .success(items): libraries = items
        case let .failure(error): errors.append(error)
        }
        switch results.1 {
        case let .success(page):
            resumeItems = ContentRatingGate.filter(page.items)
            resumeOffset = page.items.count
            resumeHasMore = Self.hasMore(page: page, offset: resumeOffset, requested: resumeLimit)
        case let .failure(error): errors.append(error)
        }
        switch results.2 {
        case let .success(page):
            nextUpItems = ContentRatingGate.filter(page.items)
            nextOffset = page.items.count
            nextHasMore = Self.hasMore(page: page, offset: nextOffset, requested: nextLimit)
        case let .failure(error): errors.append(error)
        }
        errorMessage = nil
        do { latestSections = try await loadLatestSections(for: libraries) }
        catch { errors.append(GusError(from: error)) }
        guard !Task.isCancelled, session.references.isActive, loadGeneration == generation else { return }
        errorMessage = errors.first(where: { !$0.isCancellation })?.localizedDescription ?? errorMessage
        if errors.contains(.unauthorized) {
            session.onUnauthorized()
        }
        // HomeView renders a banner if usable content survives, otherwise its
        // usual unavailable screen. Local Next Up can arrive after this request.
        state = errorMessage.map { .failed($0) } ?? .loaded
        rebuildNextUp()
        donateToSystemSearch()
    }

    private func libraryResult() async -> Result<[MediaItem], GusError> {
        do { return try .success(await session.mediaProvider.userViews()) }
        catch { return .failure(GusError(from: error)) }
    }

    private func resumeResult(startIndex: Int, limit: Int) async -> Result<MediaItemPage, GusError> {
        do { return try .success(await session.mediaProvider.resumeItemsPage(startIndex: startIndex, limit: limit)) }
        catch { return .failure(GusError(from: error)) }
    }

    private func nextUpResult(startIndex: Int, limit: Int) async -> Result<MediaItemPage, GusError> {
        do { return try .success(await session.mediaProvider.nextUpItemsPage(startIndex: startIndex, limit: limit)) }
        catch { return .failure(GusError(from: error)) }
    }

    private static func hasMore(page: MediaItemPage, offset: Int, requested: Int) -> Bool {
        guard !page.items.isEmpty else { return false }
        return page.totalRecordCount.map { offset < $0 } ?? (page.items.count == requested)
    }

    /// Fetches both automatic sources incrementally. Offsets count raw provider
    /// records, including rating-gated and deduplicated records, avoiding skipped
    /// pages when fewer cards are visible than records returned.
    func loadMoreNextUp() async {
        guard hasMoreNextUp, !isLoadingMore else { return }
        let generation = loadGeneration
        isLoadingMore = true
        defer {
            if loadGeneration == generation {
                isLoadingMore = false
            }
        }
        let resumeStart = resumeOffset, nextStart = nextOffset
        let fetchResume = resumeHasMore, fetchNext = nextHasMore
        async let resume: Result<MediaItemPage, GusError>? = fetchResume ? resumeResult(startIndex: resumeStart, limit: nextUpPageSize) : nil
        async let next: Result<MediaItemPage, GusError>? = fetchNext ? nextUpResult(startIndex: nextStart, limit: nextUpPageSize) : nil
        let results = await(resume, next)
        guard !Task.isCancelled, session.references.isActive, generation == loadGeneration else { return }
        var errors: [GusError] = []
        if let result = results.0 {
            switch result {
            case let .success(page):
                resumeOffset = resumeStart + page.items.count
                resumeHasMore = Self.hasMore(page: page, offset: resumeOffset, requested: nextUpPageSize)
                resumeItems += ContentRatingGate.filter(page.items)
            case let .failure(error): errors.append(error)
            }
        }
        if let result = results.1 {
            switch result {
            case let .success(page):
                nextOffset = nextStart + page.items.count
                nextHasMore = Self.hasMore(page: page, offset: nextOffset, requested: nextUpPageSize)
                nextUpItems += ContentRatingGate.filter(page.items)
            case let .failure(error): errors.append(error)
            }
        }
        if let error = errors.first(where: { !$0.isCancellation }) {
            errorMessage = error.localizedDescription
        }
        if errors.contains(.unauthorized) {
            session.onUnauthorized()
        }
        rebuildNextUp()
        donateToSystemSearch()
    }

    /// Donates the rating-gated home content to Core Spotlight (no-op where the
    /// platform lacks it) so library items surface in system search, and refreshes the
    /// optional tvOS Top Shelf snapshot when the app is signed with an App Group.
    private func donateToSystemSearch() {
        let nextItems = unifiedNextUp.filter { $0.playlist == nil && $0.savedEntry?.availability != .unavailable && $0.savedEntry?.availability != .requiresSelection }.compactMap(\.item)
        let items = nextItems + latestSections.flatMap(\.items)
        SpotlightIndexer.index(items, serverID: session.server.id, userID: session.user.id)

        #if os(tvOS)
            let provider = session.mediaProvider
            let shelfItems = nextItems.prefix(8).compactMap { item -> TopShelfSnapshot.Item? in
                guard let id = item.id else { return nil }
                return TopShelfSnapshot.Item(
                    id: id,
                    title: item.displayTitle,
                    imageURL: provider.backdropImageURL(for: item, maxWidth: 1280),
                    playbackProgress: item.playbackProgress,
                    contentURL: ContentLink.item(id: id, serverID: session.server.id, provider: session.server.providerKind).url
                )
            }
            TopShelfSnapshot(items: Array(shelfItems), serverID: session.server.id, userID: session.user.id).save()
        #endif
    }

    /// Fetches "Recently Added" rails for the first few libraries in parallel,
    /// preserving the library order in the returned sections.
    private func loadLatestSections(for libraries: [MediaItem]) async throws -> [HomeLatestSection] {
        let candidates = Array(libraries.prefix(6))
        let provider = session.mediaProvider

        let cachedByID = Dictionary(latestSections.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let sectionsByIndex = await withTaskGroup(
            of: (Int, HomeLatestSection?, GusError?).self
        ) { group in
            for (index, library) in candidates.enumerated() {
                guard let parentID = library.id else { continue }
                group.addTask {
                    do {
                        let latestItems = try await provider.latestMedia(in: library, limit: 12)
                        let items = ContentRatingGate.filter(
                            LatestMediaDisplayMapper.displayItems(from: latestItems, libraryCollectionType: library.collectionType)
                        )
                        guard !items.isEmpty else { return (index, nil, nil) }
                        return (index, HomeLatestSection(
                            id: parentID,
                            title: String(
                                localized: "Recently Added \(library.name ?? "Library")",
                                comment: "Home latest media section title, e.g. Recently Added Movies"
                            ),
                            items: items
                        ), nil)
                    } catch { return (index, cachedByID[parentID], GusError(from: error)) }
                }
            }

            var collected: [(Int, HomeLatestSection)] = []
            for await(index, section, error) in group {
                if let error, !error.isCancellation {
                    errorMessage = error.localizedDescription
                }
                if let section {
                    collected.append((index, section))
                }
            }
            return collected
        }

        return sectionsByIndex.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
