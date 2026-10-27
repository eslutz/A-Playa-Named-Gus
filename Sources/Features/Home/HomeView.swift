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
    @Environment(ServerMediaListsStore.self) private var serverLists
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
        .gusTVHomeTitle()
        .task {
            await upNext.refresh(session: session)
        }
        .task(id: "\(upNext.revision)-\(playlists.revision)-\(serverLists.revision)-\(activity.revision)") {
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
        guard !Task.isCancelled else { return }
        let scope = session.references.scope
        upNext.load(serverID: scope.serverID, userID: scope.userID)
        upNext.reconcileSyncedIntents(scope: scope)
        activity.reconcile(scope: scope)
        serverLists.load(scope: scope)
        let candidates = serverLists.videoPlaylists(scope: scope, supplemental: playlists).compactMap { playlist -> NextUpPlaylistCandidate? in
            guard playlist.queued || (playlist.cursor != nil && playlist.cursor?.finished != true) else { return nil }
            let index = playlist.entries.firstIndex { $0.id == playlist.cursor?.entryID } ?? 0
            let item = playlist.entries.indices.contains(index) ? playlist.entries[index].reference.item : nil
            guard item.map({ ContentRatingGate.admitsStored($0) }) ?? true else { return nil }
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
                        NextUpRail(store: store).gusTVNextUpHero(entries: store.unifiedNextUp).id("next")
                    }
                    if !store.sharedWithYouItems.isEmpty {
                        MediaRail(title: store.sharedWithYouTitle, items: store.sharedWithYouItems).id("shared")
                    }
                    ProgressTransferView()
                    ForEach(store.latestSections) { section in
                        MediaRail(title: section.title, items: section.items, latestKind: section.kind, requestsInitialFocus: store.unifiedNextUp.isEmpty && section.id == store.latestSections.first?.id)
                            .gusTVFallbackHero(items: section.items, enabled: store.unifiedNextUp.isEmpty && section.id == store.latestSections.first?.id)
                            .id(section.id)
                    }
                }
                .scrollTargetLayout()
                .gusTVPagePadding()
                .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .gusTVBrowseViewport()
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
    @Environment(RootNavigationState.self) private var root
    let store: HomeStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Next Up").gusPhoneRailHeading().accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink("Show All") { NextUpListView(store: store) }
                    .gusTVFocus(id: "all", section: "home.next.control", ids: ["all"], context: root.selectedSectionID)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: MediaRailMetrics.spacing(for: .backdrop)) {
                    ForEach(Array(store.unifiedNextUp.prefix(20))) { entry in
                        NextUpDestination(entry: entry, usesArtwork: true)
                            .gusPhoneRailWidth(backdrop: true, fallback: MediaRailMetrics.itemWidth(for: .backdrop))
                            .gusTVFocus(id: entry.id, section: "home.next", ids: store.unifiedNextUp.prefix(20).map(\.id), initial: entry.id == store.unifiedNextUp.first?.id, item: entry.item, entry: entry, context: root.selectedSectionID)
                    }
                }
                .scrollTargetLayout()
                .gusTVRailPadding()
                .tvFocusSection()
            }
            .scrollPosition(id: root.scrollBinding(for: "home.next"))
            .lookToScroll(.horizontal)
            .gusTVRailViewport()
        }
    }
}

