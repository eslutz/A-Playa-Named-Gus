import JellyfinAPI
import SwiftUI

/// Item detail surface re-expressed from the Swiftfin visionOS PR layout using A Playa Named Gus's
/// native SwiftUI stack: cinematic header, inline actions, metadata rows, and about cards.
struct ItemDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    @Environment(PlaybackRefreshStore.self) private var playbackRefresh
    @Environment(UpNextStore.self) private var upNext
    let item: BaseItemDto

    @State private var playerItem: ItemRef?
    @State private var store: ItemDetailStore?

    var body: some View {
        Group {
            if let store {
                LoadingStateView(state: store.state) {
                    detailContent(for: store)
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
        #if os(iOS) || os(visionOS)
        .toolbarBackground(.hidden, for: .navigationBar)
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

    private func detailContent(for store: ItemDetailStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CinematicDetailHero(
                    item: store.item,
                    backdropURL: session.imageBuilder.backdropImageURL(for: store.item, context: .backdrop),
                    play: {
                        playerItem = ItemRef(item: store.item)
                    },
                    isInUpNext: upNext.contains(store.item, serverID: session.server.id, userID: session.user.id),
                    toggleUpNext: {
                        upNext.toggle(store.item, serverID: session.server.id, userID: session.user.id)
                        playbackRefresh.markPlaybackProgressChanged()
                    }
                ) {
                    if DownloadsAvailability.isSupported {
                        DownloadButton(item: store.item, iconOnly: true)
                    }
                }

                VStack(alignment: .leading, spacing: 30) {
                    if let seriesStore = store.seriesStore {
                        SeriesEpisodesView(store: seriesStore)
                    }

                    DetailMetadataRows(item: store.item)

                    if let people = store.item.people, !people.isEmpty {
                        CastRail(people: people)
                    }

                    if !store.specialFeatures.isEmpty {
                        MediaRail(title: "Special Features", items: store.specialFeatures, style: .backdrop)
                    }

                    if !store.similarItems.isEmpty {
                        MediaRail(title: "Recommended", items: store.similarItems)
                    }

                    AboutCardsView(
                        item: store.item,
                        posterURL: session.imageBuilder.primaryImageURL(for: store.item, context: .posterRail)
                    )
                }
                .padding(sectionPadding)
            }
            .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .lookToScroll()
        .task {
            downloads.load(serverID: session.server.id, userID: session.user.id)
            upNext.load(serverID: session.server.id, userID: session.user.id)
        }
    }

    private var sectionPadding: EdgeInsets {
        #if os(visionOS) || os(tvOS)
            return EdgeInsets(top: 30, leading: 36, bottom: 40, trailing: 36)
        #else
            return EdgeInsets(top: 24, leading: 20, bottom: 32, trailing: 20)
        #endif
    }
}

private struct CinematicDetailHero<Accessory: View>: View {
    let item: BaseItemDto
    let backdropURL: URL?
    let play: () -> Void
    let isInUpNext: Bool
    let toggleUpNext: () -> Void
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
                    .black.opacity(0.54),
                    .black.opacity(0.18),
                    .clear,
                ],
                startPoint: .bottom,
                endPoint: .top
            )

            LinearGradient(
                colors: [.black.opacity(0.72), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )

            ViewThatFits(in: .horizontal) {
                wideOverlay
                compactOverlay
            }
            .foregroundStyle(.white)
            .padding(heroPadding)
        }
        .background(Color.black.opacity(0.22))
        .ignoresSafeArea(edges: .top)
        .accessibilityElement(children: .contain)
    }

    private var wideOverlay: some View {
        HStack(alignment: .bottom, spacing: 28) {
            titleBlock
                .frame(maxWidth: 760, alignment: .leading)

            Spacer(minLength: 24)

            actionStack
                .frame(width: actionWidth, alignment: .trailing)
        }
    }

    private var compactOverlay: some View {
        VStack(alignment: .leading, spacing: 18) {
            titleBlock
            actionStack
                .frame(maxWidth: 320, alignment: .leading)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.displayTitle)
                .font(titleFont)
                .fontWeight(.bold)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HeroMetadataRow(item: item)

            if let overview = item.overview?.trimmedNilIfEmpty {
                Text(overview)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(4)
            }
        }
    }

    private var actionStack: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                playButton
                upNextButton
                accessory
            }

            VStack(alignment: .trailing, spacing: 10) {
                playButton
                HStack(spacing: 10) {
                    upNextButton
                    accessory
                }
            }
        }
    }

    private var playButton: some View {
        Button(action: play) {
            Label("Play", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.accentColor)
        .gusDefaultActionShortcut()
        .visionHoverEffect(cornerRadius: 10)
    }

    private var upNextButton: some View {
        ItemUserActionButton(
            title: isInUpNext ? "Remove from Up Next" : "Add to Up Next",
            systemImage: isInUpNext ? "checkmark" : "plus",
            action: toggleUpNext
        )
    }

    private var titleFont: Font {
        #if os(tvOS)
            return .system(size: 72, weight: .bold)
        #elseif os(visionOS)
            return .system(size: 54, weight: .bold)
        #elseif os(macOS)
            return .largeTitle.bold()
        #else
            return .title.bold()
        #endif
    }

    private var heroHeight: CGFloat {
        #if os(tvOS)
            return 620
        #elseif os(visionOS)
            return 560
        #elseif os(macOS)
            return 480
        #else
            return 420
        #endif
    }

    private var heroPadding: CGFloat {
        #if os(tvOS) || os(visionOS)
            return 40
        #else
            return 24
        #endif
    }

    private var actionWidth: CGFloat {
        #if os(tvOS) || os(visionOS)
            return 220
        #else
            return 180
        #endif
    }
}

