import SwiftUI

/// Grid of the items inside a single library.
///
/// Pattern reference: Swiftfin's library/`getItems` paging.
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

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(scope.title)
        .toolbar {
            if let store {
                ToolbarItem {
                    LibraryFilterMenu(store: store)
                        .disabled(store.isLoading)
                }
            }
        }
        .task(id: scope.storeIdentity) {
            let store = navigationState.libraryStore(for: scope, session: session)
            self.store = store
        }
    }

    private func content(_ store: LibraryStore) -> some View {
        LoadingStateView(
            state: store.state,
            isEmpty: store.items.isEmpty && !store.canLoadMore,
            emptyTitle: "Empty Library",
            emptySymbol: "rectangle.on.rectangle",
            retryAction: { Task { await store.load() } }
        ) {
            ScrollView {
                LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: PosterGrid.spacing) {
                    ForEach(store.items, id: \.id) { item in
                        NavigationLink(value: ItemRef(item: item)) {
                            PosterCard(
                                item: item,
                                imageURL: session.mediaProvider.primaryImageURL(for: item, context: .posterGrid)
                            )
                        }
                        .id(item.id)
                        .posterNavigationStyle()
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
                            .gridCellColumns(PosterGrid.columns.count)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical)
                    }
                }
                .scrollTargetLayout()
                .padding()
                .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .tvFocusSection()
            }
            .scrollPosition(id: navigationState.scrollBinding(for: "library:" + scope.storeIdentity))
            .lookToScroll()
            .refreshable { await store.load() }
        }
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
