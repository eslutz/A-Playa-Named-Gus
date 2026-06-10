import SwiftUI

/// The home screen: a "Continue Watching" rail above a grid of library posters.
///
/// The `HomeStore` is owned by the platform root container and shared with the
/// Libraries destination, so home content is fetched once per session instead of
/// once per consuming screen.
struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PlaybackRefreshStore.self) private var playbackRefresh
    @Environment(UpNextStore.self) private var upNext
    let store: HomeStore?

    init(store: HomeStore? = nil) {
        self.store = store
    }

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
            upNext.load(serverID: session.server.id, userID: session.user.id)
        }
        .task(id: playbackRefresh.revision) {
            guard playbackRefresh.revision > 0, let store else { return }
            await store.refresh()
        }
    }

    private func content(_ store: HomeStore) -> some View {
        // Remote next-up arrives pre-filtered; locally pinned Up Next items need the
        // same content-rating pass.
        let nextUpItems = ContentRatingGate.filter(upNext.mergedItems(
            remote: store.nextUpItems,
            serverID: session.server.id,
            userID: session.user.id
        ))

        return LoadingStateView(
            state: store.state,
            isEmpty: store.resumeItems.isEmpty && nextUpItems.isEmpty && store.latestSections.isEmpty,
            emptyTitle: "No Recent Media",
            emptySymbol: "clock",
            retryAction: { Task { await store.load() } }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if !store.resumeItems.isEmpty {
                        MediaRail(title: "Continue Watching", items: store.resumeItems)
                    }
                    if !nextUpItems.isEmpty {
                        MediaRail(title: "Next Up", items: nextUpItems, style: .backdrop)
                    }
                    ForEach(store.latestSections) { section in
                        MediaRail(title: section.title, items: section.items)
                    }
                }
                .padding()
                .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .lookToScroll()
            .refreshable { await store.refresh() }
        }
    }
}

/// Horizontal rail of media items.
struct MediaRail: View {
    @Environment(SessionStore.self) private var session
    let title: String
    let items: [MediaItem]
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
                                    imageURL: session.mediaProvider.primaryImageURL(for: item, context: .posterRail)
                                )
                                .frame(width: style.itemWidth)
                            case .backdrop:
                                BackdropCard(
                                    item: item,
                                    imageURL: session.mediaProvider.backdropImageURL(for: item, maxWidth: 560)
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

enum MediaRailStyle: Equatable {
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
    static func aspectRatio(for kind: MediaRailKind) -> CGFloat {
        switch kind {
        case .poster: return 2.0 / 3.0
        case .backdrop: return 16.0 / 9.0
        }
    }

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
    let item: MediaItem
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)

                AsyncPoster(url: imageURL, contentMode: .fit, placeholderSymbol: "play.rectangle")
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(MediaRailMetrics.aspectRatio(for: .backdrop), contentMode: .fit)
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

/// Persistent Libraries destination used by tabs, sidebars, and menu routes.
/// Shares the root container's `HomeStore` with `HomeView`.
struct LibrariesLandingView: View {
    let store: HomeStore?

    init(store: HomeStore? = nil) {
        self.store = store
    }

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Libraries")
    }

    private func content(_ store: HomeStore) -> some View {
        LoadingStateView(
            state: store.state,
            isEmpty: store.libraries.isEmpty,
            emptyTitle: "No Libraries",
            emptySymbol: "rectangle.stack",
            retryAction: { Task { await store.load() } }
        ) {
            ScrollView {
                LibrariesGrid(libraries: store.libraries)
                    .padding()
                    .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .lookToScroll()
            .refreshable { await store.refresh() }
        }
    }
}

/// Grid of library poster cards.
private struct LibrariesGrid: View {
    @Environment(SessionStore.self) private var session
    let libraries: [MediaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: PosterGrid.spacing) {
                ForEach(libraries, id: \.id) { library in
                    NavigationLink(value: LibraryRef(item: library)) {
                        PosterCard(
                            title: library.name ?? "Library",
                            imageURL: session.mediaProvider.primaryImageURL(for: library, context: .posterGrid),
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
