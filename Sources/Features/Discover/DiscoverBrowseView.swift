import SwiftUI

/// Discover owns its search scope while each supported feed loads and retries independently.
struct DiscoverBrowseView: View {
    @Environment(AppNavigationModel.self) private var navigation
    @FocusState private var searchFocused: Bool
    @State private var searchPresented = false
    let store: SeerrStore
    let searchOnly: Bool
    @State private var feeds: [SeerrCatalogStore] = []
    @State private var enabledFeeds: [SeerrDiscoveryFeed] = []
    @State private var feedState: LoadState = .idle
    @State private var feedError: String?
    @State private var feedsRevision: String?
    @State private var query = ""
    @State private var searchCatalog: SeerrCatalogStore?
    @State private var submittedSearch = UUID()
    @State private var submitsImmediately = false
    @State private var scrollID: String?
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimitRawValue = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnratedContent = false

    init(store: SeerrStore, searchOnly: Bool = false) {
        self.searchOnly = searchOnly
        self.store = store
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
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
            state: feedsRevision == accessRevision ? (feeds.isEmpty ? feedState : .loaded) : .loading,
            isEmpty: feeds.isEmpty,
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
                    if let trending = feeds.first(where: { $0.source == .feed(.trending) }), trending.isValid(for: store),
                       let hero = trending.items.first(where: { $0.backdropPath != nil && store.admits($0) })
                    {
                        SeerrDiscoveryHero(title: hero, store: store)
                            .id("discover.hero")
                    }
                    if let feedError {
                        Text(feedError).foregroundStyle(.secondary)
                        Button("Retry Feeds") { Task { await loadFeeds() } }
                    }
                    ForEach(Array(zip(enabledFeeds, feeds)), id: \.0) { feed, catalog in
                        SeerrDiscoveryShelf(feed: feed, catalog: catalog, store: store)
                            .id(feed.rawValue)
                            .task(id: accessRevision) { await catalog.load(store: store) }
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
            .refreshable {
                await loadFeeds()
                // Each feed keeps its own successful content and failure state.
                for catalog in feeds {
                    await catalog.load(store: store, refresh: true)
                }
            }
        }
    }

    @MainActor private func loadFeeds() async {
        let expected = accessRevision
        if feedsRevision != expected {
            feeds = []
            enabledFeeds = []
        }
        feedsRevision = expected
        feedState = .loading
        feedError = nil
        do {
            let sliders = try await store.requireClient().discoverSliders()
            guard !Task.isCancelled, accessRevision == expected else { return }
            var seen: Set<SeerrDiscoveryFeed> = []
            let selected = sliders.sorted { $0.order < $1.order }.compactMap(\.supportedFeed)
                .filter { seen.insert($0).inserted }
            let previous = feeds
            enabledFeeds = selected
            feeds = selected.map { feed in
                previous.first(where: { $0.source == .feed(feed) }) ?? SeerrCatalogStore(source: .feed(feed))
            }
            feedState = .loaded
        } catch {
            guard !Task.isCancelled, accessRevision == expected else { return }
            store.handle(error)
            guard accessRevision == expected else { return }
            feedState = feeds.isEmpty ? .failed(error.localizedDescription) : .loaded
            feedError = error.localizedDescription
        }
    }
}

private struct SeerrDiscoveryHero: View {
    let title: SeerrTitle
    let store: SeerrStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        #if os(tvOS)
            GusTVMediaDetailLayout {
                SeerrArtworkView(path: title.backdropPath, aspectRatio: 16.0 / 9.0, width: "w1280")
            } summary: {
                heroText
            } details: {
                EmptyView()
            }
        #else
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    SeerrArtworkView(path: title.backdropPath, aspectRatio: 16.0 / 9.0, width: "w1280")
                    heroText
                }
            } else {
                SeerrArtworkView(path: title.backdropPath, aspectRatio: 16.0 / 9.0, width: "w1280")
                    .overlay(alignment: .bottomLeading) {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                            heroText.padding(20).foregroundStyle(.white)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
            }
        #endif
    }

    private var heroText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.displayTitle).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
            Text(title.seerrIdentityDescription).font(.subheadline)
            NavigationLink {
                SeerrTitleDetailView(title: title, store: store)
            } label: { Label("View Title", systemImage: "info.circle") }
                .gusTVRequestButtonStyle()
                .accessibilityIdentifier("Seerr.hero." + (title.mediaType?.rawValue ?? "unknown") + "." + String(title.id))
        }
    }
}

private struct SeerrDiscoveryShelf: View {
    let feed: SeerrDiscoveryFeed
    let catalog: SeerrCatalogStore
    let store: SeerrStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(feed.seerrTitle).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink("See All") {
                    SeerrCatalogGridView(title: feed.seerrTitle, source: .feed(feed), store: store)
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
                    Button("Retry Shelf") { Task { await catalog.load(store: store, refresh: true) } }
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
                    .tvFocusSection()
                    .padding(.vertical, 8)
                }
                .lookToScroll(.horizontal)
                if let error = catalog.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("Retry Shelf") { Task { await catalog.load(store: store, refresh: true) } }
                }
            }
        }
    }
}
