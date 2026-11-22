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
                            case let .natural(text):
                                Label {
                                    VStack(alignment: .leading, spacing: ContentSpacing.caption) {
                                        Text(verbatim: text)
                                        Text("Natural Language").font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: { Image(systemName: "text.magnifyingglass") }
                            case let .related(search):
                                Label {
                                    VStack(alignment: .leading, spacing: ContentSpacing.caption) {
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(SessionStore.self) private var session
    let store: SearchStore

    let searchState: SectionSearchState

    private var usesList: Bool {
        searchState.showsList || dynamicTypeSize.isAccessibilitySize
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
                #if os(tvOS)
                    TVSearchCompletionRows()
                #endif
                LazyVGrid(columns: usesList ? [GridItem(.flexible())] : PosterGrid.columns, alignment: .leading, spacing: PosterGrid.spacing) {
                    ForEach(store.results, id: \.id) { item in
                        resultLink(item)
                            .navigationLinkIndicatorVisibility(usesList ? .visible : .automatic)
                            .id(ItemRef(item: item).id)
                            .posterNavigationStyle()
                            .gusTVFocus(id: ItemRef(item: item).id, section: RootNavigationState.searchID, ids: store.results.map { ItemRef(item: $0).id }, item: item)
                            .task { await store.loadMoreIfNeeded(currentItem: item) }
                    }

                    if store.isRefreshing {
                        ProgressView().accessibilityLabel("Refreshing")
                    }
                    if let error = store.refreshError {
                        VStack(spacing: ContentSpacing.group) {
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
            .searchResultsScroll(viewport: searchState.viewport, anchor: Bindable(searchState).scrollAnchor)
            .lookToScroll()
        }
    }

    @ViewBuilder private func resultLink(_ item: MediaItem) -> some View {
        if item.type == .genre {
            MediaItemNavigationLink(item: item, searchQuery: store.query) {
                VStack(alignment: .leading, spacing: ContentSpacing.caption) {
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
            MediaItemNavigationLink(item: item, searchQuery: store.query) {
                if usesList {
                    MediaLibraryRow(item: item)
                } else {
                    PosterCard(item: item, imageURL: session.mediaProvider.primaryImageURL(for: item, context: .posterGrid), fallbackURLs: session.mediaProvider.artworkURLs(for: item, request: .init(role: .poster, maxWidth: 360)))
                }
            }
            .mediaItemContextMenu(item: item)
            .accessibilityIdentifier("Search.result." + ItemRef(item: item).id)
        }
    }
}

extension View {
    @ViewBuilder func searchResultsScroll(viewport: SearchResultsViewport?, anchor: Binding<String?>) -> some View {
        #if os(tvOS)
            scrollPosition(id: anchor)
        #else
            if let viewport {
                modifier(SearchResultsScrollRestoration(viewport: viewport))
                    .id(ObjectIdentifier(viewport))
            } else {
                scrollPosition(id: anchor)
            }
        #endif
    }
}

#if !os(tvOS)
    private struct SearchResultsScrollRestoration: ViewModifier {
        @Environment(RootNavigationState.self) private var navigation
        let viewport: SearchResultsViewport
        @State private var position = ScrollPosition()
        @State private var isOnscreen = false
        @State private var pendingDistance: CGFloat?

        private struct Geometry: Equatable {
            let distanceFromTop: CGFloat
            let contentHeight: CGFloat
        }

        private var showsResults: Bool {
            navigation.showsSearchResults(viewport)
        }

        func body(content: Content) -> some View {
            content
                .scrollPosition($position)
                .onScrollGeometryChange(for: Geometry.self) {
                    // ScrollPosition measures from the top including the native toolbar inset.
                    Geometry(distanceFromTop: $0.contentOffset.y + $0.contentInsets.top, contentHeight: $0.contentSize.height)
                } action: { old, new in
                    guard isOnscreen, showsResults else { return }
                    if let pendingDistance {
                        if abs(pendingDistance - new.distanceFromTop) < 1 {
                            self.pendingDistance = nil
                        } else if old.contentHeight != new.contentHeight {
                            // Lazy rows can grow after the first layout clamps the offset.
                            position.scrollTo(y: pendingDistance)
                        }
                    } else {
                        viewport.distanceFromTop = new.distanceFromTop
                    }
                }
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting {
                        pendingDistance = nil
                    }
                }
                .onAppear {
                    isOnscreen = true
                    restore()
                }
                .onDisappear { isOnscreen = false }
                .onChange(of: showsResults) { _, shown in
                    if shown {
                        restore()
                    }
                }
        }

        private func restore() {
            guard isOnscreen, showsResults, let distance = viewport.distanceFromTop else { return }
            pendingDistance = distance
            position.scrollTo(y: distance)
        }
    }
#endif

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
                SearchResultsView(store: store, searchState: state)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if let store {
                state.retain(store, owner: owner)
            } else {
                store = state.acquireStore(session: session, owner: owner)
            }
        }
        .onDisappear {
            state.release(owner: owner)
        }
        .onChange(of: state.text) { _, _ in state.updateQuery() }
    }
}
