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
        if self.revision != revision || self.restrictions != restrictions {
            title = nil
        }
        self.revision = revision
        self.restrictions = restrictions
        generation = UUID()
        let operation = generation
        state = .loading
        defer {
            if generation == operation, Task.isCancelled {
                state = title == nil ? .idle : .loaded
            }
        }
        do {
            guard mediaType == .movie || mediaType == .tv else { throw SeerrClientError.invalidPayload }
            let result = try await store.requireClient().details(mediaType: mediaType, id: id)
            guard !Task.isCancelled, store.revision == revision, generation == operation,
                  String(describing: store.restrictionRevision) == restrictions else { return }
            guard store.admits(result) else {
                title = nil
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
                LoadingStateView(state: detail.state, retryAction: { Task { await detail.load(store: store) } }, preservesContent: authorizedTitle != nil) {
                    if let title = authorizedTitle {
                        content(title)
                    }
                }
            }
        }
        .navigationTitle(authorizedTitle?.displayTitle ?? String(localized: "Title"))
        .gusTVDetailTitle()
        .gusTVFocusScope()
        .task(id: accessRevision) {
            requestTitle = nil
            reportTitle = nil
            await detail.load(store: store)
        }
        .gusTVTask(item: $requestTitle, onDismiss: { Task { await detail.load(store: store) } }) { title in
            SeerrRequestView(title: title)
        }
        .gusTVTask(item: $reportTitle) { title in
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
            #if !os(tvOS)
                ToolbarItem(placement: .primaryAction) { moreActions }
            #endif
        }
    }

    @ViewBuilder private var moreActions: some View {
        if let title = authorizedTitle, let client = store.client {
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
            } label: { GusToolbarLabel("More Actions", systemImage: "ellipsis") }
                .gusTVToolbarIcon()
                .accessibilityLabel("More Actions")
        }
    }

    private func content(_ title: SeerrTitle) -> some View {
        ScrollView {
            GusTVMediaDetailLayout {
                SeerrArtworkView(
                    path: title.backdropPath,
                    aspectRatio: title.backdropPath == nil ? 2.0 / 3.0 : 16.0 / 9.0,
                    width: "w1280",
                    fallbackURL: SeerrArtwork.url(path: title.posterPath, width: "w780")
                )
                .frame(maxHeight: 520)
                .clipped()
            } summary: {
                identity(title)
                actions(title)
            } details: {
                if let synopsis = title.overview?.trimmedNilIfEmpty {
                    Text(synopsis).font(.body).fixedSize(horizontal: false, vertical: true)
                }
                if detail.mediaType == .tv, let seasons = title.seasons, !seasons.isEmpty {
                    seasonList(title, seasons: seasons)
                }
                if let genres = title.genres, !genres.isEmpty {
                    categoryLinks("Genres", items: genres, kind: detail.mediaType == .movie ? .movieGenres : .tvGenres)
                }
                if detail.mediaType == .movie, let studios = title.productionCompanies, !studios.isEmpty {
                    categoryLinks("Studios", items: studios, kind: .studios)
                }
                if detail.mediaType == .tv, let networks = title.networks, !networks.isEmpty {
                    categoryLinks("Networks", items: networks, kind: .networks)
                }
                if let credits = title.credits, !credits.cast.isEmpty || !credits.crew.isEmpty {
                    SeerrCreditsSection(credits: credits, store: store)
                }
                if detail.mediaType == .movie, let collection = title.collection, let name = collection.name?.trimmedNilIfEmpty {
                    NavigationLink {
                        SeerrCatalogGridView(title: name, source: .collection(collection.id), store: store)
                    } label: { Label(name, systemImage: "rectangle.stack") }
                        .accessibilityIdentifier("Seerr.collection." + String(collection.id))
                }
                SeerrRelatedTitlesSection(
                    heading: String(localized: "Recommendations"),
                    source: .recommendations(detail.mediaType, title.id),
                    linkID: "Seerr.recommendations.seeAll",
                    store: store
                )
                SeerrRelatedTitlesSection(
                    heading: detail.mediaType == .movie ? String(localized: "Similar Movies") : String(localized: "Similar Series"),
                    source: .similar(detail.mediaType, title.id),
                    linkID: "Seerr.similar.seeAll",
                    store: store
                )
            }
            .padding()
            .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .lookToScroll()
        .refreshable { await detail.load(store: store) }
    }

    private func categoryLinks(_ heading: LocalizedStringKey, items: [SeerrCategory], kind: SeerrCategoryKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).font(.headline).accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(item.name) {
                            SeerrCatalogGridView(title: item.name, source: .category(kind, item.id), store: store)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 8)
            }
            .lookToScroll(.horizontal)
            .gusTVRailViewport()
        }
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
            if let availability = title.seerrAvailabilityDescription {
                Text(availability).font(.headline)
            }
        }
    }

    private func actions(_ title: SeerrTitle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if canOpenRequest(title) {
                Button(detail.mediaType == .tv ? "Request Seasons" : "Request", systemImage: "plus.circle") {
                    requestTitle = title
                }
                .gusTVRequestButtonStyle()
                .accessibilityIdentifier("Seerr.request")
                .gusTVFocus(id: "request", section: "seerr-title:" + detail.mediaType.rawValue + ":" + String(title.id), ids: ["request"], initial: true)
            }
            if title.mediaInfo?.status == .available || title.mediaInfo?.status == .partiallyAvailable {
                SeerrPlaybackMatchView(title: title)
            }
            #if os(tvOS)
                moreActions.gusTVToolbarIcon()
            #endif
            SeerrBlocklistAction(title: title) {
                detail.invalidate()
                Task { await detail.load(store: store) }
            }
        }
    }

    private func canOpenRequest(_ title: SeerrTitle) -> Bool {
        SeerrRequestEligibility.canOpenReview(title: title, type: detail.mediaType, user: store.user)
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
                            if let availability = title.mediaInfo?.seasons?.first(where: { $0.seasonNumber == season.seasonNumber })?.status.seerrDescription {
                                Text(availability).font(.subheadline).foregroundStyle(.secondary)
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
                .padding(.vertical, 8)
            }
            .lookToScroll(.horizontal)
            .gusTVRailViewport()
        }
    }
}

private struct SeerrRelatedTitlesSection: View {
    let heading: String
    let source: SeerrCatalogSource
    let linkID: String
    let store: SeerrStore
    @State private var catalog: SeerrCatalogStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let catalog, catalog.isValid(for: store),
               !catalog.items.isEmpty || catalog.hasMore || catalog.errorMessage != nil
            {
                HStack {
                    Text(heading).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if !catalog.items.isEmpty || catalog.hasMore {
                        NavigationLink("See All") {
                            SeerrCatalogGridView(title: heading, source: source, store: store)
                        }
                        .accessibilityLabel(String(localized: "See All \(heading)"))
                        .accessibilityIdentifier(linkID)
                    }
                }
                if let error = catalog.errorMessage {
                    Text(error).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await catalog.load(store: store, refresh: true) } }
                }
                if !catalog.items.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 16) {
                            ForEach(catalog.items.filter { store.admits($0) }, id: \.seerrCatalogID) { item in
                                SeerrResultLink(title: item, store: store)
                                    .frame(width: MediaRailMetrics.itemWidth(for: .poster))
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .lookToScroll(.horizontal)
                    .gusTVRailViewport()
                }
            }
        }
        .task(id: "\(store.revision):\(source):\(store.restrictionRevision)") {
            let catalog = SeerrCatalogStore(source: source)
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
