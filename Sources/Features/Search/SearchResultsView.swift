import SwiftUI

struct SearchResultsView: View {
    @Environment(RootNavigationState.self) private var rootState
    @Environment(SessionStore.self) private var session
    let store: SearchStore

    var body: some View {
        LoadingStateView(
            state: store.state,
            isEmpty: store.results.isEmpty && !store.canLoadMore,
            emptyTitle: "No Results",
            emptySymbol: "magnifyingglass",
            retryAction: { Task { await store.search(store.query) } }
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
                        .id(ItemRef(item: item).id)
                        .posterNavigationStyle()
                        .mediaItemContextMenu(item: item)
                        .gusTVFocus(id: ItemRef(item: item).id, section: "search:" + rootState.selectedSectionID + ":" + store.query, ids: store.results.map { ItemRef(item: $0).id }, item: item)
                        .task {
                            await store.loadMoreIfNeeded(currentItem: item)
                        }
                    }

                    if let error = store.pageError {
                        Text(error).foregroundStyle(.secondary)
                    }
                    if store.canLoadMore {
                        Button("Continue Searching") { Task { await store.continueSearching() } }
                            .disabled(store.isLoadingNextPage)
                            .frame(minHeight: 44)
                    }
                    if store.isLoadingNextPage {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .scrollTargetLayout()
                .gusTVPagePadding()
            }
            .scrollPosition(id: rootState.scrollBinding(for: "search:" + rootState.selectedSectionID + ":" + store.query))
            .lookToScroll()
        }
    }
}

struct SearchRootView<Content: View>: View {
    @Environment(AppNavigationModel.self) private var navigation
    @Environment(SessionStore.self) private var session
    @Bindable var state: SectionSearchState
    @FocusState private var isSearchFocused: Bool

    @ViewBuilder var content: () -> Content

    var body: some View {
        searchContent
            .onChange(of: navigation.searchFocusRequest) { _, request in
                guard session.mediaProvider.capabilities.supportsSearch, request > 0 else { return }
                state.isPresented = true
                isSearchFocused = true
            }
    }

    @ViewBuilder
    private var searchContent: some View {
        if session.mediaProvider.capabilities.supportsSearch {
            searchSurface
                .gusSearchable(
                    text: $state.text,
                    isPresented: $state.isPresented,
                    isFocused: $isSearchFocused,
                    prompt: Text("Search Library")
                )
                .onChange(of: state.text, initial: true) { _, _ in state.updateQuery() }
        } else {
            content()
        }
    }

    @ViewBuilder
    private var searchSurface: some View {
        if isSearching {
            if let store = state.store {
                SearchResultsView(store: store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            content()
        }
    }

    private var isSearching: Bool {
        session.mediaProvider.capabilities.supportsSearch
            && !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