private struct NextUpListView: View {
    let store: HomeStore
    @AppStorage("nextUpDisplayGrid") private var showsGrid = false
    var body: some View {
        ScrollView {
            LazyVGrid(columns: showsGrid ? [GridItem(.adaptive(minimum: 160), alignment: .top)] : [GridItem(.flexible())], alignment: .leading, spacing: 16) {
                ForEach(store.unifiedNextUp) { entry in
                    NextUpDestination(entry: entry, usesArtwork: showsGrid)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(showsGrid ? "List" : "Grid", systemImage: showsGrid ? "list.bullet" : "square.grid.2x2") { showsGrid.toggle() }
                    .accessibilityIdentifier("NextUp.displayMode")
                    .accessibilityValue(showsGrid ? "Grid" : "List")
            }
        }
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
    @Environment(VideoPlaylistsStore.self) private var playlists
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
            }
        }
        .accessibilityIdentifier("NextUp.card." + entry.id)
        .mediaItemContextMenu(item: entry.playlist == nil ? entry.item : nil, groupName: String(localized: "Next Up"), allowsAddingToNextUp: false, remove: {
            let scope = session.references.scope
            guard NextUpActivityStore.shared.setDismissed(entry.id, dismissed: true, scope: scope) else { return }
            if let saved = entry.savedEntry {
                upNext.remove(saved)
            }
            if let playlist = entry.playlist {
                playlists.setQueued(id: playlist.id, queued: false, scope: scope)
            }
        })
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
                    .gusTVArtworkStatus(item: entry.item, progressID: "NextUp.progress." + entry.id)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.playlist?.name ?? entry.item?.seriesName ?? entry.item?.displayTitle ?? "Video")
                    .font(.headline).lineLimit(1)
                if let item = entry.item, item.type == .episode {
                    if let locator = item.episodeLocator {
                        Text("\(locator) · \(item.displayTitle)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text(item.displayTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    Text(" ").font(.caption).accessibilityHidden(true)
                }
                Text(reasonText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .gusTVCardCaption()
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
    var library: MediaItem? = nil
    var latestKind: LatestMediaKind? = nil
    var style: MediaRailStyle = .poster
    var focusKey: String? = nil
    var focusContext: String? = nil
    var requestsInitialFocus = false
    @Environment(RootNavigationState.self) private var root

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .gusPhoneRailHeading()
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let latestKind {
                    NavigationLink("Show All") { LibraryGridView(scope: .latest(latestKind)) }
                        .gusIPhoneOnly()
                } else if let library {
                    NavigationLink("Show All") { LibraryGridView(library: library) }
                        .gusIPhoneOnly()
                }
            }

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
                                .gusPhoneRailWidth(backdrop: style == .backdrop, fallback: style.itemWidth)
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
                                .gusPhoneRailWidth(backdrop: style == .backdrop, fallback: style.itemWidth)
                            }
                        }
                        .id(ItemRef(item: item).id)
                        .posterNavigationStyle()
                        .mediaItemContextMenu(item: item)
                        .gusTVFocus(id: ItemRef(item: item).id, section: focusKey ?? (root.selectedSectionID + ":rail:" + title), ids: items.map { ItemRef(item: $0).id }, initial: requestsInitialFocus && item.id == items.first?.id, item: item, context: focusContext ?? root.selectedSectionID)
                    }
                }
                .scrollTargetLayout()
                .gusTVRailPadding()
                .tvFocusSection()
            }
            .scrollPosition(id: root.scrollBinding(for: focusKey ?? (root.selectedSectionID + ":rail:" + title)))
            .lookToScroll(.horizontal)
            .gusTVRailViewport()
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
                .gusTVArtworkStatus(item: item)

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
            .gusTVCardCaption()
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
    @State private var showsGrid = false
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif

    private var usesList: Bool {
        #if os(iOS)
            widthClass == .compact && !showsGrid
        #else
            false
        #endif
    }

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showsGrid.toggle() } label: {
                    Label(showsGrid ? "List" : "Grid", systemImage: showsGrid ? "list.bullet" : "square.grid.2x2")
                }
                .accessibilityIdentifier("Libraries.displayMode")
                .gusIPhoneOnly()
            }
        }
    }

    private func content(_ store: HomeStore) -> some View {
        LoadingStateView(
            state: store.state,
            isEmpty: store.libraries.isEmpty,
            emptyTitle: "No Libraries",
            emptySymbol: "rectangle.stack",
            retryAction: { Task { await store.load() } }
        ) {
            Group {
                if usesList {
                    List(store.libraries, id: \.id) { library in
                        NavigationLink(value: LibraryRef(item: library)) {
                            HStack(spacing: 16) {
                                Image(systemName: library.librarySymbol)
                                    .font(.title2).foregroundStyle(.blue)
                                    .frame(width: 54, height: 54)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                                Text(library.displayTitle).font(.body.weight(.medium))
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .listStyle(.plain)
                } else {
                    ScrollView {
                        LibrariesGrid(libraries: store.libraries)
                            .gusPhonePagePadding()
                            .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
                            .frame(maxWidth: .infinity)
                    }
                    .lookToScroll()
                }
            }
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
