import SwiftUI

/// Home combines automatic playback progress and explicit saved intents into Next Up.
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
    @Environment(VideoPlaylistsStore.self) private var playlists
    private let activity = NextUpActivityStore.shared
    let store: HomeStore?

    init(store: HomeStore? = nil) {
        self.store = store
    }

    var body: some View {
        Group {
            if let store {
                if case let .failed(message) = store.state, !hasContent(store), DownloadsAvailability.isSupported {
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
        .task(id: "\(upNext.revision)-\(playlists.revision)-\(activity.revision)") {
            updateNextUp()
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

    private func hasContent(_ store: HomeStore) -> Bool {
        !store.unifiedNextUp.isEmpty || !store.sharedWithYouItems.isEmpty || !store.latestSections.isEmpty
    }

    private func updateNextUp() {
        let scope = session.references.scope
        upNext.load(serverID: scope.serverID, userID: scope.userID)
        upNext.reconcileSyncedIntents(scope: scope)
        activity.reconcile(scope: scope)
        let candidates = playlists.playlists(scope: scope).compactMap { playlist -> NextUpPlaylistCandidate? in
            guard playlist.queued || (playlist.cursor != nil && playlist.cursor?.finished != true) else { return nil }
            let index = playlist.entries.firstIndex { $0.id == playlist.cursor?.entryID } ?? 0
            let item = playlist.entries.indices.contains(index) ? playlist.entries[index].reference.item : nil
            guard item.map { ContentRatingGate.admitsStored($0) } ?? true else { return nil }
            return NextUpPlaylistCandidate(id: playlist.id, name: playlist.name, item: item, position: playlist.entries.isEmpty ? 0 : index + 1, total: playlist.entries.count, activityAt: playlist.activityAt)
        }
        store?.updateNextUp(saved: upNext.entries(serverID: scope.serverID, userID: scope.userID), playlists: candidates)
    }

    private func content(_ store: HomeStore) -> some View {
        return LoadingStateView(
            state: hasContent(store) ? .loaded : store.state,
            isEmpty: !hasContent(store),
            emptyTitle: String(localized: "No Recent Media", comment: "Home empty-state title when no media has been watched recently"),
            emptySymbol: "clock",
            retryAction: { Task { await store.load() } }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if let message = activity.errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Recent Activity Unavailable", systemImage: "exclamationmark.triangle").font(.headline)
                            Text(message).foregroundStyle(.secondary)
                            Button("Dismiss") { activity.clearError() }
                        }
                    }
                    if let message = store.errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Some Content Could Not Be Refreshed", systemImage: "wifi.slash").font(.headline)
                            Text(message).foregroundStyle(.secondary)
                            Button("Try Again") { Task { await store.refresh() } }
                        }
                    }
                    if !store.unifiedNextUp.isEmpty {
                        NextUpRail(store: store).id("next")
                    }
                    if !store.sharedWithYouItems.isEmpty {
                        MediaRail(title: store.sharedWithYouTitle, items: store.sharedWithYouItems).id("shared")
                    }
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
                updateNextUp()
            }
        }
    }
}

/// The first twenty cards and full list share the same builder output and IDs.
private struct NextUpRail: View {
    let store: HomeStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Next Up").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink("Show All") { NextUpListView(store: store) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: MediaRailMetrics.spacing(for: .backdrop)) {
                    ForEach(Array(store.unifiedNextUp.prefix(20))) { entry in
                        NextUpDestination(entry: entry, usesArtwork: true)
                            .frame(width: MediaRailMetrics.itemWidth(for: .backdrop))
                    }
                }
                .padding(.vertical, 4)
                .tvFocusSection()
            }
            .lookToScroll(.horizontal)
        }
    }
}

private struct NextUpListView: View {
    let store: HomeStore
    var body: some View {
        List {
            ForEach(store.unifiedNextUp) { entry in NextUpDestination(entry: entry) }
            if store.hasMoreNextUp {
                Button("Load More") { Task { await store.loadMoreNextUp() } }
                    .disabled(store.isLoadingMore)
                    .overlay(alignment: .trailing) {
                        if store.isLoadingMore {
                            ProgressView()
                        }
                    }
            }
            if let message = store.errorMessage {
                Text(message).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Next Up")
        .overlay {
            if store.unifiedNextUp.isEmpty {
                ContentUnavailableView("Nothing in Next Up", systemImage: "play.rectangle")
            }
        }
    }
}

private struct NextUpDestination: View {
    @Environment(SessionStore.self) private var session
    @Environment(UpNextStore.self) private var upNext
    let entry: NextUpEntry
    var usesArtwork = false
    @State private var replacement: UpNextEntry?

    var body: some View {
        Group {
            if let playlist = entry.playlist {
                NavigationLink(value: VideoPlaylistRef(id: playlist.id)) { label }
                    .posterNavigationStyle()
            } else if let saved = entry.savedEntry, saved.availability == .unavailable || saved.availability == .requiresSelection {
                VStack(alignment: .leading, spacing: 8) {
                    label
                    Text("Unavailable on this server").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Retry") { Task { await upNext.refresh(session: session, force: true) } }
                        Button("Choose Replacement") { replacement = saved }
                        Button("Remove", role: .destructive) { upNext.remove(saved) }
                    }
                }
            } else if let item = entry.item {
                NavigationLink(value: ItemRef(item: item)) { label }
                    .posterNavigationStyle()
                    .contextMenu {
                        if let saved = entry.savedEntry {
                            Button("Remove from Next Up", systemImage: "minus.circle", role: .destructive) { upNext.remove(saved) }
                        }
                    }
            }
        }
        .sheet(item: $replacement) { saved in
            MediaReplacementPicker(item: saved.reference.item, candidates: upNext.candidates(for: saved)) { candidate in
                await upNext.replace(saved, with: candidate, session: session)
            }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 6) {
            if usesArtwork {
                ArtworkTile(url: entry.item.flatMap { session.mediaProvider.backdropImageURL(for: $0, maxWidth: 560) }, aspectRatio: 16.0 / 9.0, contentMode: .fit, placeholderSymbol: entry.playlist == nil ? "play.rectangle" : "list.bullet.rectangle", fallbackURLs: entry.item.map { session.mediaProvider.artworkURLs(for: $0, maxWidth: 560) } ?? [])
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .posterHoverEffect()
            }
            Text(entry.playlist?.name ?? entry.item?.seriesName ?? entry.item?.displayTitle ?? "Video")
                .font(.headline).lineLimit(1)
            if let item = entry.item, item.type == .episode {
                if let locator = item.episodeLocator {
                    Text("\(locator) · \(item.displayTitle)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(item.displayTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Text(reasonText).font(.caption).foregroundStyle(.secondary)
            if let progress = entry.item?.playbackProgress, entry.reasons.contains(.resume) {
                ProgressView(value: progress).accessibilityLabel("Playback progress")
            }
        }
        .contentShape(Rectangle())
    }

    private var reasonText: String {
        entry.reasons.map { reason in
            switch reason {
            case .resume: String(localized: "Resume", comment: "Next Up reason")
            case .nextEpisode: String(localized: "Next Episode", comment: "Next Up reason")
            case .saved: String(localized: "Saved", comment: "Next Up reason")
            case .playlist: String(localized: "Playlist \(entry.playlist?.position ?? 0) of \(entry.playlist?.total ?? 0)", comment: "Next Up playlist position")
            }
        }.joined(separator: " · ")
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
