import SwiftUI

/// The home screen: a "Continue Watching" rail above a grid of library posters.
///
/// The `HomeStore` is owned by the platform root container and shared with the
/// Libraries destination, so home content is fetched once per session instead of
/// once per consuming screen.
struct HomeView: View {
    @Environment(RootNavigationState.self) private var rootState
    @Environment(AppNavigationModel.self) private var navigation
    @Environment(SessionStore.self) private var session
    @Environment(PlaybackRefreshStore.self) private var playbackRefresh
    @Environment(SharedWithYouStore.self) private var sharedWithYou
    @Environment(UpNextStore.self) private var upNext
    let store: HomeStore?

    init(store: HomeStore? = nil) {
        self.store = store
    }

    var body: some View {
        Group {
            if let store {
                if case let .failed(message) = store.state, DownloadsAvailability.isSupported {
                    ContentUnavailableView {
                        Label("Server Unavailable", systemImage: "wifi.slash")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Downloaded", systemImage: "arrow.down.circle") {
                            navigation.open(.downloaded)
                        }
                        Button("Try Again") { Task { await store.load() } }
                    }
                } else {
                    content(store)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("Queue Could Not Be Updated", isPresented: Binding(get: { upNext.errorMessage != nil }, set: {
            if !$0 {
                upNext.clearError()
            }
        })) {
            Button("OK", role: .cancel) { upNext.clearError() }
        } message: { Text(upNext.errorMessage ?? "") }
        .navigationTitle("Home")
        .task {
            await upNext.refresh(session: session)
        }
        .task(id: playbackRefresh.revision) {
            guard playbackRefresh.revision > 0, let store else { return }
            await store.refresh()
        }
        .task(id: sharedWithYou.revision) {
            guard let store else { return }
            await store.loadSharedWithYou(links: sharedWithYou.links, title: sharedWithYou.collectionTitle)
        }
        .task(id: store != nil) {
            guard let store else { return }
            await store.loadSharedWithYou(links: sharedWithYou.links, title: sharedWithYou.collectionTitle)
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
            isEmpty: store.resumeItems.isEmpty && store.sharedWithYouItems.isEmpty && nextUpItems.isEmpty && store.latestSections.isEmpty,
            emptyTitle: String(localized: "No Recent Media", comment: "Home empty-state title when no media has been watched recently"),
            emptySymbol: "clock",
            retryAction: { Task { await store.load() } }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if !store.resumeItems.isEmpty {
                        MediaRail(title: String(localized: "Continue Watching", comment: "Home rail title for in-progress media"), items: store.resumeItems).id("resume")
                    }
                    if !store.sharedWithYouItems.isEmpty {
                        MediaRail(title: store.sharedWithYouTitle, items: store.sharedWithYouItems).id("shared")
                    }
                    if !nextUpItems.isEmpty {
                        MediaRail(title: String(localized: "Next Up", comment: "Home rail title for next episodes"), items: nextUpItems, style: .backdrop).id("next")
                    }
                    SavedQueueRecoveryRail()
                    ProgressTransferView()
                    ForEach(store.latestSections) { section in
                        MediaRail(title: section.title, items: section.items).id(section.id)
                    }
                }
                .scrollTargetLayout()
                .padding()
                .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: rootState.scrollBinding(for: "home"))
            .lookToScroll()
            .refreshable {
                await upNext.refresh(session: session, force: true)
                await store.refresh()
            }
        }
    }
}

/// Horizontal rail of media items.
struct MediaRail: View {
    @Environment(UpNextStore.self) private var upNext
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
                    ForEach(items, id: \.id) { saved in
                        let item = saved.id.flatMap { session.references.updates[$0] } ?? saved
                        NavigationLink(value: ItemRef(item: item)) {
                            switch style {
                            case .poster:
                                PosterCard(
                                    item: item,
                                    imageURL: session.mediaProvider.primaryImageURL(for: item, context: .posterRail),
                                    fallbackURLs: session.mediaProvider.artworkURLs(for: item, maxWidth: 260),
                                    onExhausted: { _ = try? await session.references.currentItem(item) }
                                )
                                .frame(width: style.itemWidth)
                            case .backdrop:
                                BackdropCard(
                                    item: item,
                                    imageURL: session.mediaProvider.backdropImageURL(for: item, maxWidth: 560),
                                    fallbackURLs: session.mediaProvider.artworkURLs(for: item, maxWidth: 560),
                                    onExhausted: {
                                        _ = try? await session.references.currentItem(item)
                                        await upNext.refresh(session: session)
                                    }
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
    var fallbackURLs: [URL] = []
    var onExhausted: (() async -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkTile(url: imageURL, aspectRatio: MediaRailMetrics.aspectRatio(for: .backdrop), contentMode: .fit, placeholderSymbol: "play.rectangle", fallbackURLs: fallbackURLs, onExhausted: onExhausted)
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
