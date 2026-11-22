import SwiftUI

struct GlobalSearchContent: View {
    @Environment(RootNavigationState.self) private var root
    @Environment(SessionStore.self) private var session
    @FocusState private var fieldFocused: Bool
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif

    var body: some View {
        if session.mediaProvider.capabilities.supportsSearch {
            fieldContainer
        } else {
            ContentUnavailableView("Search Unavailable", systemImage: "magnifyingglass")
        }
    }

    @ViewBuilder private var fieldContainer: some View {
        #if os(iOS)
            if !DeviceIdentity.usesIPadPresentation || widthClass == .compact {
                // The role-based iPhone tab hosts its own native search field.
                GlobalSearchResultsContent()
            } else {
                searchableResults
            }
        #else
            searchableResults
        #endif
    }

    @ViewBuilder private var searchableResults: some View {
        let text = Binding(get: { root.globalSearch.text }, set: { root.editSearchText($0, naturalSearchEnabled: session.intelligenceAccess.usesNaturalSearch) })
        #if os(tvOS)
            GlobalSearchResultsContent()
                .modifier(LibrarySearchFieldBehavior(search: root.globalSearch))
                .searchable(text: text, prompt: Text("Search Library"))
                .onSubmit(of: .search) { root.globalSearch.submit(naturalSearchEnabled: false, history: session.searchHistory) }
        #else
            GlobalSearchResultsContent()
                .gusSearchable(
                    text: text,
                    isPresented: Bindable(root.globalSearch.typed).isPresented,
                    isFocused: $fieldFocused,
                    prompt: Text("Search Library")
                )
                .modifier(LibrarySearchFieldBehavior(search: root.globalSearch))
        #endif
    }
}

private struct GlobalSearchResultsContent: View {
    @Environment(RootNavigationState.self) private var root
    @Environment(SessionStore.self) private var session
    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(\.isSearching) private var isSearching
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif

    private var navigationTitle: String {
        #if os(iOS)
            let typed = root.globalSearch.typed
            if widthClass == .compact, !typed.isPresented {
                let query = root.globalSearch.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    return query
                }
            }
        #endif
        return String(localized: "Search")
    }

    var body: some View {
        ZStack {
            if session.intelligenceAccess.usesNaturalSearch, !root.globalSearch.displaysKeywords, !root.globalSearch.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                NaturalLibraryResults(search: root.globalSearch)
            } else if !root.globalSearch.typed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                OwnedSearchResults(state: root.globalSearch.typed)
            } else {
                RecentSearchesView { root.replaySearch($0, naturalSearchEnabled: session.intelligenceAccess.usesNaturalSearch) }
            }
        }
        .navigationTitle(navigationTitle)
        .safeAreaInset(edge: .top, spacing: 0) {
            LibraryDraftSuggestionRows()
        }
        .toolbar {
            if !root.globalSearch.text.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear Results") {
                        root.clearSearchResults {
                            if isSearching {
                                dismissSearch()
                            }
                        }
                    }
                    .accessibilityIdentifier("Search.clearResults")
                }
            }
        }
    }
}

private struct LibraryDraftSuggestionRows: View {
    @Environment(\.librarySearchDraftSuggestions) private var values
    @Environment(RootNavigationState.self) private var root
    @Environment(SessionStore.self) private var session

    var body: some View {
        SearchDraftSuggestions(values: values) {
            root.editSearchText($0, naturalSearchEnabled: session.intelligenceAccess.usesNaturalSearch)
        }
    }
}

struct RelatedResultsDestination: View {
    @Environment(RootNavigationState.self) private var navigation
    @Environment(SessionStore.self) private var session
    let id: UUID

    var body: some View {
        if let results = navigation.relatedResults[id] {
            content(results)
                .navigationTitle(results.target.name)
                .task(id: results.lookupID) { await results.resolve(session: session) }
        }
    }

    @ViewBuilder private func content(_ results: RelatedSearchResults) -> some View {
        if let target = results.resolved {
            LibraryGridView(scope: .related(target), searchResults: results)
        } else if results.unavailable {
            ContentUnavailableView("No Matching Credit or Tag", systemImage: results.target.kind.systemImage)
        } else if let message = results.errorMessage {
            ContentUnavailableView {
                Label("Couldn't Load Results", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry", action: results.retry)
            }
        } else {
            ProgressView().accessibilityIdentifier("Search.resolvingTag")
        }
    }
}
