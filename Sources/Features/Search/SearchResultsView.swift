import SwiftUI

struct RecentSearchesView: View {
    @Environment(SessionStore.self) private var session
    @State private var confirmsClear = false
    let onSelect: (SearchHistoryEntry) -> Void

    var body: some View {
        let history = session.searchHistory
        let entries = history.entries
        if entries.isEmpty {
            ContentUnavailableView("Search Library", systemImage: "magnifyingglass")
        } else {
            List {
                Section("Recent Searches") {
                    ForEach(entries) { entry in
                        Button { onSelect(entry) } label: {
                            switch entry {
                            case let .typed(text):
                                Label(text, systemImage: "magnifyingglass")
                            case let .related(search):
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(search.name)
                                        Text(search.kind.title).font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: { Image(systemName: search.kind.systemImage) }
                            }
                        }
                        .accessibilityIdentifier("Search.recent." + entry.id)
                        .contextMenu {
                            Button("Remove from History", systemImage: "trash", role: .destructive) { history.remove(entry) }
                        }
                        .accessibilityAction(named: "Remove from History") { history.remove(entry) }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            history.remove(entries[index])
                        }
                    }
                }
                Button("Clear Search History", role: .destructive) { confirmsClear = true }
                    .accessibilityIdentifier("Search.clearRecent")
            }
            .alert("Clear Search History?", isPresented: $confirmsClear) {
                Button("Cancel", role: .cancel) {}
                Button("Clear Search History", role: .destructive) { history.clear() }
            }
        }
    }
}

struct SearchResultsView: View {
    @Environment(RootNavigationState.self) private var rootState
    @Environment(SessionStore.self) private var session
    let store: SearchStore

    private var searchState: SectionSearchState {
        rootState.searchState(for: RootNavigationState.searchID)
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
                            .gusTVFocus(id: ItemRef(item: item).id, section: "search:" + RootNavigationState.searchID + ":" + store.query, ids: store.results.map { ItemRef(item: $0).id }, item: item)
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
            .gusVisibleContent(.search(RootNavigationState.searchID), isLoading: store.state.isLoading || store.isRefreshing || store.isLoadingNextPage)
            .scrollPosition(id: rootState.scrollBinding(for: "search:" + RootNavigationState.searchID + ":" + store.query))
            .lookToScroll()
        }
    }

    @ViewBuilder private func resultLink(_ item: MediaItem) -> some View {
        if item.type == .genre {
            MediaItemNavigationLink(item: item, onSelect: { didSelect(item) }) {
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
            MediaItemNavigationLink(item: item, onSelect: { didSelect(item) }) {
                if searchState.showsList {
                    MediaLibraryRow(item: item)
                } else {
                    PosterCard(item: item, imageURL: session.mediaProvider.primaryImageURL(for: item, context: .posterGrid), fallbackURLs: session.mediaProvider.artworkURLs(for: item, request: .init(role: .poster, maxWidth: 360)))
                }
            }
            .mediaItemContextMenu(item: item)
        }
    }

    private func didSelect(_ item: MediaItem) {
        searchState.selectedResult(item, for: store.query, in: session.searchHistory)
    }
}

/// The global search keeps its loaded pages when this surface is temporarily hidden.
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
        .onDisappear {
            state.completeLoadedSearch(in: session.searchHistory)
            state.release(owner: owner)
        }
        .onChange(of: state.text) { _, _ in state.updateQuery() }
    }
}
