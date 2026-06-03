import JellyfinAPI
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
                LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: 24) {
                    ForEach(store.results, id: \.id) { item in
                        NavigationLink(value: ItemRef(item: item)) {
                            PosterCard(
                                item: item,
                                imageURL: session.imageBuilder.primaryImageURL(for: item)
                            )
                        }
                        .buttonStyle(.plain)
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
    @Environment(SessionStore.self) private var session
    @State private var store: SearchStore?
    @State private var searchText = ""

    @ViewBuilder var content: () -> Content

    var body: some View {
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
        .searchable(text: $searchText, prompt: Text("Search Jellyfin"))
        .task {
            if store == nil {
                store = SearchStore(session: session)
            }
        }
        .task(id: searchText) {
            guard let store else { return }
            guard isSearching else {
                store.reset()
                return
            }

            do {
                try await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await store.search(searchText)
            } catch is CancellationError {
            } catch {
                await store.search(searchText)
            }
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct SearchView: View {
    @Environment(SessionStore.self) private var session
    @State private var store: SearchStore?
    @State private var searchText = ""

    var body: some View {
        Group {
            if let store {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("Search Jellyfin", systemImage: "magnifyingglass")
                } else {
                    SearchResultsView(store: store)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $searchText, prompt: Text("Search Jellyfin"))
        .task {
            if store == nil {
                store = SearchStore(session: session)
            }
        }
        .task(id: searchText) {
            guard let store else { return }
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                store.reset()
                return
            }

            do {
                try await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await store.search(trimmed)
            } catch is CancellationError {
            } catch {
                await store.search(trimmed)
            }
        }
    }
}
