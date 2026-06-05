import JellyfinAPI
import SwiftUI

/// Item detail: Apple TV-style backdrop hero, metadata, and native action controls.
struct ItemDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
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
            .playerPresentation(item: $playerItem)
            .downloadErrorAlert(downloads)
    }

    private func detailContent(for item: BaseItemDto, seriesStore: SeriesDetailStore?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                hero(for: item)

                if let seriesStore {
                    SeriesEpisodesView(store: seriesStore)
                }

                RichMetadataView(item: item)
            }
            .padding()
            .frame(maxWidth: 1280, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .lookToScroll()
        .task {
            downloads.load(serverID: session.server.id, userID: session.user.id)
        }
    }

    private func hero(for item: BaseItemDto) -> some View {
        DetailHeroView(
            item: item,
            backdropURL: session.imageBuilder.backdropImageURL(for: item, context: .backdrop),
            play: {
                playerItem = ItemRef(item: item)
            }
        ) {
            if DownloadsAvailability.isSupported {
                DownloadButton(item: item)
            }
        }
    }
}

private struct DetailHeroView<Accessory: View>: View {
    let item: BaseItemDto
    let backdropURL: URL?
    let play: () -> Void
    @ViewBuilder let accessory: Accessory

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncPoster(url: backdropURL, contentMode: .fill, placeholderSymbol: item.type == .series ? "tv" : "film")
                .frame(maxWidth: .infinity)
                .frame(height: heroHeight)
                .clipped()

            LinearGradient(
                colors: [
                    .black.opacity(0.82),
                    .black.opacity(0.42),
                    .black.opacity(0.08),
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )

            VStack(alignment: .leading, spacing: 16) {
                Text(item.displayTitle)
                    .font(.system(.largeTitle, design: .default, weight: .bold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                metadataRow(for: item)

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.body)
                        .lineLimit(4)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 640, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Button(action: play) {
                        Label("Play", systemImage: "play.fill")
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .gusDefaultActionShortcut()
                    .accessibilityHint("Starts playback for this item.")

                    accessory
                }
            }
            .foregroundStyle(.white)
            .padding(heroPadding)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var heroHeight: CGFloat {
        #if os(tvOS)
            return 620
        #elseif os(visionOS)
            return 520
        #elseif os(macOS)
            return 440
        #else
            return 380
        #endif
    }

    private var heroPadding: CGFloat {
        #if os(tvOS) || os(visionOS)
            return 40
        #else
            return 28
        #endif
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

private extension View {
    func downloadErrorAlert(_ downloads: OfflineDownloadStore) -> some View {
        alert(
            "Download Failed",
            isPresented: Binding(
                get: { downloads.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        downloads.clearError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                downloads.clearError()
            }
        } message: {
            Text(downloads.errorMessage ?? "")
        }
    }
}

private struct DownloadButton: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads

    let item: BaseItemDto

    var body: some View {
        if let record = downloads.record(for: item, serverID: session.server.id, userID: session.user.id) {
            switch record.status {
            case .complete where downloads.localFileURL(for: item, serverID: session.server.id, userID: session.user.id) != nil:
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Downloaded on \(record.downloadedAt.formatted(date: .abbreviated, time: .shortened))")
            case .queued:
                Label("Queued", systemImage: "clock")
                    .foregroundStyle(.secondary)
            case .downloading:
                Label(record.requiresTranscodingForDownload && record.progress == 0 ? "Transcoding for download..." : "Downloading", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            case .paused:
                Button {
                    Task { await downloads.resume(itemID: item.id ?? "", session: session) }
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            case .failed, .complete:
                downloadAction(itemID: item.id)
            }
        } else if OfflineDownloadEligibility.canDownload(item), let itemID = item.id {
            downloadAction(itemID: itemID)
        }
    }

    private func downloadAction(itemID: String?) -> some View {
        Button {
            Task { await downloads.download(item, session: session) }
        } label: {
            if let itemID, downloads.activeItemIDs.contains(itemID) {
                Label("Downloading", systemImage: "arrow.down.circle")
            } else {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
        .disabled(itemID.map { downloads.activeItemIDs.contains($0) } ?? true)
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

private struct RichMetadataView: View {
    let item: BaseItemDto

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if item.hasAboutMetadata {
                Text("About")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                LazyVGrid(columns: infoColumns, alignment: .leading, spacing: 16) {
                    if let tagline = item.primaryTagline {
                        MetadataPanel(title: "Tagline") {
                            Text(tagline)
                        }
                    }

                    if let genreText = item.genreText {
                        MetadataPanel(title: "Genres") {
                            Text(genreText)
                        }
                    }

                    if let studioText = item.studioText {
                        MetadataPanel(title: "Studios") {
                            Text(studioText)
                        }
                    }

                    if let rating = item.officialRating {
                        MetadataPanel(title: "Rating") {
                            Text(rating)
                        }
                    }
                }
            }

            if !item.peopleText.isEmpty {
                CastRail(people: item.people ?? [])
            }
        }
    }

    private var infoColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220), spacing: 16)]
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
                SeasonPicker(store: store)

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
            return 300
        #else
            return 240
        #endif
    }
}

private struct SeasonPicker: View {
    let store: SeriesDetailStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.seasons, id: \.id) { season in
                    Button {
                        guard let id = season.id else { return }
                        Task { await store.selectSeason(id: id) }
                    } label: {
                        Text(season.displayTitle)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(season.id == store.selectedSeasonID ? .accentColor : nil)
                }
            }
            .padding(.vertical, 2)
        }
        .lookToScroll(.horizontal)
    }
}

private struct EpisodeCard: View {
    @Environment(SessionStore.self) private var session
    let episode: BaseItemDto

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncPoster(
                url: session.imageBuilder.backdropImageURL(for: episode, maxWidth: 360),
                contentMode: .fill,
                placeholderSymbol: "play.rectangle"
            )
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .posterHoverEffect()

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.episodeLocator ?? episode.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(episode.displayTitle)
                    .font(.headline)
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
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

private struct MetadataPanel<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CastRail: View {
    let people: [BaseItemPerson]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast & Crew")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(displayPeople, id: \.self) { person in
                        VStack(spacing: 8) {
                            Circle()
                                .fill(.thinMaterial)
                                .frame(width: 84, height: 84)
                                .overlay {
                                    Text(person.initials)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }

                            Text(person.name)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            if let role = person.role {
                                Text(role)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 120)
                    }
                }
                .padding(.vertical, 4)
            }
            .lookToScroll(.horizontal)
        }
    }

    private var displayPeople: [CastDisplayPerson] {
        people.prefix(12).compactMap(CastDisplayPerson.init)
    }
}

private struct CastDisplayPerson: Hashable {
    let name: String
    let role: String?

    init?(_ person: BaseItemPerson) {
        guard let name = person.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }
        self.name = name
        self.role = person.role?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

private extension BaseItemDto {
    var hasAboutMetadata: Bool {
        primaryTagline != nil || genreText != nil || studioText != nil || officialRating != nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
