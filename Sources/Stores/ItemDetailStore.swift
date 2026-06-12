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

    private let session: SessionStore
    private let logger = Logger(category: .item)

    init(item: MediaItem, session: SessionStore) {
        self.item = item
        self.session = session
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading

        do {
            if let id = item.id {
                item = try await session.mediaProvider.item(id: id)
            }

            state = .loaded
            await loadRelatedContent(for: item)

            if item.type == .series {
                let store = SeriesDetailStore(series: item, session: session)
                seriesStore = store
                await store.loadSeasons()
            }
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            logger.error("Item detail load failed: \(gusError.localizedDescription, privacy: .public)")
            state = .failed(gusError.localizedDescription)
        }
    }

    /// Toggles the watched/played state of the item on the server and refreshes local state.
    func toggleWatched() async {
        guard let itemID = item.id else { return }
        let wasWatched = item.userData?.isWatched == true
        do {
            try await session.mediaProvider.toggleWatched(itemID: itemID, currentlyWatched: wasWatched)
            // Refresh item so userData reflects the new state.
            item = try await session.mediaProvider.item(id: itemID)
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            logger.error("Toggle watched failed: \(gusError.localizedDescription, privacy: .public)")
        }
    }

    /// Toggles the favourite state of the item on the server and refreshes local state.
    func toggleFavorite() async {
        guard let itemID = item.id else { return }
        let wasFavorite = item.userData?.isFavorite == true
        do {
            try await session.mediaProvider.toggleFavorite(itemID: itemID, currentlyFavorite: wasFavorite)
            // Refresh item so userData reflects the new state.
            item = try await session.mediaProvider.item(id: itemID)
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            logger.error("Toggle favourite failed: \(gusError.localizedDescription, privacy: .public)")
        }
    }

    private func loadRelatedContent(for item: MediaItem) async {
        async let similar = loadSimilarItems(for: item)
        async let special = loadSpecialFeatures(for: item)

        similarItems = await ContentRatingGate.filter(similar)
        specialFeatures = await ContentRatingGate.filter(special)
    }

    private func loadSimilarItems(for item: MediaItem) async -> [MediaItem] {
        guard let itemID = item.id else { return [] }
        do {
            return try await session.mediaProvider.similarItems(itemID: itemID, limit: 12)
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return [] }
            logger.debug("Similar items load failed: \(gusError.localizedDescription, privacy: .public)")
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
            logger.debug("Special features load failed: \(gusError.localizedDescription, privacy: .public)")
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

    init(series: MediaItem, session: SessionStore) {
        self.series = series
        self.session = session
    }

    func loadSeasons() async {
        guard seasonsState != .loading, let seriesID = series.id else { return }
        seasonsState = .loading

        do {
            seasons = try await session.mediaProvider.seasons(seriesID: seriesID)
            selectedSeasonID = SeriesRequest.initialSeasonID(from: seasons)
            seasonsState = .loaded

            if let selectedSeasonID {
                await loadEpisodes(seasonID: selectedSeasonID)
            }
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            logger.error("Series seasons load failed: \(gusError.localizedDescription, privacy: .public)")
            seasonsState = .failed(gusError.localizedDescription)
        }
    }

    func selectSeason(id: String) async {
        guard selectedSeasonID != id else { return }
        selectedSeasonID = id
        await loadEpisodes(seasonID: id)
    }

    private func loadEpisodes(seasonID: String) async {
        guard let seriesID = series.id else { return }
        episodesState = .loading
        episodes = []

        do {
            let page = try await session.mediaProvider.episodes(seriesID: seriesID, seasonID: seasonID, limit: 1000)
            if let totalRecordCount = page.totalRecordCount, totalRecordCount > 1000 {
                logger.warning("Episode list truncated: series has \(totalRecordCount) episodes but only 1000 were fetched")
            }
            episodes = page.items
            episodesState = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            logger.error("Series episodes load failed: \(gusError.localizedDescription, privacy: .public)")
            episodesState = .failed(gusError.localizedDescription)
        }
    }
}
