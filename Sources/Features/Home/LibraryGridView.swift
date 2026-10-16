import SwiftUI

/// Movie discovery and its paginated grid keep independent load states.
struct LibraryGridView: View {
    @Environment(RootNavigationState.self) private var navigationState
    @Environment(SessionStore.self) private var session
    let scope: LibraryGridScope
    @State private var store: LibraryStore?
    init(library: MediaItem) {
        scope = .library(library)
    }

    init(scope: LibraryGridScope) {
        self.scope = scope
    }

    private var isMovies: Bool {
        switch scope {
        case let .library(item): item.collectionType == .movies
        case let .category(category): category == .movies
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                #if os(tvOS)
                    HStack {
                        Text(scope.title).font(.largeTitle.bold())
                        Spacer()
                        if let store {
                            LibraryFilterMenu(store: store).disabled(store.isLoading)
                        }
                    }.padding(.bottom, 24)
                #endif
                if isMovies {
                    MovieCollectionsShelf(libraryID: scope.parentID)
                }
                if let store {
                    LoadingStateView(state: store.state, isEmpty: store.items.isEmpty && !store.canLoadMore, emptyTitle: "Empty Library", emptySymbol: "rectangle.on.rectangle", retryAction: { Task { await store.load() } }) {
                        grid(store)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .gusTVPagePadding()
            .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .gusTVBrowseViewport()
        .navigationTitle(scope.title)
        .toolbar {
            #if !os(tvOS)
                if let store {
                    ToolbarItem { LibraryFilterMenu(store: store).disabled(store.isLoading) }
                }
            #endif
        }
        .task(id: scope.storeIdentity) { store = navigationState.libraryStore(for: scope, session: session) }
        .scrollPosition(id: navigationState.scrollBinding(for: "library:" + scope.storeIdentity))
        .lookToScroll()
        .refreshable {
            await store?.load()
            if isMovies {
                await navigationState.collectionStore(session: session).load(force: true); await navigationState.collectionStore(session: session).loadLibrary(scope.parentID)
            }
        }
    }

    private func grid(_ store: LibraryStore) -> some View {
        LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: PosterGrid.spacing) {
            ForEach(store.items, id: \.id) { item in
                NavigationLink(value: ItemRef(item: item)) { PosterCard(item: item, imageURL: session.mediaProvider.primaryImageURL(for: item, context: .posterGrid)) }
                    .id(ItemRef(item: item).id)
                    .posterNavigationStyle()
                    .mediaItemContextMenu(item: item)
                    .gusTVFocus(id: ItemRef(item: item).id, section: "library:" + scope.storeIdentity, ids: store.items.map { ItemRef(item: $0).id }, initial: item.id == store.items.first?.id, item: item)
                    .task { await store.loadMoreIfNeeded(currentItem: item) }
            }
            if let error = store.pageError {
                Text(error).foregroundStyle(.secondary)
            }
            if store.canLoadMore {
                Button("Continue Searching") { Task { await store.continueSearching() } }.disabled(store.isLoadingNextPage).frame(minHeight: 44)
            }
            if store.isLoadingNextPage {
                ProgressView().gridCellColumns(PosterGrid.columns.count).frame(maxWidth: .infinity).padding(.vertical)
            }
        }
        .scrollTargetLayout()
        .tvFocusSection()
    }
}

private struct LibraryFilterMenu: View {
    let store: LibraryStore

    var body: some View {
        Menu {
            Picker("Sort", selection: sortSelection) {
                ForEach(LibrarySortOption.allCases) { option in
                    Text(option.title)
                        .tag(option)
                }
            }

            Picker("Filter", selection: statusSelection) {
                ForEach(LibraryStatusFilter.allCases) { option in
                    Text(option.title)
                        .tag(option)
                }
            }
        } label: {
            Label("Filter", systemImage: store.filter.hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    private var sortSelection: Binding<LibrarySortOption> {
        Binding {
            store.filter.sort
        } set: { sort in
            var filter = store.filter
            filter.sort = sort
            Task { await store.applyFilter(filter) }
        }
    }

    private var statusSelection: Binding<LibraryStatusFilter> {
        Binding {
            store.filter.status
        } set: { status in
            var filter = store.filter
            filter.status = status
            Task { await store.applyFilter(filter) }
        }
    }
}
