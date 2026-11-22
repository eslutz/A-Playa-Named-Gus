import SwiftUI

/// Horizontal episode rail with a season picker, used in the series item detail screen.
struct SeriesEpisodesView: View {
    @Environment(RootNavigationState.self) private var root
    let store: SeriesDetailStore
    var preferredEpisode: MediaItem? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: ContentSpacing.card) {
            HStack {
                #if os(tvOS)
                    SeasonPicker(store: store)
                        .font(.title2.bold())
                    Spacer()
                #else
                    Text("Episodes")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    SeasonPicker(store: store)
                #endif
            }

            LoadingStateView(
                state: store.seasonsState,
                isEmpty: store.seasons.isEmpty,
                emptyTitle: "No Seasons",
                emptySymbol: "rectangle.stack",
                retryAction: { Task { await store.loadSeasons() } },
                preservesContent: true
            ) {
                LoadingStateView(
                    state: store.episodesState,
                    isEmpty: store.episodes.isEmpty,
                    emptyTitle: "No Episodes",
                    emptySymbol: "play.rectangle",
                    retryAction: { Task { await store.retryEpisodes() } },
                    preservesContent: true
                ) {
                    SeriesEpisodeRail(episodes: store.episodes, series: store.series, seasonID: store.selectedSeasonID)
                }
            }
        }
        .task(id: preferredEpisode?.id) { await store.preferInitialEpisode(preferredEpisode) }
        .task(id: store.seasons.map(\.id)) { await store.preferInitialEpisode(preferredEpisode) }
        .task(id: store.episodes.map(\.id)) {
            let key = "episodes:" + (store.selectedSeasonID ?? "")
            if root.scrollAnchors[key] == nil, let id = store.preferredEpisodeID,
               let episode = store.episodes.first(where: { $0.id == id })
            {
                root.scrollAnchors[key] = ItemRef(item: episode).id
            }
        }
    }
}

struct SeriesEpisodeRail: View {
    @Environment(RootNavigationState.self) private var root
    let episodes: [MediaItem]
    let series: MediaItem
    let seasonID: String?

    var body: some View {
        let episodeIDs = episodes.map { ItemRef(item: $0).id }
        return ScrollView(.horizontal, showsIndicators: false) {
            // Measure the tallest caption even when it belongs to a later
            // episode. Each card defers its artwork until it enters the viewport.
            HStack(alignment: .top, spacing: ContentSpacing.card) {
                ForEach(episodes, id: \.id) { episode in
                    VStack(alignment: .leading, spacing: ContentSpacing.caption) {
                        NavigationLink(value: GusRoute.item(.init(item: episode))) {
                            EpisodeCard(episode: episode)
                        }
                        .posterNavigationStyle()
                        .mediaItemContextMenu(item: episode)
                        .gusTVFocus(id: ItemRef(item: episode).id, section: "episodes:" + (seasonID ?? ""), ids: episodeIDs, item: episode, context: "detail:" + ItemRef(item: series).id)
                        if let overview = episode.overview?.trimmedNilIfEmpty {
                            DetailSynopsis(title: episode.displayTitle, overview: overview, moreIdentifier: "Episode.fullSynopsis", lines: overviewLineLimit)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .gusTVCardCaption()
                        }
                    }
                    .frame(width: episodeCardWidth)
                    .id(ItemRef(item: episode).id)
                }
            }
            .scrollTargetLayout()
            .gusTVRailPadding()
        }
        .scrollPosition(id: root.scrollBinding(for: "episodes:" + (seasonID ?? "")))
        .lookToScroll(.horizontal)
        .gusTVRailViewport()
    }

    private var overviewLineLimit: Int {
        #if os(tvOS)
            3
        #else
            2
        #endif
    }

    private var episodeCardWidth: CGFloat {
        #if os(tvOS)
            return 520
        #elseif os(visionOS)
            return 320
        #else
            return 260
        #endif
    }
}

// MARK: - Season picker

private struct SeasonPicker: View {
    let store: SeriesDetailStore

    var body: some View {
        if store.seasons.count > 1 {
            Picker("Season", selection: selectedSeason) {
                ForEach(store.seasons, id: \.id) { season in
                    Text(season.displayTitle)
                        .tag(season.id ?? "")
                }
            }
            .pickerStyle(.menu)
            .menuIndicator(.visible)
            .accessibilityIdentifier("Series.seasonPicker")
            .accessibilityLabel("Season")
            .accessibilityValue(Text(selectedSeasonTitle))
        } else if !store.seasons.isEmpty {
            Text(selectedSeasonTitle)
        }
    }

    private var selectedSeason: Binding<String> {
        Binding {
            store.selectedSeasonID ?? ""
        } set: { id in
            guard !id.isEmpty else { return }
            Task { await store.selectSeason(id: id) }
        }
    }

    private var selectedSeasonTitle: LocalizedStringKey {
        guard let selected = store.seasons.first(where: { $0.id == store.selectedSeasonID }) else {
            return "Season"
        }
        return LocalizedStringKey(selected.displayTitle)
    }
}

// MARK: - Episode card

struct EpisodeCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(SessionStore.self) private var session
    @State private var loadsArtwork = false
    let episode: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: ContentSpacing.group) {
            Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    if loadsArtwork {
                        ArtworkTile(
                            url: session.mediaProvider.backdropImageURL(for: episode, maxWidth: artworkWidth),
                            aspectRatio: 16.0 / 9.0,
                            contentMode: .fit,
                            placeholderSymbol: "play.rectangle",
                            fallbackURLs: session.mediaProvider.artworkURLs(for: episode, request: .init(role: .episodeStill, maxWidth: artworkWidth))
                        )
                    } else {
                        Rectangle().fill(.thinMaterial)
                    }
                }
                .onScrollVisibilityChange(threshold: 0.01) { visible in loadsArtwork = visible }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .posterHoverEffect()
                .gusTVArtworkStatus(item: episode)
                .overlay(alignment: .topTrailing) {
                    if episode.userData?.isWatched == true {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.8))
                            .padding(ContentSpacing.group)
                            .accessibilityHidden(true)
                    }
                }

            VStack(alignment: .leading, spacing: ContentSpacing.caption) {
                if let locator = episode.episodeLocator {
                    Text(locator)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(episode.displayTitle)
                    .font(.headline)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                #if os(tvOS)
                    if let runtime = episode.runtimeText {
                        Text(runtime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                #endif
            }
            .gusTVCardCaption()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(episode.mediaAccessibility.label)
        .accessibilityValue(episode.mediaAccessibility.value)
    }

    private var artworkWidth: Int {
        #if os(tvOS)
            1040
        #else
            420
        #endif
    }
}
