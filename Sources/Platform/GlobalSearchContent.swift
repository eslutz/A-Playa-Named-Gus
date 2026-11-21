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
            if widthClass == .compact {
                // The role-based iPhone tab hosts its own native search field.
                results
            } else {
                searchableResults
            }
        #elseif os(tvOS)
            if root.globalSearch.related != nil {
                // The tvOS search controller brings its keyboard into focus as
                // soon as it appears. A metadata selection already supplies the query.
                results
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
            results
                .modifier(LibrarySearchFieldBehavior(search: root.globalSearch))
                .searchable(text: text, prompt: Text("Search Library"))
                .onSubmit(of: .search) { root.globalSearch.submit(naturalSearchEnabled: false, history: session.searchHistory) }
        #else
            results
                .gusSearchable(
                    text: text,
                    isPresented: Bindable(root.globalSearch.typed).isPresented,
                    isFocused: $fieldFocused,
                    prompt: Text("Search Library")
                )
                .modifier(LibrarySearchFieldBehavior(search: root.globalSearch))
        #endif
    }

    private var navigationTitle: String {
        if let related = root.globalSearch.related {
            return related.target.name
        }
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

    private var results: some View {
        Group {
            if let related = root.globalSearch.related {
                RelatedResultsView(results: related).id(ObjectIdentifier(related))
            } else if session.intelligenceAccess.usesNaturalSearch, !root.globalSearch.displaysKeywords, !root.globalSearch.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                NaturalLibraryResults(search: root.globalSearch)
            } else if !root.globalSearch.typed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                OwnedSearchResults(state: root.globalSearch.typed)
                    .id(ObjectIdentifier(root.globalSearch.typed))
            } else {
                RecentSearchesView(onSelect: root.replaySearch)
            }
        }
        .navigationTitle(navigationTitle)
        .safeAreaInset(edge: .top, spacing: 0) {
            LibraryDraftSuggestionRows()
        }
        .toolbar {
            if root.hasSearchReturn {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back to Detail", systemImage: "chevron.backward", action: root.backToSearchDetail)
                        .accessibilityIdentifier("Search.backToDetail")
                        .gusTVToolbarIcon()
                }
            }
            if root.globalSearch.related != nil || !root.globalSearch.text.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Close Results", systemImage: "xmark", action: root.closeSearchResults)
                        .accessibilityIdentifier("Search.closeResults")
                        .gusTVToolbarIcon()
                }
            }
        }
        .modifier(SearchExitCommand(root: root))
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

private struct RelatedResultsView: View {
    let results: RelatedSearchResults

    var body: some View {
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

private struct SearchExitCommand: ViewModifier {
    let root: RootNavigationState

    func body(content: Content) -> some View {
        #if os(tvOS)
            if root.hasSearchReturn, root.paths[RootNavigationState.searchID]?.isEmpty != false {
                content.onExitCommand(perform: root.backToSearchDetail)
            } else {
                content
            }
        #else
            content
        #endif
    }
}
