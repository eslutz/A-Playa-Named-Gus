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
                    Button("Search by Title") { search.naturalMode = false }
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
                        Button("Search by Title") { search.naturalMode = false }
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
        .task(id: natural.submission) { await natural.run(session: session) }
        .onChange(of: restriction) { natural.resetResults() }
        .onChange(of: hideUnrated) { natural.resetResults() }
        .onChange(of: session.intelligencePreferences.cloudEnabled) { natural.resetResults() }
    }
}

/// Attach to the view owning .searchable, including compact iPhone's role-based tab.
struct LibrarySearchFieldBehavior: ViewModifier {
    @Environment(SessionStore.self) private var session
    #if os(tvOS)
        @Environment(RootNavigationState.self) private var root
    #endif
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var restriction = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false
    @State private var catalogTerms: [String] = []
    @State private var catalogKey: String?
    let search: GlobalSearchSession

    private var requestKey: String {
        "\(search.naturalMode):\(restriction):\(hideUnrated):\(search.text)"
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
        if let store = search.typed.store, store.query == search.text, !search.naturalMode {
            candidates += GusLibraryMatching.completions(in: ContentRatingGate.filter(store.results), prefix: search.text)
        }
        if catalogKey == requestKey {
            candidates += catalogTerms
        }
        if search.naturalMode {
            candidates += [String(localized: "Unwatched sci-fi movies"), String(localized: "Favorite audiobooks")]
        }
        return SearchCompletions.matching(search.text, candidates: candidates)
    }

    @ViewBuilder private func fieldSuggestions(_ content: Content) -> some View {
        #if os(tvOS)
            content.gusTVSearchCompletions(terms, select: root.editSearchText)
        #else
            content.searchSuggestions {
                ForEach(terms, id: \.self) { value in
                    Text(value).searchCompletion(value)
                }
            }
            .onSubmit(of: .search) { search.submit(to: session.searchHistory) }
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
