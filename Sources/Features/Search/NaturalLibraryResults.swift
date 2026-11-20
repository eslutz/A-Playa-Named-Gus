import SwiftUI

struct NaturalLibraryResults: View {
    @Environment(SessionStore.self) private var session
    let search: GlobalSearchSession
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var restriction = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false

    var body: some View {
        let natural = search.natural
        Group {
            switch natural.state {
            case .idle:
                ContentUnavailableView("Natural Language", systemImage: "magnifyingglass", description: Text("Describe what you want to find, then submit your search."))
            case .loading:
                ProgressView(session.libraryIntelligence.isIndexing ? String(localized: "Indexing Library") : String(localized: "Searching Library"))
            case let .failed(message):
                ContentUnavailableView {
                    Label("Search Unavailable", systemImage: "magnifyingglass")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { natural.submit() }
                }
            case .loaded:
                List {
                    if !natural.filters.isEmpty {
                        Section("Applied Filters") {
                            Text(natural.filters.joined(separator: " · "))
                        }
                    }
                    if natural.items.isEmpty {
                        Text("No accessible title has metadata confirming these requirements.")
                    }
                    if natural.items.count == 60 {
                        Text("Showing the first 60 matches.").font(.footnote)
                    }
                    ForEach(ContentRatingGate.filter(natural.items), id: \.id) { item in
                        MediaItemNavigationLink(item: item) { MediaLibraryRow(item: item) }
                            .mediaItemContextMenu(item: item)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Search by Keyword") { search.searchByKeyword(recordingIn: session.searchHistory) }
                .accessibilityIdentifier("Search.byKeyword")
                .padding(.vertical, 8)
        }
        .task(id: natural.submission) {
            await natural.run(session: session) { search.searchByKeyword() }
        }
        .onChange(of: restriction) { natural.resetResults() }
        .onChange(of: hideUnrated) { natural.resetResults() }
        .onChange(of: session.intelligencePreferences.cloudEnabled) { _, allowed in
            if !allowed {
                natural.resetResults()
            }
        }
    }
}

/// Attach to the view owning .searchable, including compact iPhone's role-based tab.
struct LibrarySearchFieldBehavior: ViewModifier {
    @Environment(SessionStore.self) private var session
    @Environment(RootNavigationState.self) private var root
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var restriction = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false
    @State private var catalogTerms: [String] = []
    @State private var catalogKey: String?
    let search: GlobalSearchSession

    private var naturalMode: Bool {
        session.intelligenceAccess.usesNaturalSearch && !search.displaysKeywords
    }

    private var requestKey: String {
        "\(naturalMode):\(restriction):\(hideUnrated):\(search.text)"
    }

    private var terms: [String] {
        guard search.related == nil else { return [] }
        var candidates: [String] = []
        if restriction == ContentRatingGate.Limit.off.rawValue {
            candidates = session.searchHistory.entries.compactMap {
                if case let .typed(value) = $0 {
                    value
                } else {
                    nil
                }
            }
        }
        if let store = search.typed.store, store.query == search.text, !naturalMode {
            candidates += GusLibraryMatching.completions(in: ContentRatingGate.filter(store.results), prefix: search.text)
        }
        if catalogKey == requestKey {
            candidates += catalogTerms
        }
        if naturalMode {
            candidates += [String(localized: "Unwatched sci-fi movies"), String(localized: "Favorite audiobooks")]
        }
        return SearchCompletions.matching(search.text, candidates: candidates)
    }

    @ViewBuilder private func fieldSuggestions(_ content: Content) -> some View {
        #if os(tvOS)
            content.gusTVSearchCompletions(terms, inResults: search.typed.store?.results.isEmpty == false && !naturalMode, select: { root.editSearchText($0) })
        #else
            content.searchSuggestions {
                ForEach(terms, id: \.self) { value in
                    Button {
                        root.editSearchText(value, naturalSearchEnabled: session.intelligenceAccess.usesNaturalSearch)
                    } label: {
                        Text(verbatim: value)
                    }
                }
            }
            .onSubmit(of: .search) { search.submit(naturalSearchEnabled: session.intelligenceAccess.usesNaturalSearch, history: session.searchHistory) }
        #endif
    }

    func body(content: Content) -> some View {
        fieldSuggestions(content)
            .task(id: requestKey) {
                let key = requestKey
                let prefix = search.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !prefix.isEmpty, search.related == nil else { return }
                do {
                    try await Task.sleep(for: .milliseconds(200))
                    let terms = try await session.libraryIntelligence.suggestions(prefix: prefix)
                    try Task.checkCancellation()
                    guard session.isActive, key == requestKey else { return }
                    catalogTerms = terms
                    catalogKey = key
                } catch {
                    if !Task.isCancelled {
                        catalogTerms = []
                        catalogKey = nil
                    }
                }
            }
    }
}
