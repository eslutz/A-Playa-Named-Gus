import JellyfinAPI
import SwiftUI

/// Grid of the items inside a single library.
///
/// Pattern reference: Swiftfin's library/`getItems` paging.
struct LibraryGridView: View {
    @Environment(SessionStore.self) private var session
    let library: BaseItemDto
    @State private var store: LibraryStore?

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(library.name ?? "Library")
        .toolbar {
            if let store {
                ToolbarItem {
                    LibraryFilterMenu(store: store)
                        .disabled(store.isLoading)
                }
            }
        }
        .task(id: library.storeIdentity) {
            let store = LibraryStore(library: library, session: session)
            self.store = store
            await store.load()
        }
    }

    private func content(_ store: LibraryStore) -> some View {
        LoadingStateView(
            state: store.state,
            isEmpty: store.items.isEmpty,
            emptyTitle: "Empty Library",
            emptySymbol: "rectangle.on.rectangle"
        ) {
            ScrollView {
                LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: PosterGrid.spacing) {
                    ForEach(store.items, id: \.id) { item in
                        NavigationLink(value: ItemRef(item: item)) {
                            PosterCard(
                                item: item,
                                imageURL: session.imageBuilder.primaryImageURL(for: item, context: .posterGrid)
                            )
                        }
                        .posterNavigationStyle()
                        .task {
                            await store.loadMoreIfNeeded(currentItem: item)
                        }
                    }

                    if store.isLoadingNextPage {
                        ProgressView()
                            .gridCellColumns(PosterGrid.columns.count)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical)
                    }
                }
                .padding()
                .tvFocusSection()
            }
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

private extension BaseItemDto {
    var storeIdentity: String {
        id ?? name ?? collectionType?.rawValue ?? "library"
    }
}
