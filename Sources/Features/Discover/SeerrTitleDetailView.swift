import Observation
import SwiftUI

@MainActor @Observable
final class SeerrTitleDetailStore {
    let mediaType: SeerrMediaType
    let id: Int
    private(set) var title: SeerrTitle?
    private(set) var state: LoadState = .idle
    private(set) var revision: UUID?
    private(set) var restrictions: String?
    private var generation = UUID()

    init(title: SeerrTitle) {
        mediaType = title.mediaType ?? .unknown
        id = title.id
    }

    func invalidate() {
        generation = UUID()
        title = nil
        state = .idle
    }

    func load(store: SeerrStore) async {
        let revision = store.revision
        let restrictions = String(describing: store.restrictionRevision)
        self.revision = revision
        self.restrictions = restrictions
        generation = UUID()
        let operation = generation
        title = nil
        state = .loading
        do {
            guard mediaType == .movie || mediaType == .tv else { throw SeerrClientError.invalidPayload }
            let result = try await store.requireClient().details(mediaType: mediaType, id: id)
            guard !Task.isCancelled, store.revision == revision, generation == operation,
                  String(describing: store.restrictionRevision) == restrictions else { return }
            guard store.admits(result) else {
                state = .loaded
                return
            }
            title = result
            state = .loaded
        } catch {
            guard !Task.isCancelled, store.revision == revision, generation == operation,
                  String(describing: store.restrictionRevision) == restrictions else { return }
            store.handle(error)
            guard store.revision == revision else { return }
            state = .failed(error.localizedDescription)
        }
    }
}

/// Metadata, requesting and accessible Jellyfin identity remain distinct actions.
struct SeerrTitleDetailView: View {
    let store: SeerrStore
    @State private var detail: SeerrTitleDetailStore
    @State private var requestTitle: SeerrTitle?
    @State private var reportTitle: SeerrTitle?
    @State private var externalURL: URL?
    @Environment(\.openURL) private var openURL
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimitRawValue = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnratedContent = false

    init(title: SeerrTitle, store: SeerrStore) {
        self.store = store
        _detail = State(initialValue: SeerrTitleDetailStore(title: title))
    }

    private var accessRevision: String {
        "\(store.revision):\(contentLimitRawValue):\(hideUnratedContent)"
    }

    private var authorizedTitle: SeerrTitle? {
        _ = contentLimitRawValue
        _ = hideUnratedContent
        guard detail.revision == store.revision, detail.restrictions == store.restrictionRevision else { return nil }
        return detail.title.flatMap { store.admits($0) ? $0 : nil }
    }