private struct HeroMetadataRow: View {
    let item: BaseItemDto

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                tokens
            }

            VStack(alignment: .leading, spacing: 6) {
                tokens
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white.opacity(0.72))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var tokens: some View {
        if let locator = item.type == .episode ? item.episodeLocator : nil {
            Text(locator)
        }
        if let year = item.yearText {
            Text(year)
        }
        if let runtime = item.runtimeText {
            Text(runtime)
        }
        if let rating = item.officialRating {
            Text(rating)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.5)))
        }
        if let community = item.communityRatingText {
            Text(community)
                .foregroundStyle(Color.gusRatingStar)
        }
        if let critic = item.criticRatingText {
            Text(String(localized: "Critic \(critic)", comment: "Critic score label, e.g. 'Critic 74%'"))
        }
    }
}

private struct ItemUserActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 36)
        }
        .buttonStyle(.bordered)
        .visionHoverEffect(cornerRadius: 10)
        .accessibilityLabel(title)
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
    var iconOnly = false

    var body: some View {
        if let record = downloads.record(for: item, serverID: session.server.id, userID: session.user.id) {
            switch record.status {
            case .complete where downloads.localFileURL(for: item, serverID: session.server.id, userID: session.user.id) != nil:
                statusLabel("Downloaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Downloaded on \(record.downloadedAt.formatted(date: .abbreviated, time: .shortened))")
            case .queued:
                statusLabel("Queued", systemImage: "clock")
                    .foregroundStyle(.secondary)
            case .downloading:
                statusLabel(record.requiresTranscodingForDownload && record.progress == 0 ? "Transcoding for download..." : "Downloading", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            case .paused:
                Button {
                    Task { await downloads.resume(itemID: item.id ?? "", session: session) }
                } label: {
                    buttonLabel("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .visionHoverEffect(cornerRadius: 10)
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
                buttonLabel("Downloading", systemImage: "arrow.down.circle")
            } else {
                buttonLabel("Download", systemImage: "arrow.down.circle")
            }
        }
        .disabled(itemID.map { downloads.activeItemIDs.contains($0) } ?? true)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .visionHoverEffect(cornerRadius: 10)
    }

    @ViewBuilder
    private func statusLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        if iconOnly {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 36)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private func buttonLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        if iconOnly {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 36)
        } else {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct DetailMetadataRows: View {
    let item: BaseItemDto

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let genres = item.genres?.nonEmptyStrings, !genres.isEmpty {
                MetadataPillRow(title: "Genres", values: genres)
            }

            if let studios = item.studios?.compactMap(\.name).nonEmptyStrings, !studios.isEmpty {
                MetadataPillRow(title: "Studios", values: studios)
            }
        }
    }
}

private struct MetadataPillRow: View {
    let title: LocalizedStringKey
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(values, id: \.self) { value in
                        Text(value)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
                .padding(.vertical, 2)
            }
            .lookToScroll(.horizontal)
        }
    }
}

private struct SeriesEpisodesView: View {
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

private struct EpisodeCard: View {
    @Environment(SessionStore.self) private var session
    let episode: BaseItemDto

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)

                AsyncPoster(
                    url: session.imageBuilder.backdropImageURL(for: episode, maxWidth: 420),
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

private struct CastRail: View {
    @Environment(SessionStore.self) private var session
    let people: [BaseItemPerson]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cast & Crew")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(displayPeople, id: \.self) { person in
                        VStack(alignment: .leading, spacing: 7) {
                            ZStack {
                                Rectangle()
                                    .fill(.thinMaterial)

                                if let imageURL = session.imageBuilder.personImageURL(for: person.source, maxWidth: 240) {
                                    AsyncPoster(url: imageURL, contentMode: .fill, placeholderSymbol: "person")
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 120, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .posterHoverEffect()

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
                        .frame(width: 120, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 4)
            }
            .lookToScroll(.horizontal)
        }
    }

    private var displayPeople: [CastDisplayPerson] {
        people.prefix(16).compactMap(CastDisplayPerson.init)
    }
}

private struct AboutCardsView: View {
    let item: BaseItemDto
    let posterURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    posterSummaryCard

                    if let overview = item.overview?.trimmedNilIfEmpty {
                        DetailInfoCard(title: LocalizedStringKey(item.displayTitle)) {
                            Text(overview)
                                .lineLimit(5)
                        }
                    }

                    DetailInfoCard(title: "Media") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let runtime = item.runtimeText {
                                Text(runtime)
                            }
                            if let rating = item.officialRating {
                                Text(rating)
                            }
                            if let container = item.container?.trimmedNilIfEmpty {
                                Text(container.uppercased())
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .lookToScroll(.horizontal)
        }
    }

    private var posterSummaryCard: some View {
        DetailInfoCard(title: LocalizedStringKey(item.displayTitle)) {
            HStack(alignment: .top, spacing: 12) {
                AsyncPoster(url: posterURL, contentMode: .fill, placeholderSymbol: item.type == .series ? "tv" : "film")
                    .frame(width: 74, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    if let tagline = item.primaryTagline {
                        Text(tagline)
                            .lineLimit(3)
                    }
                    if let year = item.yearText {
                        Text(year)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct DetailInfoCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .lineLimit(2)
            content
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .padding(16)
        .frame(width: AboutCardMetrics.cardWidth, height: AboutCardMetrics.cardHeight, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CastDisplayPerson: Hashable {
    let source: BaseItemPerson
    let name: String
    let role: String?

    init?(_ person: BaseItemPerson) {
        guard let name = person.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }
        self.source = person
        self.name = name
        self.role = person.role?.trimmedNilIfEmpty
    }
}

private extension Array where Element == String {
    var nonEmptyStrings: [String]? {
        let cleaned = map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? nil : cleaned
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
