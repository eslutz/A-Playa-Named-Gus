import JellyfinAPI
import SwiftUI

/// Grid of the items inside a single library.
///
/// Pattern reference: Swiftfin's library/`getItems` paging (single page for the milestone).
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
        .task {
            if store == nil {
                let store = LibraryStore(library: library, session: session)
                self.store = store
                await store.load()
            }
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
                LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: 24) {
                    ForEach(store.items, id: \.id) { item in
                        NavigationLink(value: ItemRef(item: item)) {
                            PosterCard(
                                item: item,
                                imageURL: session.imageBuilder.primaryImageURL(for: item)
                            )
                        }
                        .posterNavigationStyle()
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
