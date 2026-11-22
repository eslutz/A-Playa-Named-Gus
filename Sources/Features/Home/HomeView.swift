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
    @Environment(SavedMediaStore.self) private var playlists
    @Environment(ServerMediaListsStore.self) private var serverLists
    @Environment(\.scenePhase) private var scenePhase
    @StoredContentPolicy private var contentPolicy
    @State private var heldSlots: Set<String>?
    private let activity = NextUpActivityStore.shared
    let store: HomeStore?

    init(store: HomeStore? = nil) {
        self.store = store
    }

    var body: some View {
        Group {
            if let store, store.matchesRestriction {
                if case let .failed(message) = store.state, !hasContent(store), DownloadsAvailability.isSupported {
                    ContentUnavailableView {
                        Label("Server Unavailable", systemImage: "wifi.slash")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Downloads", systemImage: "arrow.down.circle") {
                            navigation.open(.downloaded)
                        }
                        Button("Try Again") { Task { await store.load() } }
                    }
                } else {
                    content(store)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: ContentSpacing.section) {
                        BrowseShelfPlaceholder(backdrop: true)
                        BrowseShelfPlaceholder(backdrop: false).accessibilityHidden(true)
                    }.gusTVPagePadding()
                }
            }
        }
        .alert("Queue Could Not Be Updated", isPresented: Binding(get: { upNext.errorMessage != nil }, set: {
            if !$0 {
                upNext.clearError()
            }
        })) {
            Button("OK", role: .cancel) { upNext.clearError() }
        } message: { Text(upNext.errorMessage ?? "") }
        .gusVisibleContent(.home, isLoading: store?.state.isLoading ?? true)
        .navigationTitle("Home")
        .task(id: String(store != nil) + contentPolicy.revision) {
            await store?.loadIfNeeded()
            await upNext.refresh(session: session)
        }
        .modifier(NextUpUpdates(store: store))
        .task(id: playbackRefresh.revision) {
            guard playbackRefresh.revision > 0, let store else { return }
            await store.refreshAfterPlayback(revision: playbackRefresh.revision)
        }
        #if os(tvOS)
        .task(id: syncedShelfRefresh) {
            guard let store, syncedShelfRefresh.isActive, shelfContext.recommendationsEnabled else { return }
            let context = shelfContext
            while !Task.isCancelled, session.isActive {
                await store.forYou.load(context, session: session)
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
            }
        }
        #else
        .task(id: activeShelfContext) {
            guard let activeShelfContext else { return }
            await store?.forYou.load(activeShelfContext, session: session)
        }
        #endif
        .task(id: sharedWithYou.revision) {
            guard let store else { return }
            await store.loadSharedWithYou(links: sharedWithYou.links, title: sharedWithYou.collectionTitle)
        }
        .task(id: store != nil) {
            guard let store else { return }
            await store.loadSharedWithYou(links: sharedWithYou.links, title: sharedWithYou.collectionTitle)
        }
    }

    private var shelfContext: ForYouShelfState.Context {
        let preferences = session.intelligencePreferences
        #if os(tvOS)
            return .init(
                cloudEnabled: false,
                recommendationsEnabled: preferences.forYouSyncEnabled,
                limit: contentPolicy.limit.rawValue,
                hideUnrated: contentPolicy.hideUnrated,
                ageCeiling: contentPolicy.ageCeiling,
                activityRevision: playbackRefresh.revision,
                tasteRevision: 0
            )
        #else
            return .init(
                cloudEnabled: preferences.cloudEnabled,
                recommendationsEnabled: preferences.recommendationsEnabled,
                limit: contentPolicy.limit.rawValue,
                hideUnrated: contentPolicy.hideUnrated,
                ageCeiling: contentPolicy.ageCeiling,
                activityRevision: playbackRefresh.revision,
                tasteRevision: session.libraryIntelligence.tasteRevision,
                forYouSyncEnabled: preferences.forYouSyncEnabled
            )
        #endif
    }

    #if !os(tvOS)
        private var activeShelfContext: ForYouShelfState.Context? {
            store != nil && scenePhase == .active ? shelfContext : nil
        }
    #endif

    #if os(tvOS)
        private struct SyncedShelfRefresh: Equatable {
            var store: ObjectIdentifier?
            var context: ForYouShelfState.Context
            var isActive: Bool
            var iCloudAccountRevision: Int
        }

        private var syncedShelfRefresh: SyncedShelfRefresh {
            .init(
                store: store.map(ObjectIdentifier.init),
                context: shelfContext,
                isActive: scenePhase == .active,
                iCloudAccountRevision: session.forYouShelf.iCloudAccountRevision
            )
        }
    #endif

    private func shouldShowShelf(_ store: HomeStore) -> Bool {
        guard session.isActive, shelfContext.recommendationsEnabled else { return false }
        return store.forYou.needsPlaceholder(shelfContext, session: session) || !store.forYou.picks.isEmpty || store.forYou.error != nil
    }

    private func hasContent(_ store: HomeStore) -> Bool {
        !visibleSlots(store).isEmpty || heldSlots?.isEmpty == false
    }

    private func visibleSlots(_ store: HomeStore) -> Set<String> {
        var slots = Set(store.latestSections.map(\.id))
        for kind in LatestMediaKind.allCases where store.isPending(kind) {
            slots.insert("latest:" + kind.rawValue)
        }
        if store.nextUpPending || !store.unifiedNextUp.isEmpty {
            slots.insert("next")
        }
        if shouldShowShelf(store) {
            slots.insert("forYou")
        }
        if !store.sharedWithYouItems.isEmpty {
            slots.insert("shared")
        }
        return slots
    }

    private func firstLoadingSlot(_ store: HomeStore, slots: Set<String>) -> String? {
        if slots.contains("next"), store.unifiedNextUp.isEmpty, store.nextUpPending {
            return "next"
        }
        if slots.contains("forYou"), shouldShowShelf(store), store.forYou.needsPlaceholder(shelfContext, session: session) {
            return "forYou"
        }
        return LatestMediaKind.allCases.first { kind in
            slots.contains("latest:" + kind.rawValue) && store.isPending(kind)
        }.map { "latest:" + $0.rawValue }
    }

    private func content(_ store: HomeStore) -> some View {
        let slots = heldSlots ?? visibleSlots(store)
        let loadingSlot = firstLoadingSlot(store, slots: slots)
        return LoadingStateView(
            state: hasContent(store) ? .loaded : store.state,
            isEmpty: !hasContent(store),
            emptyTitle: String(localized: "No Recent Media", comment: "Home empty-state title when no media has been watched recently"),
            emptySymbol: "clock",
            retryAction: { Task { await store.load() } }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: ContentSpacing.section) {
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
                    if slots.contains("next") {
                        Group {
                            if !store.unifiedNextUp.isEmpty {
                                NextUpRail(store: store)
                            } else {
                                BrowseShelfPlaceholder(backdrop: true).opacity(store.nextUpPending ? 1 : 0).accessibilityHidden(loadingSlot != "next")
                            }
                        }.id("next")
                    }
                    if slots.contains("forYou"), shelfContext.recommendationsEnabled {
                        if store.forYou.needsPlaceholder(shelfContext, session: session) {
                            BrowseShelfPlaceholder(backdrop: false, forYou: true, showsSyncSetup: !shelfContext.forYouSyncEnabled)
                                .accessibilityHidden(loadingSlot != "forYou").id("forYou")
                        } else if store.forYou.canDisplay(shelfContext, session: session), !store.forYou.picks.isEmpty {
                            MediaRail(
                                title: String(localized: "For You"),
                                items: store.forYou.picks.map(\.item),
                                recommendations: store.forYou.picks,
                                focusKey: "home.forYou"
                            ).id("forYou")
                        } else if let error = store.forYou.error {
                            VStack(alignment: .leading) {
                                Text("For You Unavailable").font(.headline)
                                Text(error).foregroundStyle(.secondary)
                                Button("Retry") { Task { await store.forYou.load(shelfContext, session: session, refresh: true) } }
                            }
                        } else if heldSlots != nil {
                            BrowseShelfPlaceholder(backdrop: false, forYou: true, showsSyncSetup: !shelfContext.forYouSyncEnabled).hidden()
                        }
                    }
                    if slots.contains("shared") {
                        if store.sharedWithYouItems.isEmpty {
                            BrowseShelfPlaceholder(backdrop: false).hidden()
                        } else {
                            MediaRail(title: store.sharedWithYouTitle, items: store.sharedWithYouItems).id("shared")
                        }
                    }
                    ProgressTransferView()
                    ForEach(LatestMediaKind.allCases, id: \.self) { kind in
                        let id = "latest:" + kind.rawValue
                        if slots.contains(id) {
                            Group {
                                if let section = store.latestSections.first(where: { $0.kind == kind }) {
                                    MediaRail(title: section.title, items: section.items, latestKind: kind, requestsInitialFocus: store.unifiedNextUp.isEmpty && id == store.latestSections.first?.id)
                                } else {
                                    BrowseShelfPlaceholder(backdrop: false).opacity(store.isPending(kind) ? 1 : 0).accessibilityHidden(loadingSlot != id)
                                }
                            }.id(id)
                        }
                    }
                }
                .scrollTargetLayout()
                .gusTVPagePadding()
                .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .gusTVBrowseViewport()
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y <= -geometry.contentInsets.top + 2
            } action: { _, atTop in
                heldSlots = atTop ? nil : (heldSlots ?? visibleSlots(store))
            }
            .onDisappear { heldSlots = nil }
            .scrollPosition(id: rootState.scrollBinding(for: "home"))
            .lookToScroll()
            .refreshable {
                heldSlots = nil
                await upNext.refresh(session: session, force: true)
                await store.refresh()
                await store.forYou.load(shelfContext, session: session, refresh: true)
                store.refreshNextUp(upNext: upNext, playlists: playlists, serverLists: serverLists)
            }
        }
    }
}

