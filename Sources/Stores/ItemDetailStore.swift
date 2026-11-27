import Foundation
import Observation
import OSLog

enum SeriesRequest {
    static func initialSeasonID(from seasons: [MediaItem], preferredEpisode: MediaItem? = nil) -> String? {
        if let episode = preferredEpisode {
            if let parentID = episode.parentID, seasons.contains(where: { $0.id == parentID }) {
                return parentID
            }
            if let number = episode.parentIndexNumber, let match = seasons.first(where: { $0.indexNumber == number }) {
                return match.id
            }
        }
        return seasons.first { ($0.indexNumber ?? 0) > 0 }?.id ?? seasons.first?.id
    }
}

/// The Watch series destination browses episodes across seasons in Jellyfin's order.
@MainActor @Observable
final class SeriesEpisodeListStore {
    private(set) var episodes: [MediaItem] = []
    private(set) var state: LoadState = .idle
    private var paging = Paging(pageSize: 30)
    private let admits: (MediaItem) -> Bool

    init(admits: @escaping (MediaItem) -> Bool = { ContentRatingGate.admitsStored($0) }) {
        self.admits = admits
    }

    var canLoadMore: Bool {
        paging.canLoadMore
    }

    func loadNext(seriesID: String, session: SessionStore) async {
        guard session.isActive, !state.isLoading, state != .loaded || canLoadMore else { return }
        state = .loading
        do {
            // Bound the work per tap when entire pages are restricted or duplicated.
            for _ in 0 ..< 3 {
                try Task.checkCancellation()
                let offset = paging.nextStartIndex
                let query = MediaItemQuery(parentID: seriesID, includeTypes: [.episode], startIndex: offset, limit: paging.pageSize, isRecursive: true)
                let page = try await session.mediaProvider.items(query: query)
                try Task.checkCancellation()
                guard session.isActive else { return }
                let total = try MediaPageLoader.validatedTotal(for: page, startIndex: offset, previousTotal: paging.totalRecordCount)
                let additions = MediaPageLoader.unique(page.items.filter(admits), after: episodes)
                episodes += additions
                paging.appendResults(receivedCount: page.items.count, totalRecordCount: total)
                if !additions.isEmpty || !canLoadMore {
                    break
                }
            }
            state = .loaded
        } catch {
            guard session.isActive else { return }
            let failure = GusError(from: error)
            if Task.isCancelled || failure.isCancellation {
                state = paging.nextStartIndex == 0 ? .idle : .loaded
            } else {
                failure.handleIfUnauthorized(session: session)
                state = .failed(failure.localizedDescription)
            }
        }
    }
}

@MainActor
@Observable
final class ItemDetailStore {
    private(set) var state: LoadState = .idle
    private(set) var hasLoadedContent = false
    private(set) var item: MediaItem
    private(set) var seriesStore: SeriesDetailStore?
    private(set) var similarItems: [MediaItem] = []
    private(set) var specialFeatures: [MediaItem] = []
    private(set) var relatedContentError: String?
    private(set) var isUpdatingUserData = false
    private(set) var needsUserDataRefresh = false
    var actionError: String?
    private(set) var actionOutcome: ActionOutcome?
    private var expectedWatched: Bool?
    private var expectedFavorite: Bool?
    private(set) var canKeepCurrentUserData = false

    private let session: SessionStore
    private let initialSeasonID: String?
    private let onSeasonSelected: ((String) -> Void)?
    private let logger = Logger(category: .item)
    private var loadGeneration = 0
    @ObservationIgnored private var foregroundTask: Task<Void, Never>?

    init(item: MediaItem, session: SessionStore, initialSeasonID: String? = nil, onSeasonSelected: ((String) -> Void)? = nil) {
        self.item = item
        self.session = session
        self.initialSeasonID = initialSeasonID
        self.onSeasonSelected = onSeasonSelected
        session.onInvalidation(of: self) { _ = $0.cancelForegroundLoads() }
    }

    func load() async {
        guard session.isActive, state != .loading else { return }
        foregroundTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        state = .loading
        let task = Task { [weak self] in
            guard let self else { return }
            await performLoad(generation: generation)
        }
        foregroundTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if generation == loadGeneration {
            foregroundTask = nil
        }
    }

