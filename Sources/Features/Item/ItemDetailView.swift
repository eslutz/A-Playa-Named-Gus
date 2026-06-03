import JellyfinAPI
import SwiftUI

/// Item detail: backdrop, metadata, overview, and a **Play** button. On visionOS, a
/// **Cinema** toggle in a toolbar ornament opens the immersive space.
struct ItemDetailView: View {
    @Environment(SessionStore.self) private var session
    let item: BaseItemDto

    @State private var playerItem: ItemRef?
    @State private var store: ItemDetailStore?

    var body: some View {
        Group {
            if let store {
                LoadingStateView(state: store.state) {
                    detailContent(for: store.item, seriesStore: store.seriesStore)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(store?.item.displayTitle ?? item.displayTitle)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                if store == nil {
                    let store = ItemDetailStore(item: item, session: session)
                    self.store = store
                    await store.load()
                }
            }
        #if os(visionOS)
            .toolbar {
                if let item = store?.item {
                    ToolbarItem(placement: .bottomOrnament) {
                        CinemaToggleButton(item: item)
                    }
                }
            }
        #endif
            .playerPresentation(item: $playerItem)
    }

    private func detailContent(for item: BaseItemDto, seriesStore: SeriesDetailStore?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AsyncPoster(
                    url: session.imageBuilder.backdropImageURL(for: item),
                    contentMode: .fill,
                    placeholderSymbol: "film"
                )
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(item.displayTitle)
                    .font(.largeTitle.bold())

                metadataRow(for: item)

                HStack(spacing: 16) {
                    Button {
                        playerItem = ItemRef(item: item)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .gusDefaultActionShortcut()
                    .accessibilityHint("Starts playback for this item.")
                }

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                RichMetadataView(item: item)

                if let seriesStore {
                    SeriesEpisodesView(store: seriesStore)
                }
            }
            .padding()
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .lookToScroll()
    }

    private func metadataRow(for item: BaseItemDto) -> some View {
        HStack(spacing: 12) {
            if let year = item.yearText {
                Label(year, systemImage: "calendar").labelStyle(.titleOnly)
            }
            if let runtime = item.runtimeText {
                Text(runtime)
            }
            if let rating = item.officialRating {
                Text(rating)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary))
            }
            if let community = item.communityRatingText {
                Text(community).foregroundStyle(Color.gusRatingStar)
            }
            if let critic = item.criticRatingText {
                // Explicit String(localized:comment:) preserves the translator comment and
                // avoids the implicit LocalizedStringKey coupling of Text interpolation.
                Text(String(localized: "Critic \(critic)", comment: "Critic score label, e.g. 'Critic 74%'"))
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        // Combine year, runtime, rating, and score into a single VoiceOver element so the
        // row reads as one sentence rather than four separate focus stops.
        .accessibilityElement(children: .combine)
    }
}

private struct RichMetadataView: View {
    let item: BaseItemDto

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let tagline = item.primaryTagline {
                Text(tagline)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if let genreText = item.genreText {
                LabeledContent("Genres", value: genreText)
            }

            if let studioText = item.studioText {
                LabeledContent("Studios", value: studioText)
            }

            if !item.peopleText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cast & Crew")
                        .font(.headline)
                    ForEach(item.peopleText, id: \.self) { person in
                        Text(person)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct SeriesEpisodesView: View {
    let store: SeriesDetailStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Episodes")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            LoadingStateView(
                state: store.seasonsState,
                isEmpty: store.seasons.isEmpty,
                emptyTitle: "No Seasons",
                emptySymbol: "rectangle.stack"
            ) {
                Picker("Season", selection: seasonSelection) {
                    ForEach(store.seasons, id: \.id) { season in
                        Text(season.displayTitle)
                            .tag(season.id ?? "")
                    }
                }
                .pickerStyle(.menu)

                LoadingStateView(
                    state: store.episodesState,
                    isEmpty: store.episodes.isEmpty,
                    emptyTitle: "No Episodes",
                    emptySymbol: "play.rectangle"
                ) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(store.episodes, id: \.id) { episode in
                            NavigationLink(value: ItemRef(item: episode)) {
                                EpisodeRow(episode: episode)
                            }
                            .posterNavigationStyle()
                        }
                    }
                    .tvFocusSection()
                }
            }
        }
    }

    private var seasonSelection: Binding<String> {
        Binding {
            store.selectedSeasonID ?? ""
        } set: { id in
            Task {
                await store.selectSeason(id: id)
            }
        }
    }
}

private struct EpisodeRow: View {
    let episode: BaseItemDto

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(episode.episodeLocator ?? episode.displayTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.displayTitle)
                    .font(.headline)
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let runtime = episode.runtimeText {
                Text(runtime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        // Collapse the locator/title/runtime columns into one VoiceOver element.
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