/// The queue can change while either its Home rail or its pushed list is visible.
private struct NextUpUpdates: ViewModifier {
    @Environment(UpNextStore.self) private var upNext
    @Environment(SavedMediaStore.self) private var playlists
    @Environment(ServerMediaListsStore.self) private var serverLists
    @StoredContentPolicy private var contentPolicy
    private let activity = NextUpActivityStore.shared
    let store: HomeStore?

    func body(content: Content) -> some View {
        content
            .task(id: "\(store != nil)-\(contentPolicy.revision)-\(upNext.revision)-\(playlists.revision)-\(serverLists.revision)-\(activity.revision)") {
                store?.refreshNextUp(upNext: upNext, playlists: playlists, serverLists: serverLists)
            }
    }
}

/// The first twenty cards and full list share the same builder output and IDs.
private struct NextUpRail: View {
    @Environment(RootNavigationState.self) private var root
    let store: HomeStore
    var body: some View {
        VStack(alignment: .leading, spacing: ContentSpacing.card) {
            HStack {
                Text("Next Up").gusPhoneRailHeading().accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink("Show All", value: GusRoute.nextUp)
                    .accessibilityIdentifier("NextUp.showAll")
                    .gusTVFocus(id: "all", section: "home.next.control", ids: ["all"], context: root.selectedSectionID)
            }
            .tvFocusSection()
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
            }
            .scrollPosition(id: root.scrollBinding(for: "home.next"))
            .lookToScroll(.horizontal)
            .gusTVRailViewport()
        }
    }
}