    private func performLoad(generation: Int) async {
        do {
            if item.id != nil {
                let loaded = try await session.references.currentItem(item)
                try Task.checkCancellation()
                guard generation == loadGeneration, session.isActive else { return }
                item = loaded
            }

            state = .loaded
            hasLoadedContent = true
            await loadRelatedContent(for: item, generation: generation)
        } catch {
            guard generation == loadGeneration, session.isActive else { return }
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { state = .idle; return }
            logger.error("Item detail load failed: \(gusError.localizedDescription, privacy: .private)")
            state = .failed(gusError.localizedDescription)
        }
    }

    func acceptResolvedMetadata(_ current: MediaItem) {
        guard session.isActive, !isUpdatingUserData else { return }
        if item.id != current.id {
            foregroundTask?.cancel()
            loadGeneration += 1
            similarItems = []
            specialFeatures = []
            relatedContentError = nil
            seriesStore = nil
            state = .loaded
            hasLoadedContent = true
            item = current
            let generation = loadGeneration
            foregroundTask = Task { [weak self] in
                guard let self else { return }
                await loadRelatedContent(for: current, generation: generation)
                if generation == loadGeneration {
                    foregroundTask = nil
                }
            }
        } else if case .failed = state {
            state = .loaded
        }
        item = current
    }

    func toggleWatched() async {
        await updateUserData(watched: true, to: item.userData?.isWatched != true)
    }

    /// Explicit menu actions do not toggle against potentially stale displayed metadata.
    func setWatched(_ watched: Bool, localProgress: OfflinePlaybackProgressStore = .shared, bookProgress: BookProgressStore = .shared, nextUp: UpNextStore? = nil, activity: NextUpActivityStore = .shared) async {
        guard session.isActive, !isUpdatingUserData, item.id != nil else { return }
        if needsUserDataRefresh {
            await refreshUserData(); return
        }
        isUpdatingUserData = true
        actionError = nil
        actionOutcome = .pending
        canKeepCurrentUserData = false
        var attemptedWrite = false
        var acceptedWrite = false
        var acceptedProgressReset = false
        defer { isUpdatingUserData = false }
        do {
            let refreshed = try await session.references.currentItem(item)
            try Task.checkCancellation()
            guard session.isActive else { return }
            item = refreshed
            guard let id = item.id, ContentRatingGate.admitsStored(item) else { throw GusError.notFound }
            let scope = session.references.scope
            let serializesProgress = item.isBookFormat
            if serializesProgress, !(await localProgress.beginStatusUpdate(itemID: id, scope: scope)) {
                actionOutcome = nil
                return
            }
            defer {
                if serializesProgress {
                    localProgress.endStatusUpdate(itemID: id, scope: scope)
                }
            }
            try Task.checkCancellation()
            guard session.isActive else { return }
            expectedWatched = watched
            expectedFavorite = nil
            needsUserDataRefresh = true
            attemptedWrite = true
            try await session.mediaProvider.updatePlaybackPosition(itemID: id, positionTicks: 0)
            acceptedProgressReset = true
            try Task.checkCancellation()
            guard session.isActive else { return }
            localProgress.resetCheckpoint(itemID: id, scope: session.references.scope)
            if item.type == .book {
                bookProgress.clearLocator(forItemID: id, scope: session.references.scope)
            }
            // This provider API selects an endpoint; the inverse requests the desired status.
            try await session.mediaProvider.toggleWatched(itemID: id, currentlyWatched: !watched)
            acceptedWrite = true
            actionOutcome = .accepted
            try Task.checkCancellation()
            guard session.isActive else { return }
            if watched {
                if let nextUp {
                    try nextUp.dismissLocally(item, scope: session.references.scope, activity: activity)
                } else if let key = NextUpBuilder.mediaID(item), !activity.setDismissed(key, dismissed: true, scope: session.references.scope) {
                    throw GusError.server(activity.errorMessage ?? String(localized: "Your queue change couldn't be saved. Try again."))
                }
            }
            try await reconcileUserData()
        } catch {
            finishActionFailure(error, attempted: attemptedWrite, accepted: acceptedWrite, partiallyAccepted: acceptedProgressReset && !acceptedWrite)
        }
    }

    func toggleFavorite() async {
        await setFavorite(item.userData?.isFavorite != true)
    }

