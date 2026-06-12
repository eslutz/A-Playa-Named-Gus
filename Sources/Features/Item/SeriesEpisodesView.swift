import SwiftUI

/// Horizontal episode rail with a season picker, used in the series item detail screen.
struct SeriesEpisodesView: View {
    let store: SeriesDetailStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Episodes")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                SeasonPicker(store: store)
            }

            LoadingStateView(
                state: store.seasonsState,
                isEmpty: store.seasons.isEmpty,
                emptyTitle: "No Seasons",
                emptySymbol: "rectangle.stack"
            ) {
                LoadingStateView(
                    state: store.episodesState,
                    isEmpty: store.episodes.isEmpty,
                    emptyTitle: "No Episodes",
                    emptySymbol: "play.rectangle"
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 18) {
                            ForEach(store.episodes, id: \.id) { episode in
                                NavigationLink(value: ItemRef(item: episode)) {
                                    EpisodeCard(episode: episode)
                                        .frame(width: episodeCardWidth)
                                }
                                .posterNavigationStyle()
                            }
                        }
                        .padding(.vertical, 4)
                        .tvFocusSection()
                    }
                    .lookToScroll(.horizontal)
                }
            }
        }
    }

    private var episodeCardWidth: CGFloat {
        #if os(tvOS)
            return 360
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
        Menu {
            Picker("Season", selection: selectedSeason) {
                ForEach(store.seasons, id: \.id) { season in
                    Text(season.displayTitle)
                        .tag(season.id ?? "")
                }
            }
        } label: {
            Label(selectedSeasonTitle, systemImage: "chevron.up.chevron.down")
        }
        .disabled(store.seasons.isEmpty)
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

private struct EpisodeCard: View {
    @Environment(SessionStore.self) private var session
    let episode: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)

                AsyncPoster(
                    url: session.mediaProvider.backdropImageURL(for: episode, maxWidth: 420),
                    contentMode: .fit,
                    placeholderSymbol: "play.rectangle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .posterHoverEffect()

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.episodeLocator ?? episode.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(episode.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                if let overview = episode.overview?.trimmedNilIfEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(episodeAccessibilityLabel)
    }

    private var episodeAccessibilityLabel: String {
        var parts: [String] = []
        if let locator = episode.episodeLocator {
            parts.append(locator)
        }
        parts.append(episode.displayTitle)
        if let runtime = episode.runtimeText {
            parts.append(runtime)
        }
        return parts.joined(separator: ", ")
    }
}
