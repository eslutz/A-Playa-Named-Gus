import JellyfinAPI
import SwiftUI

/// The home screen: a "Continue Watching" rail above a grid of library posters.
///
/// Pattern reference: Swiftfin's `HomeViewModel`-backed home. The store is created from
/// the environment `SessionStore` in `.task` (environment isn't available at `init`).
struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PlaybackRefreshStore.self) private var playbackRefresh
    @State private var store: HomeStore?

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Home")
        .task {
            if store == nil {
                let store = HomeStore(session: session)
                self.store = store
                await store.load()
            }
        }
        .task(id: playbackRefresh.revision) {
            guard playbackRefresh.revision > 0, let store else { return }
            await store.load()
        }
    }

    private func content(_ store: HomeStore) -> some View {
        LoadingStateView(
            state: store.state,
            isEmpty: store.libraries.isEmpty && store.resumeItems.isEmpty && store.nextUpItems.isEmpty && store.latestSections.isEmpty,
            emptyTitle: "No Libraries",
            emptySymbol: "rectangle.stack"
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if !store.resumeItems.isEmpty {
                        MediaRail(title: "Continue Watching", items: store.resumeItems)
                    }
                    if !store.nextUpItems.isEmpty {
                        MediaRail(title: "Next Up", items: store.nextUpItems, style: .backdrop)
                    }
                    ForEach(store.latestSections) { section in
                        MediaRail(title: section.title, items: section.items)
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

/// Horizontal rail of media items.
private struct MediaRail: View {
    @Environment(SessionStore.self) private var session
    let title: String
    let items: [BaseItemDto]
    var style: MediaRailStyle = .poster

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: style.spacing) {
                    ForEach(items, id: \.id) { item in
                        NavigationLink(value: ItemRef(item: item)) {
                            switch style {
                            case .poster:
                                PosterCard(
                                    item: item,
                                    imageURL: session.imageBuilder.primaryImageURL(for: item, context: .posterRail)
                                )
                                .frame(width: style.itemWidth)
                            case .backdrop:
                                BackdropCard(
                                    item: item,
                                    imageURL: session.imageBuilder.backdropImageURL(for: item, maxWidth: 560)
                                )
                                .frame(width: style.itemWidth)
                            }
                        }
                        .posterNavigationStyle()
                    }
                }
                .padding(.vertical, 4)
                .tvFocusSection()
            }
            .lookToScroll(.horizontal)
        }
    }
}

private enum MediaRailStyle: Equatable {
    case poster
    case backdrop

    var itemWidth: CGFloat {
        MediaRailMetrics.itemWidth(for: kind)
    }

    var spacing: CGFloat {
        MediaRailMetrics.spacing(for: kind)
    }

    private var kind: MediaRailKind {
        switch self {
        case .poster: return .poster
        case .backdrop: return .backdrop
        }
    }
}

enum MediaRailKind: Equatable {
    case poster
    case backdrop
}

enum MediaRailMetrics {
    static func itemWidth(for kind: MediaRailKind) -> CGFloat {
        #if os(tvOS)
            return kind == .backdrop ? 420 : 240
        #elseif os(macOS) || os(visionOS)
            return kind == .backdrop ? 320 : 180
        #else
            return kind == .backdrop ? 300 : 150
        #endif
    }

    static func spacing(for kind: MediaRailKind) -> CGFloat {
        switch kind {
        case .poster: return 16
        case .backdrop: return 22
        }
    }
}

private struct BackdropCard: View {
    let item: BaseItemDto
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncPoster(url: imageURL, contentMode: .fill, placeholderSymbol: "play.rectangle")
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .posterHoverEffect()

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var title: String {
        item.seriesName ?? item.displayTitle
    }

    private var subtitle: String? {
        if item.type == .episode {
            return item.episodeLocator ?? item.name
        }
        return item.runtimeText ?? item.productionYear.map(String.init)
    }

    private var accessibilityLabel: Text {
        if let subtitle {
            Text("\(title), \(subtitle)")
        } else {
            Text(title)
        }
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
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: PosterGrid.spacing) {
                ForEach(libraries, id: \.id) { library in
                    NavigationLink(value: LibraryRef(item: library)) {
                        PosterCard(
                            title: library.name ?? "Library",
                            imageURL: session.imageBuilder.primaryImageURL(for: library, context: .posterGrid),
                            aspectRatio: 16.0 / 9.0,
                            placeholderSymbol: library.librarySymbol
                        )
                    }
                    .posterNavigationStyle()
                }
            }
            .tvFocusSection()
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