    func setFavorite(_ favorite: Bool) async {
        await updateUserData(watched: false, to: favorite)
    }

    /// A failed refresh after a successful mutation must be reconciled before toggling again.
    func refreshUserData() async {
        guard session.isActive, !isUpdatingUserData, item.id != nil else { return }
        isUpdatingUserData = true
        defer { isUpdatingUserData = false }
        do {
            try await reconcileUserData()
        } catch {
            guard session.isActive else { return }
            let failure = GusError(from: error)
            failure.handleIfUnauthorized(session: session)
            if !failure.isCancellation {
                actionError = failure.localizedDescription
            }
        }
    }

    private func updateUserData(watched: Bool, to value: Bool) async {
        guard session.isActive, !isUpdatingUserData, item.id != nil else { return }
        if needsUserDataRefresh {
            await refreshUserData(); return
        }
        isUpdatingUserData = true
        actionError = nil
        actionOutcome = .pending
        canKeepCurrentUserData = false
        var attemptedWrite = false
        var acceptedWrite = false
        defer { isUpdatingUserData = false }
        do {
            let refreshed = try await session.references.currentItem(item)
            try Task.checkCancellation()
            guard session.isActive else { return }
            item = refreshed
            guard let id = item.id, ContentRatingGate.admitsStored(item) else { throw GusError.notFound }
            expectedWatched = watched ? value : nil
            expectedFavorite = watched ? nil : value
            attemptedWrite = true
            needsUserDataRefresh = true
            if watched {
                try await session.mediaProvider.toggleWatched(itemID: id, currentlyWatched: !value)
            } else {
                try await session.mediaProvider.toggleFavorite(itemID: id, currentlyFavorite: !value)
            }
            acceptedWrite = true
            actionOutcome = .accepted
            try await reconcileUserData()
        } catch {
            finishActionFailure(error, attempted: attemptedWrite, accepted: acceptedWrite)
        }
    }

    private func reconcileUserData() async throws {
        let refreshed = try await session.references.currentItem(item)
        try Task.checkCancellation()
        guard session.isActive else { throw GusError.cancelled }
        item = refreshed
        let bookPositionConfirmed = !item.isBookFormat || expectedWatched == nil || (item.userData?.playbackPositionTicks ?? 0) == 0
        let matches = bookPositionConfirmed
            && (expectedWatched == nil || expectedWatched == item.userData?.isWatched)
            && (expectedFavorite == nil || expectedFavorite == item.userData?.isFavorite)
        guard matches else {
            needsUserDataRefresh = true
            canKeepCurrentUserData = true
            actionError = String(localized: "The server has not confirmed this change. Refresh Status before making another change.")
            return
        }
        needsUserDataRefresh = false
        canKeepCurrentUserData = false
        if expectedWatched != nil || expectedFavorite != nil {
            session.libraryIntelligence.invalidateTasteSignals()
        }
        expectedWatched = nil
        expectedFavorite = nil
        actionOutcome = .confirmed
        actionError = nil
    }

    private func finishActionFailure(_ error: Error, attempted: Bool, accepted: Bool, partiallyAccepted: Bool = false) {
        let failure = GusError(from: error)
        failure.handleIfUnauthorized(session: session)
        guard session.isActive else { actionOutcome = nil; return }
        if failure.isCancellation {
            actionOutcome = nil; return
        }
        if partiallyAccepted {
            actionOutcome = .uncertain
            actionError = String(localized: "Progress was reset, but the completion status was not confirmed. Refresh Status before making another change.")
        } else if accepted {
            actionOutcome = .accepted
            actionError = String(localized: "Saved; refresh unavailable. Pull to refresh before making another change.")
        } else if attempted, Self.isUncertainWrite(failure) {
            actionOutcome = .uncertain
            actionError = String(localized: "The change may have been saved. Refresh Status before trying again.")
        } else {
            actionOutcome = .failed(failure)
            expectedWatched = nil
            expectedFavorite = nil
            needsUserDataRefresh = false
            actionError = failure.localizedDescription
        }
    }

