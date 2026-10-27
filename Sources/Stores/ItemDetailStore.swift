import Foundation
import Observation
import OSLog

enum SeriesRequest {
    static func initialSeasonID(from seasons: [MediaItem]) -> String? {
        seasons.first { ($0.indexNumber ?? 0) > 0 }?.id ?? seasons.first?.id
    }
}

@MainActor
@Observable
final class ItemDetailStore {
    private(set) var state: LoadState = .idle
    private(set) var item: MediaItem
    private(set) var seriesStore: SeriesDetailStore?
    private(set) var similarItems: [MediaItem] = []
    private(set) var specialFeatures: [MediaItem] = []
    private(set) var isUpdatingUserData = false
    private(set) var needsUserDataRefresh = false
    var actionError: String?

    private let session: SessionStore
    private let logger = Logger(category: .item)
    private var loadGeneration = 0
    @ObservationIgnored private var relatedContentTask: Task<Void, Never>?

    init(item: MediaItem, session: SessionStore) {
        self.item = item
        self.session = session
    }

    func load() async {
        guard state != .loading else { return }
        relatedContentTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        state = .loading

        do {
            if item.id != nil {
                let loaded = try await session.references.currentItem(item)
                try Task.checkCancellation()
                guard generation == loadGeneration else { return }
                item = loaded
            }

            state = .loaded
            await loadRelatedContent(for: item, generation: generation)
        } catch {
            guard generation == loadGeneration else { return }
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { state = .idle; return }
            logger.error("Item detail load failed: \(gusError.localizedDescription, privacy: .private)")
            state = .failed(gusError.localizedDescription)
        }
    }

    func acceptResolvedMetadata(_ current: MediaItem) {
        guard !isUpdatingUserData else { return }
        if item.id != current.id {
            relatedContentTask?.cancel()
            loadGeneration += 1
            similarItems = []
            specialFeatures = []
            seriesStore = nil
            state = .loaded
            item = current
            let generation = loadGeneration
            relatedContentTask = Task { [weak self] in
                await self?.loadRelatedContent(for: current, generation: generation)
            }
        } else if case .failed = state {
            state = .loaded
        }
        item = current
    }

    func toggleWatched() async {
        await updateUserData(watched: true)
    }

    /// Explicit menu actions do not toggle against potentially stale displayed metadata.
    func setWatched(_ watched: Bool, localProgress: OfflinePlaybackProgressStore = .shared, nextUp: UpNextStore? = nil, activity: NextUpActivityStore = .shared) async {
        guard !isUpdatingUserData, item.id != nil else { return }
        isUpdatingUserData = true
        actionError = nil
        defer { isUpdatingUserData = false }
        do {
            item = try await session.references.currentItem(item)
            guard let id = item.id, ContentRatingGate.admitsStored(item) else { throw GusError.notFound }
            needsUserDataRefresh = true
            try await session.mediaProvider.updatePlaybackPosition(itemID: id, positionTicks: 0)
            localProgress.resetCheckpoint(itemID: id, scope: session.references.scope)
            // This provider API selects an endpoint; the inverse requests the desired status.
            try await session.mediaProvider.toggleWatched(itemID: id, currentlyWatched: !watched)
            if watched {
                if let nextUp {
                    try nextUp.dismissLocally(item, scope: session.references.scope, activity: activity)
                } else if let key = NextUpBuilder.mediaID(item), !activity.setDismissed(key, dismissed: true, scope: session.references.scope) {
                    throw GusError.server(activity.errorMessage ?? String(localized: "Your queue change couldn't be saved. Try again."))
                }
            }
            item = try await session.references.currentItem(item)
            needsUserDataRefresh = false
        } catch {
            let failure = GusError(from: error)
            if !failure.isCancellation {
                actionError = failure.localizedDescription
            }
        }
    }

    func toggleFavorite() async {
        await updateUserData(watched: false)
    }

    /// A failed refresh after a successful mutation must be reconciled before toggling again.
    func refreshUserData() async {
        guard !isUpdatingUserData, item.id != nil else { return }
        isUpdatingUserData = true
        defer { isUpdatingUserData = false }
        do {
            item = try await session.references.currentItem(item)
            needsUserDataRefresh = false
            actionError = nil
        } catch {
            let failure = GusError(from: error)
            if !failure.isCancellation {
                actionError = failure.localizedDescription
            }
        }
    }

