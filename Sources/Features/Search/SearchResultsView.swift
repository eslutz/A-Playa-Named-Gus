import SwiftUI

struct SearchResultsView: View {
    @Environment(RootNavigationState.self) private var rootState
    @Environment(SessionStore.self) private var session
    let store: SearchStore

    private var searchState: SectionSearchState {
        rootState.searchState(for: rootState.selectedSectionID)
    }

    var body: some View {
        LoadingStateView(
            state: store.state,
            isEmpty: store.results.isEmpty && !store.canLoadMore,
            emptyTitle: "No Results",
            emptySymbol: "magnifyingglass",
            retryAction: { Task { await store.search(store.query) } }
        ) {
            ScrollView {
                LazyVGrid(columns: searchState.showsList ? [GridItem(.flexible())] : PosterGrid.columns, alignment: .leading, spacing: PosterGrid.spacing) {
                    ForEach(store.results, id: \.id) { item in
                        resultLink(item)
                            .id(ItemRef(item: item).id)
                            .posterNavigationStyle()
                            .gusTVFocus(id: ItemRef(item: item).id, section: "search:" + rootState.selectedSectionID + ":" + store.query, ids: store.results.map { ItemRef(item: $0).id }, item: item)
                            .task { await store.loadMoreIfNeeded(currentItem: item) }
                    }

                    if store.isRefreshing {
                        ProgressView().accessibilityLabel("Refreshing")
                    }
                    if let error = store.refreshError {
                        VStack(spacing: 8) {
                            Text(error).foregroundStyle(.secondary)
                            Button("Try Again") { Task { await store.search(store.query) } }
                                .disabled(store.isRefreshing)
                        }
                    } else if let error = store.pageError {
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
            .gusVisibleContent(.search(rootState.selectedSectionID), isLoading: store.state.isLoading || store.isRefreshing || store.isLoadingNextPage)
            .scrollPosition(id: rootState.scrollBinding(for: "search:" + rootState.selectedSectionID + ":" + store.query))
            .lookToScroll()
        }
    }

    @ViewBuilder private func resultLink(_ item: MediaItem) -> some View {
        if item.type == .genre {
            MediaItemNavigationLink(item: item) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(item.displayTitle, systemImage: "tag")
                        .font(.headline)
                    Text("Genre").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
            }
            .accessibilityIdentifier("Search.genre." + (item.id ?? ""))
        } else {
            MediaItemNavigationLink(item: item) {
                if searchState.showsList {
                    MediaLibraryRow(item: item)
                } else {
                    PosterCard(item: item, imageURL: session.mediaProvider.primaryImageURL(for: item, context: .posterGrid), fallbackURLs: session.mediaProvider.artworkURLs(for: item, request: .init(role: .poster, maxWidth: 360)))
                }
            }
            .mediaItemContextMenu(item: item)
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
            OwnedSearchResults(state: state).id(ObjectIdentifier(state))
        } else {
            content()
        }
    }

    private var isSearching: Bool {
        session.mediaProvider.capabilities.supportsSearch
            && !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// One native result surface owns heavy pages while alive in the navigation
/// hierarchy. The account registry keeps only query and presentation choices.
struct OwnedSearchResults: View {
    @Environment(SessionStore.self) private var session
    let state: SectionSearchState
    @State private var store: SearchStore?
    @State private var owner = UUID()

    var body: some View {
        Group {
            if state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("Search Library", systemImage: "magnifyingglass")
            } else if let store {
                SearchResultsView(store: store)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            let acquired = store ?? state.acquireStore(session: session, owner: owner)
            store = acquired
            state.retain(acquired, owner: owner)
        }
        .onAppear {
            if let store {
                state.retain(store, owner: owner)
            }
        }
        .onDisappear { state.release(owner: owner) }
        .onChange(of: state.text) { _, _ in state.updateQuery() }
    }
}
