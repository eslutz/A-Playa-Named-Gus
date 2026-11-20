import Observation
import SwiftUI

/// A season's episode rows are metadata; playback is resolved through the Gus library.
struct SeerrSeasonView: View {
    let series: SeerrTitle
    let season: SeerrSeason
    let store: SeerrStore
    @State private var loadedSeason: SeerrSeason?
    @State private var state: LoadState = .idle
    @State private var revision: UUID?
    @State private var loadedRestrictions: String?
    @State private var generation = UUID()
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimitRawValue = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnratedContent = false

    private var accessRevision: String {
        "\(store.revision):\(contentLimitRawValue):\(hideUnratedContent)"
    }

    private var isAuthorized: Bool {
        _ = contentLimitRawValue
        _ = hideUnratedContent
        return store.admits(series) && (revision == nil || revision == store.revision)
    }

    var body: some View {
        Group {
            if !isAuthorized {
                RestrictedContentView()
            } else {
                LoadingStateView(state: state, retryAction: { Task { await load() } }, preservesContent: loadedSeason != nil) {
                    if let loadedSeason {
                        content(loadedSeason)
                    }
                }
            }
        }
        .navigationTitle(isAuthorized ? season.seerrName : String(localized: "Season"))
        .toolbarTitleDisplayMode(.inline)
        .task(id: accessRevision) { await load() }
    }

    private func content(_ season: SeerrSeason) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DetailCoverHeader {
                    SeerrArtworkView(path: season.posterPath ?? series.posterPath, contentMode: .fit, width: "w780")
                        .frame(maxWidth: 220)
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
            .padding()
            .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .lookToScroll()
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        generation = UUID()
        let operation = generation
        let connectionRevision = store.revision
        let restrictions = String(describing: store.restrictionRevision)
        if revision != connectionRevision || loadedRestrictions != restrictions {
            loadedSeason = nil
        }
        revision = connectionRevision
        loadedRestrictions = restrictions
        state = .loading
        defer {
            if generation == operation, Task.isCancelled {
                state = loadedSeason == nil ? .idle : .loaded
            }
        }
        guard store.admits(series) else { state = .loaded; return }
        do {
            let result = try await store.requireClient().season(tvID: series.id, number: season.seasonNumber)
            guard !Task.isCancelled, generation == operation, store.revision == connectionRevision,
                  String(describing: store.restrictionRevision) == restrictions, store.admits(series) else { return }
            loadedSeason = result
            state = .loaded
        } catch {
            guard !Task.isCancelled, generation == operation, store.revision == connectionRevision,
                  String(describing: store.restrictionRevision) == restrictions else { return }
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