    private func updateUserData(watched: Bool) async {
        guard !isUpdatingUserData, item.id != nil else { return }
        if needsUserDataRefresh {
            await refreshUserData(); return
        }
        isUpdatingUserData = true
        actionError = nil
        defer { isUpdatingUserData = false }
        do {
            item = try await session.references.currentItem(item)
            guard let id = item.id else { throw GusError.notFound }
            if watched {
                try await session.mediaProvider.toggleWatched(itemID: id, currentlyWatched: item.userData?.isWatched == true)
            } else {
                try await session.mediaProvider.toggleFavorite(itemID: id, currentlyFavorite: item.userData?.isFavorite == true)
            }
            needsUserDataRefresh = true
            item = try await session.references.currentItem(item)
            needsUserDataRefresh = false
        } catch {
            let failure = GusError(from: error)
            if !failure.isCancellation {
                actionError = failure.localizedDescription
            }
        }
    }

    private func loadRelatedContent(for item: MediaItem, generation: Int) async {
        async let similar = loadSimilarItems(for: item)
        async let special = loadSpecialFeatures(for: item)

        let (loadedSimilar, loadedSpecial) = await(similar, special)
        guard generation == loadGeneration, !Task.isCancelled, session.references.isActive else { return }
        similarItems = ContentRatingGate.filter(loadedSimilar)
        specialFeatures = ContentRatingGate.filter(loadedSpecial)
        if item.type == .series {
            let store = SeriesDetailStore(series: item, session: session)
            seriesStore = store
            await store.loadSeasons()
        }
    }

    private func loadSimilarItems(for item: MediaItem) async -> [MediaItem] {
        guard let itemID = item.id else { return [] }
        do {
            return try await session.mediaProvider.similarItems(itemID: itemID, limit: 12)
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return [] }
            logger.debug("Similar items load failed: \(gusError.localizedDescription, privacy: .private)")
            return []
        }
    }

    private func loadSpecialFeatures(for item: MediaItem) async -> [MediaItem] {
        guard let itemID = item.id else { return [] }
        do {
            return try await session.mediaProvider.specialFeatures(itemID: itemID)
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return [] }
            logger.debug("Special features load failed: \(gusError.localizedDescription, privacy: .private)")
            return []
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
    private var episodeTask: Task<MediaItemPage, Error>?

    init(series: MediaItem, session: SessionStore) {
        self.series = series
        self.session = session
    }

    func loadSeasons() async {
        guard seasonsState != .loading, let seriesID = series.id else { return }
        seasonGeneration += 1
        let generation = seasonGeneration
        seasonsState = .loading

        do {
            let loaded = try await session.mediaProvider.seasons(seriesID: seriesID)
            try Task.checkCancellation()
            guard generation == seasonGeneration else { return }
            seasons = loaded
            if !seasons.contains(where: { $0.id == selectedSeasonID }) {
                selectedSeasonID = SeriesRequest.initialSeasonID(from: seasons)
            }
            seasonsState = .loaded

            if let selectedSeasonID {
                await loadEpisodes(seasonID: selectedSeasonID)
            }
        } catch {
            guard generation == seasonGeneration else { return }
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { seasonsState = .idle; return }
            logger.error("Series seasons load failed: \(gusError.localizedDescription, privacy: .private)")
            seasonsState = .failed(gusError.localizedDescription)
        }
    }

    func selectSeason(id: String) async {
        guard selectedSeasonID != id || episodesState != .loaded else { return }
        selectedSeasonID = id
        await loadEpisodes(seasonID: id)
    }

    func retryEpisodes() async {
        guard let selectedSeasonID else { return }
        await loadEpisodes(seasonID: selectedSeasonID)
    }

    private func loadEpisodes(seasonID: String) async {
        guard let seriesID = series.id else { return }
        episodeGeneration += 1
        let generation = episodeGeneration
        episodeTask?.cancel()
        episodesState = .loading
        episodes = []

        do {
            let task = Task { try await session.mediaProvider.episodes(seriesID: seriesID, seasonID: seasonID, limit: 1000) }
            episodeTask = task
            let page = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard generation == episodeGeneration, selectedSeasonID == seasonID else { return }
            if let totalRecordCount = page.totalRecordCount, totalRecordCount > 1000 {
                logger.warning("Episode list truncated: series has \(totalRecordCount) episodes but only 1000 were fetched")
            }
            episodes = page.items
            episodesState = .loaded
        } catch {
            guard generation == episodeGeneration, selectedSeasonID == seasonID else { return }
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { episodesState = .idle; return }
            logger.error("Series episodes load failed: \(gusError.localizedDescription, privacy: .private)")
            episodesState = .failed(gusError.localizedDescription)
        }
    }
}
