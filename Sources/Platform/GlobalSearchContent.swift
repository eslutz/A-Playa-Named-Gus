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

    private var searchableResults: some View {
        results
            .gusSearchable(
                text: Binding(get: { root.globalSearch.typed.text }, set: { root.editSearchText($0) }),
                isPresented: Bindable(root.globalSearch.typed).isPresented,
                isFocused: $fieldFocused,
                prompt: Text("Search Library")
            )
            .onSubmit(of: .search) { root.globalSearch.typed.submitSearch(to: session.searchHistory) }
    }

    private var results: some View {
        Group {
            if let related = root.globalSearch.related {
                RelatedResultsView(results: related).id(ObjectIdentifier(related))
            } else if !root.globalSearch.typed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                OwnedSearchResults(state: root.globalSearch.typed)
                    .id(ObjectIdentifier(root.globalSearch.typed))
            } else {
                RecentSearchesView(onSelect: root.replaySearch)
            }
        }
        .navigationTitle(root.globalSearch.related?.target.name ?? String(localized: "Search"))
        .toolbar {
            if root.hasSearchReturn {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back to Detail", systemImage: "chevron.backward", action: root.backToSearchDetail)
                        .accessibilityIdentifier("Search.backToDetail")
                        .gusTVToolbarIcon()
                }
            }
            if root.globalSearch.related != nil || !root.globalSearch.typed.text.isEmpty {
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
