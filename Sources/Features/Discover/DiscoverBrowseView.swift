import SwiftUI

/// Discover owns its search scope while each supported feed loads and retries independently.
struct DiscoverBrowseView: View {
    @Environment(AppNavigationModel.self) private var navigation
    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var searchFocused: Bool
    @State private var searchPresented = false
    let store: SeerrStore
    let searchOnly: Bool
    @State private var shelves: [SeerrHomeShelf] = []
    @State private var feedState: LoadState = .idle
    @State private var feedError: String?
    @State private var feedsRevision: String?
    @State private var query = ""
    @State private var searchCatalog: SeerrCatalogStore?
    @State private var submittedSearch = UUID()
    @State private var submitsImmediately = false
    @State private var scrollID: String?
    @State private var today = Calendar.current.startOfDay(for: .now)
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimitRawValue = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnratedContent = false

    init(store: SeerrStore, searchOnly: Bool = false) {
        self.searchOnly = searchOnly
        self.store = store
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trending: SeerrCatalogStore? {
        for case let .titles(.trending, catalog) in shelves {
            return catalog
        }
        return nil
    }

    private var accessRevision: String {
        "\(store.revision):\(contentLimitRawValue):\(hideUnratedContent)"
    }

    private var searchRevision: String {
        "\(accessRevision):\(normalizedQuery):\(submittedSearch)"
    }

    var body: some View {
        Group {
            if !normalizedQuery.isEmpty {
                if let searchCatalog, searchCatalog.source == .search(normalizedQuery) {
                    SeerrCatalogResults(catalog: searchCatalog, store: store)
                } else {
                    ProgressView("Searching Discover")
                }
            } else if searchOnly {
                ContentUnavailableView("Search Seerr", systemImage: "magnifyingglass", description: Text("Find movies and shows to request."))
            } else {
                browse
            }
        }
        .navigationTitle(searchOnly ? "Search Seerr" : "Discover")
        .gusSeerrSearch(text: $query, isPresented: $searchPresented, isFocused: $searchFocused, enabledOnTV: searchOnly)
        .onChange(of: navigation.searchFocusRequest, initial: true) { _, request in
            guard request > 0 else { return }
            searchPresented = true
            searchFocused = true
        }
        .onSubmit(of: .search) {
            submitsImmediately = true
            submittedSearch = UUID()
        }
        .task(id: accessRevision) { await loadFeeds() }
        .task(id: searchRevision) {
            guard !normalizedQuery.isEmpty else {
                searchCatalog = nil
                return
            }
            let catalog = SeerrCatalogStore(source: .search(normalizedQuery))
            searchCatalog = catalog
            let shouldDebounce = !submitsImmediately
            submitsImmediately = false
            if shouldDebounce {
                do { try await Task.sleep(for: .milliseconds(300)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            await catalog.load(store: store)
        }
        .onChange(of: store.revision) { _, _ in scrollID = nil }
    }

    private var browse: some View {
        LoadingStateView(
            state: feedsRevision == accessRevision ? (shelves.isEmpty ? feedState : .loaded) : .loading,
            isEmpty: shelves.isEmpty,
            emptyTitle: String(localized: "No Discover Feeds"),
            emptySymbol: "rectangle.stack",
            retryAction: { Task { await loadFeeds() } }
        ) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 32) {
                    #if os(tvOS)
                        HStack(spacing: 32) {
                            NavigationLink { DiscoverBrowseView(store: store, searchOnly: true) } label: { Label("Search Seerr", systemImage: "magnifyingglass") }
                            SeerrRequestHistoryLink()
                            NavigationLink { SeerrSettingsView() } label: { Label("Seerr Settings", systemImage: "gearshape") }
                            if store.user?.canManageRequests == true {
                                NavigationLink("Manage Requests") { SeerrRequestsView(managing: true) }
                            }
                        }.focusSection().padding(.vertical, 24)
                    #endif
                    if let trending, trending.isValid(for: store) {
                        if let featured = trending.featuredTrending {
                            SeerrTrendingCarousel(
                                titles: featured.titles.filter { store.admits($0) },
                                day: calendar.startOfDay(for: featured.requestedAt),
                                store: store,
                                canSaveSelection: featured.canSaveSelection
                            )
                            .id("discover.hero")
                        }
                        if let error = trending.featuredError {
                            Text(error).foregroundStyle(.secondary)
                            Button("Retry Trending") {
                                Task { await trending.loadTrending(for: .now, calendar: calendar, store: store, refresh: true) }
                            }
                        }
                    }
                    if let feedError {
                        Text(feedError).foregroundStyle(.secondary)
                        Button("Retry Feeds") { Task { await loadFeeds() } }
                    }
                    ForEach(shelves, id: \.id) { shelf in
                        Group {
                            switch shelf {
                            case let .titles(feed, catalog):
                                SeerrDiscoveryShelf(feed: feed, catalog: catalog, store: store) { await shelf.load(store: store, refresh: true) }
                            case let .categories(directory): SeerrCategoryShelf(directory: directory, store: store)
                            }
                        }
                        .id(shelf.id)
                        .task(id: accessRevision) {
                            if shelf.section != .titles(.trending) {
                                await shelf.load(store: store)
                            }
                        }
                    }
                    Text("Metadata and artwork provided by TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .scrollTargetLayout()
                .padding()
                .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $scrollID)
            .lookToScroll()
            // The header needs Trending even when the server puts its shelf well below the viewport.
            .task(id: TrendingLoadKey(catalog: trending.map(ObjectIdentifier.init), day: today, isActive: scenePhase == .active)) {
                if scenePhase == .active {
                    await trending?.loadTrending(for: today, calendar: calendar, store: store)
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    today = calendar.startOfDay(for: .now)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = calendar.startOfDay(for: .now) }
            .refreshable {
                await loadFeeds()
                // Each feed keeps its own successful content and failure state.
                for shelf in shelves {
                    await shelf.load(store: store, refresh: true)
                }
            }
        }
    }

    @MainActor private func loadFeeds() async {
        let expected = accessRevision
        if feedsRevision != expected {
            shelves = []
        }
        feedsRevision = expected
        feedState = .loading
        feedError = nil
        do {
            let sliders = try await store.requireClient().discoverSliders()
            guard !Task.isCancelled, accessRevision == expected else { return }
            var seen: Set<SeerrDiscoverSection> = []
            let selected = sliders.sorted { $0.order < $1.order }.compactMap(\.supportedSection)
                .filter { seen.insert($0).inserted }
            shelves = selected.map { section in
                shelves.first(where: { $0.section == section }) ?? SeerrHomeShelf(section)
            }
            feedState = .loaded
        } catch {
            guard !Task.isCancelled, accessRevision == expected else { return }
            store.handle(error)
            guard accessRevision == expected else { return }
            feedState = shelves.isEmpty ? .failed(error.localizedDescription) : .loaded
            feedError = error.localizedDescription
        }
    }
}

private struct TrendingLoadKey: Equatable {
    let catalog: ObjectIdentifier?
    let day: Date
    let isActive: Bool
}

@MainActor private enum SeerrHomeShelf {
    case titles(SeerrDiscoveryFeed, SeerrCatalogStore)
    case categories(SeerrCategoryDirectory)

    init(_ section: SeerrDiscoverSection) {
        switch section {
        case let .titles(feed): self = .titles(feed, SeerrCatalogStore(source: .feed(feed)))
        case let .categories(kind): self = .categories(SeerrCategoryDirectory(kind: kind))
        }
    }

    var section: SeerrDiscoverSection {
        switch self {
        case let .titles(feed, _): .titles(feed)
        case let .categories(directory): .categories(directory.kind)
        }
    }

    var id: String {
        switch self {
        case let .titles(feed, _): feed.rawValue
        case let .categories(directory): directory.kind.rawValue
        }
    }

    func load(store: SeerrStore, refresh: Bool = false) async {
        switch self {
        case let .titles(.trending, catalog): await catalog.loadTrending(for: .now, calendar: .autoupdatingCurrent, store: store, refresh: refresh)
        case let .titles(_, catalog): await catalog.load(store: store, refresh: refresh)
        case let .categories(directory): await directory.load(store: store, refresh: refresh)
        }
    }
}

private struct SeerrDiscoveryShelf: View {
    let feed: SeerrDiscoveryFeed
    let catalog: SeerrCatalogStore
    let store: SeerrStore
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(feed.seerrTitle).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink("See All") {
                    SeerrCatalogGridView(title: feed.seerrTitle, source: .feed(feed), store: store, featuredCatalog: feed == .trending ? catalog : nil)
                }
                .accessibilityIdentifier("Seerr.feed.\(feed.rawValue).showAll")
            }
            .tvFocusSection()
            if catalog.state == .loading && catalog.items.isEmpty {
                ProgressView("Loading titles")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if catalog.items.isEmpty {
                if case let .failed(message) = catalog.state {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    Button("Retry Shelf") { Task { await retry() } }
                } else if catalog.state == .loaded {
                    Text("No titles in this feed").foregroundStyle(.secondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: MediaRailMetrics.spacing(for: .poster)) {
                        ForEach(catalog.items.filter { store.admits($0) }, id: \.seerrCatalogID) { title in
                            SeerrResultLink(title: title, store: store)
                                .frame(width: MediaRailMetrics.itemWidth(for: .poster))
                        }
                    }
                    .padding(.vertical, 8)
                }
                .lookToScroll(.horizontal)
                .gusTVRailViewport()
                if let error = catalog.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("Retry Shelf") { Task { await retry() } }
                }
            }
        }
    }
}
