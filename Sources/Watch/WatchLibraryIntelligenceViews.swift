import SwiftUI

struct WatchLibrarySearchView: View {
    @Environment(SessionStore.self) private var session
    @State private var natural = LibraryNaturalSearchState()
    @State private var draftMode = SearchDraftMode.natural
    @State private var keywordStore: SearchStore?
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var ratingLimit = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false

    private var prefersNatural: Bool {
        session.intelligenceAccess.usesNaturalSearch
    }

    private var naturalMode: Bool {
        prefersNatural && draftMode == .natural
    }

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
        } else if keywordStore?.query == natural.text.trimmingCharacters(in: .whitespacesAndNewlines) {
            values += GusLibraryMatching.completions(in: results, prefix: natural.text)
        }
        return SearchCompletions.matching(natural.text, candidates: values)
    }

    var body: some View {
        List {
            if prefersNatural, !suggestions.isEmpty {
                Section { suggestionButtons }
            }
            if naturalMode {
                Text("Watch searches recent items and keyword matches.").font(.footnote)
                if !natural.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Search by Keyword", action: useKeyword)
                }
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
                if !naturalMode {
                    Button("Retry") { Task { await keywordStore?.search(natural.text) } }
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
        .searchable(text: Binding(get: { natural.text }, set: { edit($0) }), prompt: "Search Library")
        .searchSuggestions {
            if !prefersNatural {
                suggestionButtons
            }
        }
        .onSubmit(of: .search) {
            if prefersNatural {
                draftMode = .natural
                natural.submit()
            } else {
                session.searchHistory.record(.typed(natural.text))
            }
        }
        .task(id: "\(naturalMode):\(natural.text):\(ratingLimit):\(hideUnrated)") {
            guard !naturalMode else {
                keywordStore?.cancelForegroundLoad()
                return
            }
            let keyword = natural.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let allowed: [MediaItemType] = [.movie, .series, .episode, .book, .audioBook, .musicAlbum, .audio]
            let store = keywordStore ?? SearchStore(session: session, limit: 20, includeTypes: allowed)
            keywordStore = store
            if store.query != keyword {
                store.reset()
            }
            guard !keyword.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await store.search(keyword)
        }
        .task(id: natural.submission) {
            guard naturalMode else { return }
            await natural.run(session: session, onKeyword: useKeyword)
        }
        .onChange(of: prefersNatural) { _, _ in
            natural.resetResults()
            draftMode = natural.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .natural : .keywordUntilSubmit
        }
        .onChange(of: ratingLimit) { natural.resetResults() }
        .onChange(of: hideUnrated) { natural.resetResults() }
        .onChange(of: session.intelligencePreferences.cloudEnabled) { _, enabled in
            if !enabled {
                natural.resetResults()
            }
        }
        .navigationDestination(for: WatchItemRoute.self) { route in
            if let item = results.first(where: { $0.id == route.id }) {
                WatchIntelligenceDestination(item: item)
            }
        }
    }

    private func useKeyword() {
        natural.resetResults()
        draftMode = .keyword
    }

    private var suggestionButtons: some View {
        ForEach(suggestions, id: \.self) { value in
            Button { edit(value) } label: { Text(verbatim: value) }
        }
    }

    private func edit(_ draft: String) {
        guard draft != natural.text else { return }
        draftMode.edit(draft, naturalSearchEnabled: prefersNatural)
        natural.text = draft
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
