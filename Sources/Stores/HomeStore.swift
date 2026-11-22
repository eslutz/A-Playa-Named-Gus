import Foundation
import Observation
#if os(tvOS)
    import TVServices
#endif

struct HomeLatestSection: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [MediaItem]
    let kind: LatestMediaKind
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
    var forYou: ForYouShelfState {
        session.forYouShelf
    }

    private let activity: NextUpActivityStore
    private var resumeOffset = 0
    private var nextOffset = 0
    private var resumeTotal: Int?
    private var nextTotal: Int?
    private var resumeHasMore = false
    private var nextHasMore = false
    private var loadGeneration = UUID()
    private var sharedWithYouGeneration = UUID()
    private(set) var isLoadingMore = false
    var hasMoreNextUp: Bool {
        resumeHasMore || nextHasMore
    }

    private let nextUpPageSize = 50
    private typealias FeedFailure = (title: String, cause: GusError)
    private(set) var libraryState: LoadState = .idle
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

    init(session: SessionStore, activity: NextUpActivityStore = .shared) {
        self.session = session
        self.activity = activity
        session.onInvalidation(of: self) { store in
            for task in store.flights.values {
                task.cancel()
            }
            store.flights.removeAll()
            store.loadGeneration = UUID()
        }
    }

    private enum Feed: Hashable, Sendable {
        case resume, next, libraries, latest(LatestMediaKind)
        static let automatic: [Self] = [.resume, .next]
        static var home: [Self] {
            automatic + LatestMediaKind.allCases.map(latest)
        }

        var isAutomatic: Bool {
            self == .resume || self == .next
        }

        var cacheKey: String {
            switch self {
            case .resume: "resume"
            case .next: "next"
            case .libraries: "libraries"
            case let .latest(kind): "latest:" + kind.rawValue
            }
        }

        var title: String {
            switch self {
            case .resume: String(localized: "Continue Watching")
            case .next: String(localized: "Next Up")
            case .libraries: String(localized: "Libraries")
            case let .latest(kind): kind.title
            }
        }
    }

    func restoreSnapshots() {
        guard session.isActive else { return }
        for key in Feed.home + [.libraries] {
            hydrate(key)
        }
    }

    private struct AutomaticPage: Codable {
        let items: [MediaItem]
        let offset: Int
        let total: Int?
        let hasMore: Bool
    }

    private var timestamps: [Feed: Date] = [:]
    private var completed = Set<Feed>()
    private var flights: [Feed: Task<GusError?, Never>] = [:]
    private var feedErrors: [Feed: GusError] = [:]
    private var restriction = BrowseSnapshotCache.restriction
    private var lastPlaybackRevision = 0

    var matchesRestriction: Bool {
        restriction == BrowseSnapshotCache.restriction
    }

    var nextUpPending: Bool {
        !completed.contains(.resume) || !completed.contains(.next)
    }

    func isPending(_ kind: LatestMediaKind) -> Bool {
        !completed.contains(.latest(kind))
    }

    func load() async {
        await loadHome(force: true)
    }

    func refresh() async {
        await loadHome(force: true)
    }

    func loadIfNeeded() async {
        await loadHome(force: false)
    }

    func refreshAfterPlayback(revision: Int) async {
        guard revision > lastPlaybackRevision else { return }
        lastPlaybackRevision = revision
        // A read started before playback completed can carry the old position.
        for key in Feed.automatic {
            _ = await flights[key]?.value
        }
        await loadHome(force: true, automaticOnly: true)
    }

    private func prepareScope() {
        let current = BrowseSnapshotCache.restriction
        guard current != restriction else { return }
        restriction = current
        loadGeneration = UUID()
        for task in flights.values {
            task.cancel()
        }
        flights.removeAll()
        timestamps.removeAll()
        completed.removeAll()
        errorMessage = nil
        feedErrors.removeAll()
        for key in [Feed.resume, .next, .libraries] {
            clear(key)
        }
        latestSections = []
        sharedWithYouItems = ContentRatingGate.filter(sharedWithYouItems)
        savedIntents.removeAll { !ContentRatingGate.admitsStored($0.reference.item) }
        playlistCandidates = []
        rebuildNextUp()
    }

    private func clear(_ key: Feed) {
        switch key {
        case .resume:
            resumeItems = []
            resumeOffset = 0
            resumeTotal = nil
            resumeHasMore = false
        case .next:
            nextUpItems = []
            nextOffset = 0
            nextTotal = nil
            nextHasMore = false
        case .libraries: libraries = []
        case let .latest(kind): latestSections.removeAll { $0.kind == kind }
        }
        completed.remove(key)
        timestamps[key] = nil
    }

    private func setLatest(_ kind: LatestMediaKind, items: [MediaItem]) {
        let id = "latest:" + kind.rawValue
        var sections = latestSections.filter { $0.kind != kind }
        if !items.isEmpty {
            sections.append(.init(id: id, title: kind.title, items: items, kind: kind))
        }
        latestSections = LatestMediaKind.allCases.compactMap { kind in sections.first { $0.kind == kind } }
    }

    private func applyAutomatic(_ page: AutomaticPage, key: Feed, recordActivity: Bool = true) {
        if key == .resume {
            resumeItems = ContentRatingGate.filter(page.items)
            resumeOffset = page.offset
            resumeTotal = page.total
            resumeHasMore = page.hasMore
        } else {
            nextUpItems = ContentRatingGate.filter(page.items)
            nextOffset = page.offset
            nextTotal = page.total
            nextHasMore = page.hasMore
        }
        rebuildNextUp(recordActivity: recordActivity)
    }

    private func hydrate(_ key: Feed) {
        let cache = session.browseCache
        if let date = timestamps[key] {
            if (0 ..< BrowseSnapshotCache.lifetime).contains(cache.now().timeIntervalSince(date)) {
                return
            }
            clear(key)
            if key.isAutomatic {
                rebuildNextUp()
            }
        }
        if key.isAutomatic {
            guard let entry = cache.read(key.cacheKey, as: AutomaticPage.self) else { return }
            applyAutomatic(entry.value, key: key, recordActivity: false)
            timestamps[key] = entry.savedAt
        } else {
            guard let entry = cache.read(key.cacheKey, as: [MediaItem].self) else { return }
            if key == .libraries {
                libraries = entry.value
                libraryState = .loaded
            } else if case let .latest(kind) = key {
                setLatest(kind, items: ContentRatingGate.filter(entry.value))
            }
            timestamps[key] = entry.savedAt
        }
        completed.insert(key)
    }

    private func needsRefresh(_ key: Feed, force: Bool) -> Bool {
        if !force || timestamps[key] != nil {
            hydrate(key)
        }
        if feedErrors[key] != nil {
            return true
        }
        let interval: TimeInterval = key.isAutomatic ? 60 : 300
        return force || timestamps[key].map { session.browseCache.now().timeIntervalSince($0) >= interval } != false
    }

    private func loadHome(force: Bool, automaticOnly: Bool = false) async {
        guard session.isActive, !Task.isCancelled else { return }
        prepareScope()
        let partition = restriction
        let requested = automaticOnly ? Feed.automatic : Feed.home
        let feeds = requested.filter { needsRefresh($0, force: force) }
        if state == .idle {
            state = .loading
        }
        async let views: Void = automaticOnly ? () : loadLibraries(force: force)
        if feeds.contains(where: { $0.isAutomatic && flights[$0] == nil }) {
            loadGeneration = UUID()
            isLoadingMore = false
        }
        await withTaskGroup(of: Void.self) { group in
            for key in feeds {
                group.addTask { _ = await self.refreshFeed(key) }
            }
        }
        await views
        guard session.isActive, partition == restriction else { return }
        if !feeds.isEmpty || state == .loading {
            let failure: FeedFailure? = Feed.home.lazy.compactMap { key in self.feedErrors[key].map { (key.title, $0) } }.first
            errorMessage = failure.map { failure in
                String(localized: "Couldn’t refresh \(failure.title). \(failure.cause.localizedDescription)")
            }
            state = errorMessage.map { .failed($0) } ?? .loaded
        }
        donateToSystemSearch()
    }

    private func refreshFeed(_ key: Feed) async -> GusError? {
        if let flight = flights[key] {
            return await flight.value
        }
        let partition = restriction
        if timestamps[key] == nil {
            completed.remove(key)
        }
        let task = Task { @MainActor () -> GusError? in
            defer {
                if !Task.isCancelled {
                    self.flights[key] = nil
                }
            }
            do {
                try await self.fetch(key, partition: partition)
                self.feedErrors[key] = nil
                self.timestamps[key] = self.session.browseCache.now()
                self.completed.insert(key)
                return nil
            } catch {
                let failure = GusError(from: error)
                guard !failure.isCancellation, self.session.isActive, partition == self.restriction else { return .cancelled }
                if failure.invalidatesBrowseSnapshot {
                    self.session.browseCache.remove(key.cacheKey)
                    self.clear(key)
                    self.rebuildNextUp()
                }
                self.feedErrors[key] = failure
                self.completed.insert(key)
                failure.handleIfUnauthorized(session: self.session)
                return failure
            }
        }
        flights[key] = task
        return await task.value
    }

    private func fetch(_ key: Feed, partition: String) async throws {
        func validate() throws {
            try Task.checkCancellation()
            guard session.isActive, partition == BrowseSnapshotCache.restriction else { throw CancellationError() }
        }
        try validate()
        let cache = session.browseCache
        if key == .libraries {
            let items = try await session.mediaProvider.userViews()
            try validate()
            libraries = items
            cache.write(items.map(\.browseSnapshotItem), key: key.cacheKey)
        } else if key.isAutomatic {
            let limit = max(key == .resume ? resumeOffset : nextOffset, nextUpPageSize)
            let result = key == .resume ? await resumeResult(startIndex: 0, limit: limit) : await nextUpResult(startIndex: 0, limit: limit)
            let page = try result.get()
            try validate()
            let count = min(nextUpPageSize, page.items.count)
            let more = Self.hasMore(page: page, offset: page.items.count, requested: limit)
            cache.write(AutomaticPage(items: ContentRatingGate.filter(Array(page.items.prefix(count))).map(\.browseSnapshotItem), offset: count, total: page.totalRecordCount, hasMore: page.items.count > count || more), key: key.cacheKey)
            applyAutomatic(.init(items: page.items, offset: page.items.count, total: page.totalRecordCount, hasMore: more), key: key)
        } else if case let .latest(kind) = key {
            var items: [MediaItem] = []
            var offset = 0
            while items.count < 12, offset < 180 {
                let page = try await session.mediaProvider.latestMedia(kind: kind, startIndex: offset, limit: 60)
                try validate()
                items = kind.displayItems(items + ContentRatingGate.filter(page.items))
                offset += page.items.count
                if page.items.count < 60 || page.totalRecordCount.map({ offset >= $0 }) == true {
                    break
                }
            }
            let shelf = Array(items.prefix(12))
            setLatest(kind, items: shelf)
            cache.write(shelf.map(\.browseSnapshotItem), key: key.cacheKey)
        }
    }

    func loadLibraries(force: Bool = true) async {
        guard session.isActive, !Task.isCancelled else { return }
        prepareScope()
        guard needsRefresh(.libraries, force: force) else { return }
        if libraries.isEmpty, timestamps[.libraries] == nil {
            libraryState = .loading
        }
        let failure = await refreshFeed(.libraries)
        if failure == .cancelled {
            return
        }
        libraryState = failure.map { .failed($0.localizedDescription) } ?? .loaded
    }

    func loadSharedWithYou(links: [ContentLink], title: String) async {
        guard session.isActive, !Task.isCancelled else { return }
        let generation = UUID()
        sharedWithYouGeneration = generation
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

        guard !Task.isCancelled, session.isActive, session.references.isActive, generation == sharedWithYouGeneration else { return }
        sharedWithYouItems = ContentRatingGate.filter(
            indexedItems.sorted { $0.0 < $1.0 }.map(\.1)
        )
    }

    func refreshNextUp(upNext: UpNextStore, playlists: SavedMediaStore, serverLists: ServerMediaListsStore) {
        guard !Task.isCancelled else { return }
        let scope = session.references.scope
        upNext.load(serverID: scope.serverID, userID: scope.userID)
        upNext.reconcileSyncedIntents(scope: scope)
        activity.reconcile(scope: scope)
        serverLists.load(scope: scope)
        let candidates = serverLists.videoPlaylists(scope: scope, supplemental: playlists).compactMap { playlist -> NextUpPlaylistCandidate? in
            guard playlist.appearsInNextUp else { return nil }
            let index = playlist.entries.firstIndex { $0.id == playlist.cursor?.entryID } ?? 0
            let item = playlist.entries.indices.contains(index) ? playlist.entries[index].reference.item : nil
            guard item.map({ ContentRatingGate.admitsStored($0) }) ?? true else { return nil }
            return NextUpPlaylistCandidate(id: playlist.id, name: playlist.name, item: item, position: playlist.entries.isEmpty ? 0 : index + 1, total: playlist.entries.count, activityAt: playlist.activityAt, members: playlist.entries.map(\.reference.item))
        }
        updateNextUp(saved: upNext.entries(serverID: scope.serverID, userID: scope.userID), playlists: candidates)
    }

    func updateNextUp(saved: [UpNextEntry], playlists: [NextUpPlaylistCandidate]) {
        savedIntents = saved.filter { $0.reference.scope == session.references.scope && ContentRatingGate.admitsStored($0.reference.item) }
        playlistCandidates = playlists
        rebuildNextUp()
        donateToSystemSearch()
    }

    private func rebuildNextUp(recordActivity: Bool = true) {
        let scope = session.references.scope
        if recordActivity {
            activity.reconcileResume(resumeItems + nextUpItems, scope: scope)
        }
        unifiedNextUp = NextUpBuilder.build(
            resume: resumeItems, nextEpisodes: nextUpItems, saved: savedIntents,
            playlists: playlistCandidates.filter { !activity.isDismissed("playlist:" + $0.id.uuidString, scope: scope) }, activity: activity.snapshot(scope: scope),
            firstSeenIDs: activity.firstSeenIDs(scope: scope)
        ).filter {
            !activity.isDismissed($0.id, scope: scope) && ($0.playlist != nil || $0.item.map { !activity.isDismissed($0, scope: scope) } != false)
        }
        if recordActivity {
            activity.remember(unifiedNextUp.map(\.id), scope: scope)
        }
    }

    private func resumeResult(startIndex: Int, limit: Int, previousTotal: Int? = nil) async -> Result<MediaItemPage, GusError> {
        do {
            var page = try await session.mediaProvider.resumeItemsPage(startIndex: startIndex, limit: limit)
            page.totalRecordCount = try MediaPageLoader.validatedTotal(for: page, startIndex: startIndex, previousTotal: previousTotal)
            return .success(page)
        } catch { return .failure(GusError(from: error)) }
    }

    private func nextUpResult(startIndex: Int, limit: Int, previousTotal: Int? = nil) async -> Result<MediaItemPage, GusError> {
        do {
            var page = try await session.mediaProvider.nextUpItemsPage(startIndex: startIndex, limit: limit)
            page.totalRecordCount = try MediaPageLoader.validatedTotal(for: page, startIndex: startIndex, previousTotal: previousTotal)
            return .success(page)
        } catch { return .failure(GusError(from: error)) }
    }

    private static func hasMore(page: MediaItemPage, offset: Int, requested: Int) -> Bool {
        guard !page.items.isEmpty else { return false }
        return page.totalRecordCount.map { offset < $0 } ?? (page.items.count == requested)
    }

    /// Fetches both automatic sources incrementally. Offsets count raw provider
    /// records, including rating-gated and deduplicated records, avoiding skipped
    /// pages when fewer cards are visible than records returned.
    func loadMoreNextUp() async {
        guard hasMoreNextUp, !isLoadingMore, flights[.resume] == nil, flights[.next] == nil else { return }
        let generation = loadGeneration
        isLoadingMore = true
        defer {
            if loadGeneration == generation {
                isLoadingMore = false
            }
        }
        let resumeStart = resumeOffset, nextStart = nextOffset
        let fetchResume = resumeHasMore, fetchNext = nextHasMore
        async let resume: Result<MediaItemPage, GusError>? = fetchResume ? resumeResult(startIndex: resumeStart, limit: nextUpPageSize, previousTotal: resumeTotal) : nil
        async let next: Result<MediaItemPage, GusError>? = fetchNext ? nextUpResult(startIndex: nextStart, limit: nextUpPageSize, previousTotal: nextTotal) : nil
        let results = await(resume, next)
        guard !Task.isCancelled, session.references.isActive, generation == loadGeneration, restriction == BrowseSnapshotCache.restriction else { return }
        var errors: [GusError] = []
        if let result = results.0 {
            switch result {
            case let .success(page):
                resumeOffset = resumeStart + page.items.count
                resumeTotal = page.totalRecordCount
                resumeHasMore = Self.hasMore(page: page, offset: resumeOffset, requested: nextUpPageSize)
                resumeItems += MediaPageLoader.unique(ContentRatingGate.filter(page.items), after: resumeItems)
            case let .failure(error):
                if error.invalidatesBrowseSnapshot {
                    session.browseCache.remove("resume"); clear(.resume); completed.insert(.resume)
                }
                errors.append(error)
            }
        }
        if let result = results.1 {
            switch result {
            case let .success(page):
                nextOffset = nextStart + page.items.count
                nextTotal = page.totalRecordCount
                nextHasMore = Self.hasMore(page: page, offset: nextOffset, requested: nextUpPageSize)
                nextUpItems += MediaPageLoader.unique(ContentRatingGate.filter(page.items), after: nextUpItems)
            case let .failure(error):
                if error.invalidatesBrowseSnapshot {
                    session.browseCache.remove("next"); clear(.next); completed.insert(.next)
                }
                errors.append(error)
            }
        }
        errorMessage = errors.first(where: { !$0.isCancellation })?.localizedDescription
        if errors.contains(.unauthorized) {
            session.handleUnauthorized()
        }
        rebuildNextUp()
        donateToSystemSearch()
    }

    private var systemNextItems: [MediaItem] {
        unifiedNextUp.filter { $0.playlist == nil && $0.savedEntry?.availability != .unavailable && $0.savedEntry?.availability != .requiresSelection }.compactMap(\.item)
    }

    /// Donates the rating-gated home content to Core Spotlight (no-op where the
    /// platform lacks it) so library items surface in system search, and refreshes the
    /// optional tvOS Top Shelf snapshot when the app is signed with an App Group.
    private func donateToSystemSearch() {
        let items = systemNextItems + latestSections.flatMap(\.items)
        SpotlightIndexer.index(items, serverID: session.server.id, userID: session.user.id)

        #if os(tvOS)
            refreshTopShelf()
        #endif
    }

    #if os(tvOS)
        func refreshTopShelf() {
            let provider = session.mediaProvider
            let showSeriesProgress = UserDefaults.standard.bool(forKey: MediaItem.seriesProgressKey)
            let shelfItems = systemNextItems.prefix(8).compactMap { item -> TopShelfSnapshot.Item? in
                guard let id = item.id else { return nil }
                return TopShelfSnapshot.Item(
                    id: id,
                    title: item.displayTitle,
                    imageURL: provider.backdropImageURL(for: item, maxWidth: 1280),
                    playbackProgress: item.cardProgress(showSeriesProgress: showSeriesProgress),
                    contentURL: ContentLink.item(id: id, serverID: session.server.id, provider: session.server.providerKind).url
                )
            }
            TopShelfSnapshot(items: Array(shelfItems), serverID: session.server.id, userID: session.user.id).save()
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
    #endif
}