    /// An explicit acknowledgement of freshly read server state clears uncertainty;
    /// it never resubmits the previous write or toggles a possibly stale value.
    func keepCurrentUserData() {
        guard canKeepCurrentUserData, !isUpdatingUserData else { return }
        expectedWatched = nil
        expectedFavorite = nil
        needsUserDataRefresh = false
        canKeepCurrentUserData = false
        actionOutcome = nil
        actionError = nil
    }

    private static func isUncertainWrite(_ failure: GusError) -> Bool {
        switch failure {
        case .timeout, .offline, .network: true
        default: false
        }
    }

    func retryRelatedContent() async {
        guard session.isActive else { return }
        foregroundTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await loadRelatedContent(for: item, generation: generation)
        }
        foregroundTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if generation == loadGeneration {
            foregroundTask = nil
        }
    }

    /// Leaving the last visible destination cancels its work without discarding content.
    @discardableResult
    func cancelForegroundLoads() -> Bool {
        let canceled = foregroundTask != nil || state.isLoading
        loadGeneration += 1
        foregroundTask?.cancel()
        foregroundTask = nil
        let canceledSeries = seriesStore?.cancelForegroundLoads() == true
        if state.isLoading {
            state = hasLoadedContent ? .loaded : .idle
        }
        return canceled || canceledSeries
    }

    private func loadRelatedContent(for item: MediaItem, generation: Int) async {
        async let similar = loadSimilarItems(for: item)
        async let special = loadSpecialFeatures(for: item)

        let (loadedSimilar, loadedSpecial) = await(similar, special)
        guard generation == loadGeneration, !Task.isCancelled, session.references.isActive else { return }
        var failures: [String] = []
        switch loadedSimilar {
        case let .success(items): similarItems = ContentRatingGate.filter(items)
        case let .failure(error): if !error.isCancellation {
                failures.append(error.localizedDescription)
            }
        }
        switch loadedSpecial {
        case let .success(items): specialFeatures = ContentRatingGate.filter(items)
        case let .failure(error): if !error.isCancellation {
                failures.append(error.localizedDescription)
            }
        }
        relatedContentError = failures.first
        if item.type == .series {
            let store = seriesStore ?? SeriesDetailStore(series: item, session: session, initialSeasonID: initialSeasonID, onSeasonSelected: onSeasonSelected)
            seriesStore = store
            await store.loadSeasons()
        }
    }

    private func loadSimilarItems(for item: MediaItem) async -> Result<[MediaItem], GusError> {
        guard let itemID = item.id else { return .success([]) }
        do {
            return try await .success(session.mediaProvider.similarItems(itemID: itemID, limit: 12))
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return .failure(gusError) }
            logger.debug("Similar items load failed: \(gusError.localizedDescription, privacy: .private)")
            return .failure(gusError)
        }
    }

    private func loadSpecialFeatures(for item: MediaItem) async -> Result<[MediaItem], GusError> {
        guard !item.isBookFormat, let itemID = item.id else { return .success([]) }
        do {
            return try await .success(session.mediaProvider.specialFeatures(itemID: itemID))
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return .failure(gusError) }
            logger.debug("Special features load failed: \(gusError.localizedDescription, privacy: .private)")
            return .failure(gusError)
        }
    }
}

@MainActor
@Observable
final class SeriesDetailStore {
    private(set) var seasonsState: LoadState = .idle
    private(set) var episodesState: LoadState = .idle
    private(set) var seasons: [MediaItem] = []
    private(set) var episodes: [MediaItem] = []
    private(set) var selectedSeasonID: String?

    let series: MediaItem

    private let session: SessionStore
    private let logger = Logger(category: .item)
    private var seasonGeneration = 0
    private var episodeGeneration = 0
    private var seasonTask: Task<[MediaItem], Error>?
    private var episodeTask: Task<[MediaItem], Error>?
    private var loadedSeasonID: String?
    private var preferredEpisode: MediaItem?
    private var hasUserSelectedSeason = false
    private var didApplyPreferredEpisode = false
    private(set) var preferredEpisodeID: String?

    private let onSeasonSelected: ((String) -> Void)?

    init(series: MediaItem, session: SessionStore, initialSeasonID: String? = nil, onSeasonSelected: ((String) -> Void)? = nil) {
        self.series = series
        self.session = session
        selectedSeasonID = initialSeasonID
        hasUserSelectedSeason = initialSeasonID != nil
        self.onSeasonSelected = onSeasonSelected
        session.onInvalidation(of: self) { _ = $0.cancelForegroundLoads() }
    }