struct NextUpListView: View {
    let store: HomeStore
    @AppStorage("nextUpDisplayGrid") private var showsGrid = false
    var body: some View {
        ScrollView {
            #if os(tvOS)
                HStack {
                    Text("Next Up").font(.largeTitle.bold())
                    Spacer()
                    displayModeButton
                }
                .focusSection()
                .padding(.horizontal)
                .padding(.top, 64)
                .padding(.bottom, 24)
            #endif
            if showsGrid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(store.unifiedNextUp) { entry in
                        NextUpDestination(entry: entry, usesArtwork: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(store.unifiedNextUp) { entry in
                        NextUpDestination(entry: entry, usesArtwork: showsGrid)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                }
                .padding(.horizontal)
            }

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
        .modifier(NextUpUpdates(store: store))
        .gusTVDetailTitle()
        .toolbar {
            #if !os(tvOS)
                ToolbarItem(placement: .primaryAction) { displayModeButton }
            #endif
        }
        .overlay {
            if store.unifiedNextUp.isEmpty {
                ContentUnavailableView("Nothing in Next Up", systemImage: "play.rectangle")
            }
        }
    }

    private var displayModeButton: some View {
        Button { showsGrid.toggle() } label: { GusToolbarLabel(showsGrid ? "List" : "Grid", systemImage: showsGrid ? "list.bullet" : "square.grid.2x2") }
            .gusIPadIconOnly()
            .gusTVToolbarIcon()
            .accessibilityIdentifier("NextUp.displayMode")
            .accessibilityLabel(showsGrid ? "List" : "Grid")
            .accessibilityValue(showsGrid ? "Grid" : "List")
    }
}

private struct NextUpDestination: View {
    @Environment(SessionStore.self) private var session
    @Environment(UpNextStore.self) private var upNext
    let entry: NextUpEntry
    var usesArtwork = false
    @Environment(SavedMediaStore.self) private var playlists
    @State private var replacement: UpNextEntry?

    var body: some View {
        Group {
            if let playlist = entry.playlist {
                NavigationLink(value: GusRoute.playlist(.init(id: playlist.id))) { label }
                    .navigationLinkIndicatorVisibility(usesArtwork ? .automatic : .visible)
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
                MediaItemNavigationLink(item: item) { label }
                    .navigationLinkIndicatorVisibility(usesArtwork ? .automatic : .visible)
                    .posterNavigationStyle()
            }
        }
        .accessibilityIdentifier("NextUp.card." + entry.id)
        .mediaItemContextMenu(item: entry.playlist == nil ? entry.item : nil, groupName: String(localized: "Next Up"), allowsAddingToNextUp: false, remove: {
            let scope = session.references.scope
            if let playlist = entry.playlist {
                guard NextUpActivityStore.shared.setDismissed(entry.id, dismissed: true, scope: scope) else {
                    throw GusError.server(NextUpActivityStore.shared.errorMessage ?? String(localized: "Your queue change couldn't be saved. Try again."))
                }
                playlists.setQueued(id: playlist.id, queued: false, scope: scope)
            } else if let item = entry.item {
                try await upNext.removeFromNextUp(item, session: session)
            }
        })
        .sheet(item: $replacement) { saved in
            MediaReplacementPicker(item: saved.reference.item, candidates: upNext.candidates(for: saved)) { candidate in
                await upNext.replace(saved, with: candidate, session: session)
            }
        }
    }

    @ViewBuilder private var label: some View {
        if !usesArtwork {
            MediaLibraryRow(item: entry.item, title: entry.playlist?.name ?? entry.item?.seriesName ?? entry.item?.displayTitle, subtitle: episodeSubtitle, status: reasonText)
        } else {
            VStack(alignment: .leading, spacing: ContentSpacing.group) {
                if usesArtwork {
                    ArtworkTile(url: entry.item.flatMap { session.mediaProvider.backdropImageURL(for: $0, maxWidth: 560) }, aspectRatio: 16.0 / 9.0, contentMode: .fit, placeholderSymbol: entry.playlist == nil ? "play.rectangle" : "list.bullet.rectangle", fallbackURLs: entry.item.map { session.mediaProvider.artworkURLs(for: $0, request: .init(role: $0.type == .episode ? .episodeStill : .backdrop, maxWidth: 560)) } ?? [])
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .posterHoverEffect()
                        .gusTVArtworkStatus(item: entry.item, progressID: "NextUp.progress." + entry.id)
                }
                VStack(alignment: .leading, spacing: ContentSpacing.group) {
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([entry.playlist?.name, entry.item?.mediaAccessibility.label].compactMap { $0 }.joined(separator: ", "))
            .accessibilityValue([entry.item?.mediaAccessibility.value, reasonText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
        }
    }

    private var episodeSubtitle: String? {
        guard let item = entry.item, item.type == .episode else { return nil }
        return item.episodeLocator.map { "\($0) · \(item.displayTitle)" } ?? item.displayTitle
    }

    private var reasonText: String {
        entry.reasons.filter { $0 != .saved }.map { reason in
            switch reason {
            case .resume: String(localized: "Resume", comment: "Next Up reason")
            case .nextEpisode: String(localized: "Next Episode", comment: "Next Up reason")
            case .saved: ""
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
    var recommendations: [GusLibraryPick] = []
    var style: MediaRailStyle = .poster
    var focusKey: String? = nil
    var focusContext: String? = nil
    var requestsInitialFocus = false
    @Environment(RootNavigationState.self) private var root

    var body: some View {
        VStack(alignment: .leading, spacing: ContentSpacing.card) {
            HStack {
                Text(title)
                    .gusPhoneRailHeading()
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let latestKind {
                    NavigationLink("Show All", value: GusRoute.libraryGrid(.latest(latestKind)))
                        .gusTVFocus(id: "all", section: (focusKey ?? "latest:" + latestKind.rawValue) + ":control", ids: ["all"], context: focusContext ?? root.selectedSectionID)
                } else if let library {
                    NavigationLink("Show All", value: GusRoute.libraryGrid(.library(library)))
                        .gusTVFocus(id: "all", section: (focusKey ?? "library:" + (library.id ?? title)) + ":control", ids: ["all"], context: focusContext ?? root.selectedSectionID)
                }
            }
            .tvFocusSection()

            #if os(iOS)
                if !recommendations.isEmpty, !session.intelligencePreferences.forYouSyncEnabled {
                    ForYouSyncSetupButton()
                }
            #endif

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: style.spacing) {
                    ForEach(items, id: \.id) { saved in
                        let item = saved.id.flatMap { session.references.updates[$0] } ?? saved
                        MediaItemNavigationLink(item: item) {
                            switch style {
                            case .poster:
                                VStack(alignment: .leading, spacing: 4) {
                                    PosterCard(
                                        item: item,
                                        imageURL: session.mediaProvider.primaryImageURL(for: item, context: .posterRail),
                                        alignsMixedArtwork: !recommendations.isEmpty,
                                        fallbackURLs: session.mediaProvider.artworkURLs(for: item, request: .init(role: .poster, maxWidth: 260)),
                                        onExhausted: { _ = try? await session.references.currentItem(item) }
                                    )
                                    if let pick = recommendations.first(where: { $0.id == item.id && !$0.reason.isEmpty }) {
                                        Text(pick.reason).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .gusPhoneRailWidth(backdrop: style == .backdrop, fallback: style.itemWidth)
                            case .backdrop:
                                BackdropCard(
                                    item: item,
                                    imageURL: session.mediaProvider.backdropImageURL(for: item, maxWidth: 560),
                                    fallbackURLs: session.mediaProvider.artworkURLs(for: item, request: .init(role: item.type == .episode ? .episodeStill : .backdrop, maxWidth: 560)),
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
            }
            .scrollPosition(id: root.scrollBinding(for: focusKey ?? (root.selectedSectionID + ":rail:" + title)))
            .lookToScroll(.horizontal)
            .gusTVRailViewport()
        }
    }
}

#if os(iOS)
    private struct ForYouSyncSetupButton: View {
        @Environment(SessionStore.self) private var session
        @State private var showingConsent = false

        var body: some View {
            VStack(alignment: .leading, spacing: ContentSpacing.group) {
                Button {
                    showingConsent = true
                } label: {
                    Label("Set Up Apple TV Sync", systemImage: "appletv")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .gusPhoneActionTint()
                .disabled(session.isVerifyingForYouSyncAccount)
                .accessibilityIdentifier("ForYou.setupAppleTVSync")
                .forYouSyncConsent(isPresented: $showingConsent)

                if session.forYouSyncAccountVerificationFailed {
                    Text("Couldn’t verify your iCloud account. Try again.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
#endif

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
        ContentSpacing.card
    }
}

private struct BackdropCard: View {
    @AppStorage(MediaItem.seriesProgressKey) private var showSeriesProgress = false
    let item: MediaItem
    let imageURL: URL?
    var fallbackURLs: [URL] = []
    var onExhausted: (() async -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: ContentSpacing.group) {
            ArtworkTile(url: imageURL, aspectRatio: MediaRailMetrics.aspectRatio(for: .backdrop), contentMode: .fit, placeholderSymbol: "play.rectangle", fallbackURLs: fallbackURLs, onExhausted: onExhausted)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .posterHoverEffect()
                .gusTVArtworkStatus(item: item)

            VStack(alignment: .leading, spacing: ContentSpacing.caption) {
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
        .accessibilityLabel(item.mediaAccessibility.label)
        .accessibilityValue(item.mediaAccessibility(showSeriesProgress: showSeriesProgress).value)
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
}

/// Persistent Libraries destination used by tabs, sidebars, and menu routes.
/// Shares the root container's `HomeStore` with `HomeView`.
struct LibrariesLandingView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StoredContentPolicy private var contentPolicy
    @Environment(SessionStore.self) private var session
    @Environment(RootNavigationState.self) private var navigationState
    private var showsGrid: Bool {
        get { navigationState.librariesShowGrid }
        nonmutating set { navigationState.librariesShowGrid = newValue }
    }

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif

    private var usesList: Bool {
        #if os(iOS)
            (widthClass == .compact || DeviceIdentity.usesIPadPresentation) && !showsGrid
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
            if let store, store.matchesRestriction {
                content(store)
            } else {
                BrowseGridPlaceholder(list: usesList, ratio: 16.0 / 9).gusPhonePagePadding()
            }
        }
        .task(id: String(store != nil) + String(scenePhase == .active) + contentPolicy.revision) {
            guard scenePhase == .active else { return }
            await store?.loadLibraries(force: false)
        }
        .navigationTitle("Libraries")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showsGrid.toggle() } label: {
                    Label(showsGrid ? "List" : "Grid", systemImage: showsGrid ? "list.bullet" : "square.grid.2x2")
                }
                .accessibilityIdentifier("Libraries.displayMode")
                .gusIPadIconOnly()
                .gusIPhoneOrIPadOnly()
            }
        }
    }

    @ViewBuilder private func content(_ store: HomeStore) -> some View {
        if store.libraries.isEmpty, store.libraryState == .idle || store.libraryState == .loading {
            BrowseGridPlaceholder(list: usesList, ratio: 16.0 / 9).gusPhonePagePadding()
        } else {
            LoadingStateView(
                state: store.libraryState,
                isEmpty: store.libraries.isEmpty,
                emptyTitle: "No Libraries",
                emptySymbol: "rectangle.stack",
                retryAction: { Task { await store.loadLibraries() } },
                preservesContent: true
            ) {
                Group {
                    if usesList {
                        List(store.libraries, id: \.id) { library in
                            let urls = session.mediaProvider.artworkURLs(for: library, request: .init(role: .libraryThumbnail, maxWidth: 288))
                            NavigationLink(value: GusRoute.library(.init(item: library))) {
                                HStack(spacing: 16) {
                                    ArtworkTile(
                                        url: urls.first, aspectRatio: 16.0 / 9.0, contentMode: .fit,
                                        placeholderSymbol: library.librarySymbol, fallbackURLs: Array(urls.dropFirst())
                                    )
                                    .frame(width: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .accessibilityHidden(true)
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
                .refreshable { await store.loadLibraries() }
            }
        }
    }
}

/// Grid of library poster cards.
private struct LibrariesGrid: View {
    @Environment(SessionStore.self) private var session
    let libraries: [MediaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: ContentSpacing.card) {
            LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: PosterGrid.spacing) {
                ForEach(libraries, id: \.id) { library in
                    NavigationLink(value: GusRoute.library(.init(item: library))) {
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

/// Uses the same rail width and artwork ratios as the loaded cards.
struct BrowseShelfPlaceholder: View {
    let backdrop: Bool
    var forYou = false
    var showsSyncSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: ContentSpacing.card) {
            Text(verbatim: "Section title")
                .gusPhoneRailHeading()
                .redacted(reason: .placeholder)
            #if os(iOS)
                if forYou, showsSyncSetup {
                    ForYouSyncSetupButton().hidden()
                        .overlay { Capsule().fill(.quaternary) }
                }
            #endif
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: MediaRailMetrics.spacing(for: backdrop ? .backdrop : .poster)) {
                    ForEach(0 ..< 8, id: \.self) { _ in
                        BrowseCardPlaceholder(ratio: backdrop ? 16.0 / 9 : 2.0 / 3, forYou: forYou, nextUp: backdrop)
                            .gusPhoneRailWidth(backdrop: backdrop, fallback: MediaRailMetrics.itemWidth(for: backdrop ? .backdrop : .poster))
                    }
                }.gusTVRailPadding()
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(true)
            #if os(tvOS)
                .focusable(false)
            #endif
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

private struct BrowseCardPlaceholder: View {
    let ratio: CGFloat
    var forYou = false
    var nextUp = false

    var body: some View {
        VStack(alignment: .leading, spacing: ContentSpacing.group) {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary).aspectRatio(ratio, contentMode: .fit)
            VStack(alignment: .leading, spacing: ContentSpacing.caption) {
                if nextUp {
                    Text(verbatim: "Media title").font(.headline).lineLimit(1)
                } else {
                    Text(verbatim: "Media title").font(.subheadline.weight(.medium)).gusTVPosterTitle()
                }
                Text(verbatim: "Subtitle").font(.caption)
                Text(verbatim: " ").font(.caption)
            }
            .gusTVCardCaption()
            .redacted(reason: .placeholder)
            #if !os(tvOS)
                if forYou {
                    Text(verbatim: "Recommendation").font(.caption)
                        .lineLimit(2, reservesSpace: true)
                        .redacted(reason: .placeholder)
                }
            #endif
        }
    }
}

struct BrowseGridPlaceholder: View {
    var list = false
    var ratio: CGFloat = 2.0 / 3
    var body: some View {
        Group {
            if list {
                VStack(spacing: 16) {
                    ForEach(0 ..< 8, id: \.self) { _ in
                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 8).fill(.quaternary).aspectRatio(ratio, contentMode: .fit).frame(height: 58)
                            Capsule().fill(.quaternary).frame(width: 140, height: 12)
                            Spacer()
                        }
                    }
                }
            } else {
                LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: PosterGrid.spacing) {
                    ForEach(0 ..< 12, id: \.self) { _ in BrowseCardPlaceholder(ratio: ratio) }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}
