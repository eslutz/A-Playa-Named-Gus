import Observation
import SwiftUI

/// A season's episode rows are metadata; playback is resolved through the Gus library.
struct SeerrSeasonView: View {
    let seriesID: Int
    let seasonNumber: Int
    let store: SeerrStore
    @State private var loaded: (series: SeerrTitle, season: SeerrSeason)?
    @State private var state: LoadState = .idle
    @State private var loadedAccess: String?
    @State private var generation = UUID()
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimitRawValue = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnratedContent = false

    private var accessRevision: String {
        "\(store.revision):\(contentLimitRawValue):\(hideUnratedContent)"
    }

    private var authorizedSeason: (series: SeerrTitle, season: SeerrSeason)? {
        guard loadedAccess == accessRevision, let loaded, store.admits(loaded.series) else { return nil }
        return loaded
    }

    var body: some View {
        Group {
            if state == .loaded, authorizedSeason == nil {
                RestrictedContentView()
            } else {
                LoadingStateView(state: state, retryAction: { Task { await load(refresh: true) } }, preservesContent: authorizedSeason != nil) {
                    if let authorizedSeason {
                        content(authorizedSeason.season, series: authorizedSeason.series)
                    }
                }
            }
        }
        .navigationTitle(authorizedSeason?.season.seerrName ?? String(localized: "Season"))
        .toolbarTitleDisplayMode(.inline)
        .task(id: accessRevision) { await load() }
    }

    private func content(_ season: SeerrSeason, series: SeerrTitle) -> some View {
        ArtworkDetailPage {
            DetailCoverHeader(maximumCoverWidth: 220) {
                SeerrArtworkView(path: season.posterPath ?? series.posterPath, contentMode: .fit, width: "w780")

            } summary: {
                Text(series.displayTitle).font(.title2).foregroundStyle(.secondary)
                Text(season.seerrName).font(.largeTitle.bold())
                Text("Standard format").font(.subheadline).foregroundStyle(.secondary)
                if let summary = season.overview?.trimmedNilIfEmpty {
                    DetailSynopsis(title: season.seerrName, overview: summary)
                }
                if let availability = series.mediaInfo?.seasons?.first(where: { $0.seasonNumber == season.seasonNumber }) {
                    if let description = availability.status.seerrDescription {
                        Text(description).font(.headline)
                    }
                    if availability.status == .available || availability.status == .partiallyAvailable {
                        SeerrPlaybackMatchView(title: series, seasonNumber: season.seasonNumber)
                    }
                }
            }
        } sections: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Episodes").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                if let episodes = season.episodes, !episodes.isEmpty {
                    ForEach(episodes.sorted { $0.episodeNumber < $1.episodeNumber }) { episode in
                        SeerrEpisodeMetadata(episode: episode)
                        Divider()
                    }
                } else {
                    Text("Episode information unavailable").foregroundStyle(.secondary)
                }
                Text("Seerr episode information does not establish playback availability in your Gus library.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .refreshable { await load(refresh: true) }
    }

    @MainActor private func load(refresh: Bool = false) async {
        let access = accessRevision
        if loadedAccess != access {
            loaded = nil
        } else if !refresh, state == .loaded {
            return
        }
        loadedAccess = access
        generation = UUID()
        let operation = generation
        let connectionRevision = store.revision
        state = .loading
        defer {
            if generation == operation, Task.isCancelled {
                state = loaded == nil ? .idle : .loaded
            }
        }
        do {
            let client = try store.requireClient()
            let series = try await client.details(mediaType: .tv, id: seriesID)
            guard !Task.isCancelled, generation == operation, accessRevision == access else { return }
            guard store.admits(series) else {
                loaded = nil
                state = .loaded
                return
            }
            let season = try await client.season(tvID: seriesID, number: seasonNumber)
            guard !Task.isCancelled, generation == operation, accessRevision == access else { return }
            guard season.seasonNumber == seasonNumber else { throw SeerrClientError.invalidPayload }
            loaded = store.admits(series) ? (series, season) : nil
            state = .loaded
        } catch {
            guard !Task.isCancelled, generation == operation, accessRevision == access else { return }
            store.handle(error)
            guard store.revision == connectionRevision else { return }
            state = .failed(error.localizedDescription)
        }
    }
}

private struct SeerrEpisodeMetadata: View {
    let episode: SeerrEpisode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if !dynamicTypeSize.isAccessibilitySize, episode.stillPath != nil {
                SeerrArtworkView(path: episode.stillPath, aspectRatio: 16.0 / 9.0, symbol: "tv", width: "w300")
                    .frame(width: 120)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Episode \(episode.episodeNumber)").font(.subheadline).foregroundStyle(.secondary)
                if let name = episode.name?.trimmedNilIfEmpty {
                    Text(name).font(.headline)
                }
                if let date = episode.airDate?.trimmedNilIfEmpty {
                    Text(date).font(.subheadline).foregroundStyle(.secondary)
                }
                if let summary = episode.overview?.trimmedNilIfEmpty {
                    DetailSynopsis(title: episode.name ?? String(localized: "Episode \(episode.episodeNumber)"), overview: summary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }
}
