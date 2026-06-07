import Foundation
import JellyfinAPI
import Observation
import OSLog

enum SeriesRequest {
    static func seasonsParameters(userID: String) -> Paths.GetSeasonsParameters {
        Paths.GetSeasonsParameters(
            userID: userID,
            fields: SearchRequest.metadataFields,
            enableImages: true,
            enableUserData: true
        )
    }

    static func episodesParameters(userID: String, seasonID: String) -> Paths.GetEpisodesParameters {
        Paths.GetEpisodesParameters(
            userID: userID,
            fields: SearchRequest.metadataFields,
            seasonID: seasonID,
            startIndex: 0,
            limit: 300,
            enableImages: true,
            enableUserData: true,
            sortBy: .indexNumber
        )
    }

    static func initialSeasonID(from seasons: [BaseItemDto]) -> String? {
        seasons.first { ($0.indexNumber ?? 0) > 0 }?.id ?? seasons.first?.id
    }
}

@MainActor
@Observable
final class ItemDetailStore {
    private(set) var state: LoadState = .idle
    private(set) var item: BaseItemDto
    private(set) var seriesStore: SeriesDetailStore?
    private(set) var similarItems: [BaseItemDto] = []
    private(set) var specialFeatures: [BaseItemDto] = []

    private let session: SessionStore
    private let logger = Logger(category: .item)

    init(item: BaseItemDto, session: SessionStore) {
        self.item = item
        self.session = session
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading

        do {
            if let id = item.id {
                let response = try await NetworkRetryPolicy.idempotent.run {
                    try await session.client.send(Paths.getItem(itemID: id, userID: session.user.id))
                }
                item = response.value
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

    private func loadRelatedContent(for item: BaseItemDto) async {
        async let similar = loadSimilarItems(for: item)
        async let special = loadSpecialFeatures(for: item)

        similarItems = await similar
        specialFeatures = await special
    }

    private func loadSimilarItems(for item: BaseItemDto) async -> [BaseItemDto] {
        guard let itemID = item.id else { return [] }
        do {
            let parameters = Paths.GetSimilarItemsParameters(
                userID: session.user.id,
                limit: 12,
                fields: SearchRequest.metadataFields
            )
            let response = try await NetworkRetryPolicy.idempotent.run {
                try await session.client.send(Paths.getSimilarItems(itemID: itemID, parameters: parameters))
            }
            return response.value.items ?? []
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return [] }
            logger.debug("Similar items load failed: \(gusError.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func loadSpecialFeatures(for item: BaseItemDto) async -> [BaseItemDto] {
        guard let itemID = item.id else { return [] }
        do {
            let response = try await NetworkRetryPolicy.idempotent.run {
                try await session.client.send(Paths.getSpecialFeatures(itemID: itemID, userID: session.user.id))
            }
            return response.value
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
    private(set) var seasons: [BaseItemDto] = []
    private(set) var episodes: [BaseItemDto] = []
    private(set) var selectedSeasonID: String?

    let series: BaseItemDto

    private let session: SessionStore
    private let logger = Logger(category: .item)

    init(series: BaseItemDto, session: SessionStore) {
        self.series = series
        self.session = session
    }

    func loadSeasons() async {
        guard seasonsState != .loading, let seriesID = series.id else { return }
        seasonsState = .loading

        do {
            let parameters = SeriesRequest.seasonsParameters(userID: session.user.id)
            let response = try await NetworkRetryPolicy.idempotent.run {
                try await session.client.send(Paths.getSeasons(seriesID: seriesID, parameters: parameters))
            }
            seasons = response.value.items ?? []
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
            let parameters = SeriesRequest.episodesParameters(userID: session.user.id, seasonID: seasonID)
            let response = try await NetworkRetryPolicy.idempotent.run {
                try await session.client.send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters))
            }
            episodes = response.value.items ?? []
            episodesState = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            logger.error("Series episodes load failed: \(gusError.localizedDescription, privacy: .public)")
            episodesState = .failed(gusError.localizedDescription)
        }
    }
}