    func loadSeasons() async {
        guard session.isActive, seasonsState != .loading, let seriesID = series.id else { return }
        seasonGeneration += 1
        let generation = seasonGeneration
        seasonsState = .loading

        do {
            let provider = session.mediaProvider
            let task = Task { try await provider.seasons(seriesID: seriesID) }
            seasonTask = task
            defer {
                if generation == seasonGeneration {
                    seasonTask = nil
                }
            }
            let loaded = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard generation == seasonGeneration, session.isActive else { return }
            seasons = loaded
            if !seasons.contains(where: { $0.id == selectedSeasonID }) {
                hasUserSelectedSeason = false
                selectedSeasonID = SeriesRequest.initialSeasonID(from: seasons, preferredEpisode: preferredEpisode)
            }
            seasonsState = .loaded

            if let selectedSeasonID {
                await loadEpisodes(seasonID: selectedSeasonID)
            }
        } catch {
            guard generation == seasonGeneration, session.isActive else { return }
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { seasonsState = .idle; return }
            logger.error("Series seasons load failed: \(gusError.localizedDescription, privacy: .private)")
            seasonsState = .failed(gusError.localizedDescription)
        }
    }

    /// Initial resume alignment never overrides a deliberate season selection.
    func preferInitialEpisode(_ episode: MediaItem?) async {
        guard !hasUserSelectedSeason, !didApplyPreferredEpisode,
              let episode, episode.type == .episode, episode.seriesID == series.id else { return }
        preferredEpisode = episode
        preferredEpisodeID = episode.id
        guard !seasons.isEmpty, let seasonID = SeriesRequest.initialSeasonID(from: seasons, preferredEpisode: episode) else { return }
        didApplyPreferredEpisode = true
        if selectedSeasonID != seasonID {
            selectedSeasonID = seasonID
            await loadEpisodes(seasonID: seasonID)
        }
    }

    func selectSeason(id: String) async {
        guard seasons.contains(where: { $0.id == id }) else { return }
        hasUserSelectedSeason = true
        onSeasonSelected?(id)
        guard selectedSeasonID != id || episodesState != .loaded else { return }
        selectedSeasonID = id
        await loadEpisodes(seasonID: id)
    }

    func retryEpisodes() async {
        guard let selectedSeasonID else { return }
        await loadEpisodes(seasonID: selectedSeasonID)
    }

    @discardableResult
    func cancelForegroundLoads() -> Bool {
        let canceled = seasonTask != nil || episodeTask != nil
        seasonGeneration += 1
        episodeGeneration += 1
        seasonTask?.cancel()
        seasonTask = nil
        episodeTask?.cancel()
        episodeTask = nil
        if seasonsState.isLoading {
            seasonsState = seasons.isEmpty ? .idle : .loaded
        }
        if episodesState.isLoading {
            episodesState = episodes.isEmpty ? .idle : .loaded
        }
        return canceled
    }

    private func loadEpisodes(seasonID: String) async {
        guard session.isActive, let seriesID = series.id else { return }
        episodeGeneration += 1
        let generation = episodeGeneration
        episodeTask?.cancel()
        episodesState = .loading
        if loadedSeasonID != seasonID {
            episodes = []
        }

        do {
            let provider = session.mediaProvider
            let task = Task {
                try await MediaPageLoader.collect { offset, size in
                    try await provider.episodesPage(seriesID: seriesID, seasonID: seasonID, startIndex: offset, limit: size)
                }
            }
            episodeTask = task
            defer {
                if generation == episodeGeneration {
                    episodeTask = nil
                }
            }
            let page = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard generation == episodeGeneration, selectedSeasonID == seasonID, session.isActive else { return }
            episodes = ContentRatingGate.filter(page)
            loadedSeasonID = seasonID
            episodesState = .loaded
        } catch {
            guard generation == episodeGeneration, selectedSeasonID == seasonID, session.isActive else { return }
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { episodesState = episodes.isEmpty ? .idle : .loaded; return }
            logger.error("Series episodes load failed: \(gusError.localizedDescription, privacy: .private)")
            episodesState = .failed(gusError.localizedDescription)
        }
    }
}
