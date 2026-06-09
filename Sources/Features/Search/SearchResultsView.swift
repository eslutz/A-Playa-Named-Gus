import SwiftUI

struct SearchResultsView: View {
    @Environment(SessionStore.self) private var session
    let store: SearchStore

    var body: some View {
        LoadingStateView(
            state: store.state,
            isEmpty: store.results.isEmpty,
            emptyTitle: "No Results",
            emptySymbol: "magnifyingglass"
        ) {
            ScrollView {
                LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: PosterGrid.spacing) {
                    ForEach(store.results, id: \.id) { item in
                        NavigationLink(value: ItemRef(item: item)) {
                            PosterCard(
                                item: item,
                                imageURL: session.mediaProvider.primaryImageURL(for: item, context: .posterGrid)
                            )
                        }
                        .posterNavigationStyle()
                        .task {
                            await store.loadMoreIfNeeded(currentItem: item)
                        }
                    }

                    if store.isLoadingNextPage {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .lookToScroll()
        }
    }
}

struct SearchRootView<Content: View>: View {
    @Environment(AppNavigationModel.self) private var navigation
    @Environment(SessionStore.self) private var session
    @State private var store: SearchStore?
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool

    @ViewBuilder var content: () -> Content

    var body: some View {
        searchContent
            .task {
                guard session.mediaProvider.capabilities.supportsSearch, store == nil else { return }
                store = SearchStore(session: session)
            }
            .onChange(of: navigation.searchFocusRequest) { _, request in
                guard session.mediaProvider.capabilities.supportsSearch, request > 0 else { return }
                isSearchPresented = true
                isSearchFocused = true
            }
    }

    @ViewBuilder
    private var searchContent: some View {
        if session.mediaProvider.capabilities.supportsSearch {
            searchSurface
                .gusSearchable(
                    text: $searchText,
                    isPresented: $isSearchPresented,
                    isFocused: $isSearchFocused,
                    prompt: Text("Search Library")
                )
                .searchDebounce(text: $searchText, store: $store)
        } else {
            content()
        }
    }

    private var searchSurface: some View {
        Group {
            if isSearching {
                if let store {
                    SearchResultsView(store: store)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                content()
            }
        }
    }

    private var isSearching: Bool {
        session.mediaProvider.capabilities.supportsSearch
            && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Shared debounce modifier

private extension View {
    /// Debounces a `.searchable` text field by 300 ms and drives a `SearchStore`.
    ///
    /// Centralised here so every platform root gets consistent debounce delay,
    /// consistent trimming, and no duplicated `catch` branches.
    func searchDebounce(text: Binding<String>, store: Binding<SearchStore?>) -> some View {
        task(id: text.wrappedValue) {
            let trimmed = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let store = store.wrappedValue else { return }

            guard !trimmed.isEmpty else {
                store.reset()
                return
            }

            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return // cancelled by a new keystroke; nothing to do
            }

            guard !Task.isCancelled else { return }
            await store.search(trimmed)
        }
    }
}
