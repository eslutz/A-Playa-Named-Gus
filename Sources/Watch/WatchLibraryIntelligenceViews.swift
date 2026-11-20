import SwiftUI

@available(watchOS 27, *)
struct WatchLibrarySearchView: View {
    @Environment(SessionStore.self) private var session
    @State private var natural = LibraryNaturalSearchState()
    @State private var naturalMode = false
    @State private var keyword = ""
    @State private var keywordStore: SearchStore?
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var ratingLimit = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false

    private var results: [MediaItem] {
        let rows = naturalMode ? natural.items : keywordStore?.results ?? []
        return rows.filter { ContentRatingGate.admitsStored($0) }
    }

    private var suggestions: [String] {
        var values = [String]()
        if ratingLimit == ContentRatingGate.Limit.off.rawValue {
            values += session.searchHistory.entries.compactMap { entry in
                if case let .typed(value) = entry {
                    value
                } else {
                    nil
                }
            }
        }
        if naturalMode {
            values += [String(localized: "Unwatched sci-fi movies"), String(localized: "Favorite audiobooks")]
        } else if keywordStore?.query == keyword {
            values += GusLibraryMatching.completions(in: results, prefix: keyword)
        }
        return SearchCompletions.matching(naturalMode ? natural.text : keyword, candidates: values)
    }

    var body: some View {
        List {
            if naturalMode || GusIntelligenceModel(session: session).isAvailable {
                Picker("Search Mode", selection: $naturalMode) {
                    Text("Keyword").tag(false)
                    Text("Natural Language").tag(true)
                }
            }
            if naturalMode {
                Text("Watch searches recent items and keyword matches.").font(.footnote)
                if !natural.filters.isEmpty {
                    Text(natural.filters.joined(separator: " · ")).font(.footnote)
                }
            }
            let state = naturalMode ? natural.state : keywordStore?.state ?? .idle
            if state == .loading {
                ProgressView()
            }
            if case let .failed(message) = state {
                Text(message)
                if naturalMode {
                    Button("Search by Title") { naturalMode = false }
                } else {
                    Button("Retry") { Task { await keywordStore?.search(keyword) } }
                }
            }
            if state == .loaded, results.isEmpty {
                Text("No Results")
            }
            ForEach(results, id: \.id) { item in WatchItemRow(item: item) }
            if !naturalMode, let keywordStore, keywordStore.canLoadMore {
                Button("Continue Searching") { Task { await keywordStore.continueSearching() } }
                    .disabled(keywordStore.isLoadingNextPage)
            }
        }
        .navigationTitle("Search Library")
        .searchable(text: naturalMode ? Bindable(natural).text : $keyword, prompt: "Search Library")
        .searchSuggestions {
            ForEach(suggestions, id: \.self) { value in Text(value).searchCompletion(value) }
        }
        .onSubmit(of: .search) {
            if naturalMode {
                natural.submit()
            } else {
                session.searchHistory.record(.typed(keyword))
            }
        }
        .task(id: "\(naturalMode):\(keyword):\(ratingLimit):\(hideUnrated)") {
            guard !naturalMode else { return }
            let allowed: [MediaItemType] = [.movie, .series, .episode, .book, .audioBook, .musicAlbum, .audio]
            let store = keywordStore ?? SearchStore(session: session, limit: 20, includeTypes: allowed)
            keywordStore = store
            if store.query != keyword {
                store.reset()
            }
            guard !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await store.search(keyword)
        }
        .task(id: natural.submission) { await natural.run(session: session) }
        .onChange(of: naturalMode) { natural.resetResults() }
        .onChange(of: ratingLimit) { natural.resetResults() }
        .onChange(of: hideUnrated) { natural.resetResults() }
        .onChange(of: session.intelligencePreferences.cloudEnabled) { natural.resetResults() }
        .navigationDestination(for: WatchItemRoute.self) { route in
            if let item = results.first(where: { $0.id == route.id }) {
                WatchIntelligenceDestination(item: item)
            }
        }
    }
}

@available(watchOS 27, *)
struct WatchForYouView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var ratingLimit = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false
    @State private var shelf = ForYouShelfState()

    private var context: ForYouShelfState.Context {
        let prefs = session.intelligencePreferences
        return .init(cloudEnabled: prefs.cloudEnabled, recommendationsEnabled: prefs.recommendationsEnabled, limit: ratingLimit, hideUnrated: hideUnrated, activityRevision: 0, tasteRevision: session.libraryIntelligence.tasteRevision)
    }

    var body: some View {
        List {
            if context.recommendationsEnabled, shelf.context == context {
                if shelf.isLoading {
                    ProgressView()
                }
                if let error = shelf.error {
                    Text(error)
                    Button("Retry") { Task { await shelf.load(context, session: session, refresh: true) } }
                } else if !shelf.isLoading, shelf.picks.isEmpty {
                    Text("No Recommendations Yet")
                }
                ForEach(shelf.picks, id: \.item.id) { pick in
                    VStack(alignment: .leading) {
                        WatchItemRow(item: pick.item)
                        Text(pick.reason).font(.footnote)
                    }
                }
            }
        }
        .navigationTitle("For You")
        .task(id: context) { await shelf.load(context, session: session) }
        .refreshable { await shelf.load(context, session: session, refresh: true) }
        .navigationDestination(for: WatchItemRoute.self) { route in
            if context.recommendationsEnabled, shelf.context == context,
               let item = shelf.picks.first(where: { $0.item.id == route.id })?.item, ContentRatingGate.admitsStored(item)
            {
                WatchIntelligenceDestination(item: item)
            }
        }
    }
}

private struct WatchIntelligenceDestination: View {
    let item: MediaItem

    var body: some View {
        switch item.type {
        case .musicAlbum: WatchAlbumView(album: item)
        case .series: WatchSeriesSearchEpisodes(series: item)
        default: WatchItemActionsView(item: item)
        }
    }
}

private struct WatchSeriesSearchEpisodes: View {
    @Environment(SessionStore.self) private var session
    let series: MediaItem
    @State private var episodes: [MediaItem] = []
    @State private var state: LoadState = .idle

    var body: some View {
        LoadingStateView(state: state, isEmpty: episodes.isEmpty, emptyTitle: "No Episodes", emptySymbol: "tv", retryAction: { Task { await load() } }) {
            List(episodes, id: \.id) { item in
                NavigationLink(item.displayTitle) { WatchItemActionsView(item: item) }
            }
        }
        .navigationTitle(series.displayTitle)
        .task { await load() }
    }

    private func load() async {
        guard let id = series.id, session.isActive else { return }
        state = .loading
        do {
            let page = try await session.mediaProvider.items(query: .init(parentID: id, includeTypes: [.episode], startIndex: 0, limit: 30, isRecursive: true))
            try Task.checkCancellation()
            guard session.isActive else { return }
            episodes = ContentRatingGate.filter(page.items)
            state = .loaded
        } catch {
            guard !Task.isCancelled, session.isActive else { return }
            let failure = GusError(from: error)
            failure.handleIfUnauthorized(session: session)
            state = .failed(failure.localizedDescription)
        }
    }
}
