import JellyfinAPI
import SwiftUI

/// The home screen: a "Continue Watching" rail above a grid of library posters.
///
/// Pattern reference: Swiftfin's `HomeViewModel`-backed home. The store is created from
/// the environment `SessionStore` in `.task` (environment isn't available at `init`).
struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var store: HomeStore?

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(Text("Gus", comment: "App name"))
        .task {
            if store == nil {
                let store = HomeStore(session: session)
                self.store = store
                await store.load()
            }
        }
    }

    private func content(_ store: HomeStore) -> some View {
        LoadingStateView(
            state: store.state,
            isEmpty: store.libraries.isEmpty && store.resumeItems.isEmpty,
            emptyTitle: "No Libraries",
            emptySymbol: "rectangle.stack"
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if !store.resumeItems.isEmpty {
                        ContinueWatchingRail(items: store.resumeItems)
                    }
                    LibrariesGrid(libraries: store.libraries)
                }
                .padding()
            }
            .lookToScroll()
            .refreshable { await store.load() }
        }
    }
}

/// Horizontal rail of in-progress items.
private struct ContinueWatchingRail: View {
    @Environment(SessionStore.self) private var session
    let items: [BaseItemDto]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Watching")
                .font(.title2.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(items, id: \.id) { item in
                        NavigationLink(value: ItemRef(item: item)) {
                            PosterCard(
                                item: item,
                                imageURL: session.imageBuilder.primaryImageURL(for: item)
                            )
                            .frame(width: railItemWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var railItemWidth: CGFloat {
        #if os(tvOS)
            return 240
        #elseif os(macOS) || os(visionOS)
            return 180
        #else
            return 130
        #endif
    }
}

/// Grid of library poster cards.
private struct LibrariesGrid: View {
    @Environment(SessionStore.self) private var session
    let libraries: [BaseItemDto]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Libraries")
                .font(.title2.bold())

            LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: 24) {
                ForEach(libraries, id: \.id) { library in
                    NavigationLink(value: LibraryRef(item: library)) {
                        PosterCard(
                            title: library.name ?? "Library",
                            imageURL: session.imageBuilder.primaryImageURL(for: library),
                            aspectRatio: 16.0 / 9.0,
                            placeholderSymbol: library.librarySymbol
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

extension BaseItemDto {
    /// SF Symbol representing a library's collection type.
    var librarySymbol: String {
        switch collectionType {
        case .movies: return "film"
        case .tvshows: return "tv"
        case .music: return "music.note"
        case .books: return "book"
        case .photos: return "photo"
        case .livetv: return "antenna.radiowaves.left.and.right"
        default: return "rectangle.stack"
        }
    }
}