    var body: some View {
        Group {
            if detail.state == .loaded, authorizedTitle == nil {
                RestrictedContentView()
            } else {
                LoadingStateView(state: detail.state, retryAction: { Task { await detail.load(store: store) } }) {
                    if let title = authorizedTitle {
                        content(title)
                    }
                }
            }
        }
        .navigationTitle(authorizedTitle?.displayTitle ?? String(localized: "Title"))
        .task(id: accessRevision) {
            requestTitle = nil
            reportTitle = nil
            await detail.load(store: store)
        }
        .sheet(item: $requestTitle, onDismiss: { Task { await detail.load(store: store) } }) { title in
            SeerrRequestView(title: title)
        }
        .sheet(item: $reportTitle) { title in
            SeerrReportIssueView(title: title)
        }
        .alert("Open Seerr on Another Device", isPresented: Binding(get: { externalURL != nil }, set: {
            if !$0 {
                externalURL = nil
            }
        })) {
            Button("Done", role: .cancel) { externalURL = nil }
        } message: {
            if let externalURL {
                Text("Open this address in a browser and sign in to Seerr: \(externalURL.absoluteString)")
            }
        }
        .toolbar {
            if let title = authorizedTitle, let client = store.client {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if store.user?.canViewIssues == true, title.mediaInfo != nil {
                            NavigationLink {
                                SeerrIssuesView(title: title)
                            } label: { Label("Issues", systemImage: "exclamationmark.bubble") }
                        }
                        if store.user?.canCreateIssues == true, title.mediaInfo != nil {
                            Button("Report an Issue", systemImage: "exclamationmark.bubble") { reportTitle = title }
                        }
                        Button("Open in Seerr", systemImage: "arrow.up.right.square") {
                            let url = client.baseURL.appending(path: "\(detail.mediaType.rawValue)/\(title.id)")
                            openURL(url) { accepted in
                                if !accepted {
                                    externalURL = url
                                }
                            }
                        }
                    } label: { Label("More Actions", systemImage: "ellipsis") }
                }
            }
        }
    }

    private func content(_ title: SeerrTitle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SeerrArtworkView(
                    path: title.backdropPath ?? title.posterPath,
                    aspectRatio: title.backdropPath == nil ? 2.0 / 3.0 : 16.0 / 9.0,
                    width: "w1280"
                )
                .frame(maxHeight: 520)
                .clipped()
                identity(title)
                actions(title)
                if let synopsis = title.overview?.trimmedNilIfEmpty {
                    Text(synopsis).font(.body).fixedSize(horizontal: false, vertical: true)
                }
                if detail.mediaType == .tv, let seasons = title.seasons, !seasons.isEmpty {
                    seasonList(title, seasons: seasons)
                }
                if let credits = title.credits, !credits.cast.isEmpty || !credits.crew.isEmpty {
                    SeerrCreditsSection(credits: credits, store: store)
                }
                SeerrRecommendationsSection(title: title, mediaType: detail.mediaType, store: store)
            }
            .padding()
            .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .lookToScroll()
        .refreshable { await detail.load(store: store) }
    }

    private func identity(_ title: SeerrTitle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.displayTitle).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
            Text(title.seerrIdentityDescription).foregroundStyle(.secondary)
            if let certification = title.certification {
                Text(certification).font(.subheadline).foregroundStyle(.secondary)
            }
            if let runtime = title.runtime, runtime > 0 {
                Text("\(runtime) min").font(.subheadline).foregroundStyle(.secondary)
            }
            if let rating = title.voteAverage, rating > 0 {
                Text("TMDB \(rating, specifier: "%.1f")/10").font(.subheadline).foregroundStyle(.secondary)
            }
            if let genres = title.genres, !genres.isEmpty {
                Text(genres.map(\.name).joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(title.seerrAvailabilityDescription).font(.headline)
        }
    }

    private func actions(_ title: SeerrTitle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if canOpenRequest(title) {
                Button(detail.mediaType == .tv ? "Request Seasons" : "Request", systemImage: "plus.circle") {
                    requestTitle = title
                }
                .buttonStyle(.borderedProminent)
            }
            if title.mediaInfo?.status == .available || title.mediaInfo?.status == .partiallyAvailable {
                SeerrPlaybackMatchView(title: title)
            }
            SeerrBlocklistAction(title: title) {
                detail.invalidate()
                Task { await detail.load(store: store) }
            }
        }
    }

    private func canOpenRequest(_ title: SeerrTitle) -> Bool {
        guard store.user?.canRequest(detail.mediaType) == true else { return false }
        switch title.mediaInfo?.status {
        case .available, .blocklisted: return false
        case .pending, .processing: return detail.mediaType == .tv
        default: return true
        }
    }

    private func seasonList(_ title: SeerrTitle, seasons: [SeerrSeason]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seasons").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            ForEach(seasons.sorted { $0.seasonNumber < $1.seasonNumber }, id: \.seasonNumber) { season in
                NavigationLink {
                    SeerrSeasonView(series: title, season: season, store: store)
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(season.seerrName).font(.headline)
                            if let count = season.episodeCount {
                                Text("\(count) episodes").font(.subheadline).foregroundStyle(.secondary)
                            }
                            if let state = title.mediaInfo?.seasons?.first(where: { $0.seasonNumber == season.seasonNumber }) {
                                Text(state.status.seerrDescription).font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                Text("Availability unknown").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.forward").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                Divider()
            }
        }
    }
}

struct SeerrCreditsSection: View {
    let credits: SeerrCredits
    let store: SeerrStore

    private var people: [SeerrCredit] {
        var seen: Set<Int> = []
        return (credits.cast + credits.crew).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast & Crew").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(people) { person in
                        NavigationLink {
                            SeerrPersonView(personID: person.id, displayName: person.name, store: store)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                SeerrArtworkView(path: person.profilePath, aspectRatio: 4.0 / 5.0, symbol: "person", width: "w185")
                                Text(person.name).font(.subheadline.weight(.medium))
                                if let role = (person.character ?? person.job)?.trimmedNilIfEmpty {
                                    Text(role).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: CastCardMetrics.width)
                        }
                        .posterNavigationStyle()
                    }
                }
                .tvFocusSection()
                .padding(.vertical, 8)
            }
            .lookToScroll(.horizontal)
        }
    }
}

private struct SeerrRecommendationsSection: View {
    let title: SeerrTitle
    let mediaType: SeerrMediaType
    let store: SeerrStore
    @State private var catalog: SeerrCatalogStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recommendations").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                if catalog?.items.isEmpty == false {
                    NavigationLink("See All") {
                        SeerrCatalogGridView(title: String(localized: "Recommendations"), source: .recommendations(mediaType, title.id), store: store)
                    }
                }
            }
            if let catalog {
                if catalog.state == .loading {
                    ProgressView("Loading recommendations")
                } else if let error = catalog.errorMessage {
                    Text(error).foregroundStyle(.secondary)
                    Button("Retry Recommendations") { Task { await catalog.load(store: store, refresh: true) } }
                } else if catalog.items.isEmpty {
                    Text("No recommendations available").foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(catalog.items.filter { store.admits($0) }, id: \.seerrCatalogID) { item in
                                SeerrResultLink(title: item, store: store)
                                    .frame(width: MediaRailMetrics.itemWidth(for: .poster))
                            }
                        }
                        .tvFocusSection()
                        .padding(.vertical, 8)
                    }
                    .lookToScroll(.horizontal)
                }
            }
        }
        .task(id: "\(store.revision):\(title.id):\(store.restrictionRevision)") {
            let catalog = SeerrCatalogStore(source: .recommendations(mediaType, title.id))
            self.catalog = catalog
            await catalog.load(store: store)
        }
    }
}

extension SeerrSeason {
    var seerrName: String {
        seasonNumber == 0 ? String(localized: "Specials") : String(localized: "Season \(seasonNumber)")
    }
}
