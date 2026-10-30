import SwiftUI

/// Item detail surface re-expressed from the Swiftfin visionOS PR layout using A Playa Named Gus's
/// native SwiftUI stack: cinematic header, inline actions, metadata rows, and about cards.
struct ItemDetailView: View {
    @Environment(RootNavigationState.self) private var navigationState
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    @Environment(PlaybackRefreshStore.self) private var playbackRefresh
    @Environment(UpNextStore.self) private var upNext
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    let item: MediaItem

    @State private var updatingNextUp = false
    @State private var nextUpError: String?
    @State private var playerItem: ItemRef?
    @State private var sharePlay = SharePlayCoordinator.shared
    @State private var addingToPlaylist = false
    @State private var addingToCollection = false
    @State private var sharePlayPresentation: SharePlayPresentation?
    @State private var sharePlayErrorMessage: String?
    @State private var store: ItemDetailStore?
    @State private var localProgress = OfflinePlaybackProgressStore.shared
    // Read via @AppStorage so a changed household limit re-gates already-pushed screens.
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimitRawValue = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnratedContent = false

    var body: some View {
        Group {
            if isRestricted {
                RestrictedContentView()
            } else if let store {
                LoadingStateView(state: store.state, retryAction: { Task { await store.load() } }) {
                    detailContent(for: store)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(detailNavigationTitle)
        .gusTVDetailTitle()
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                if store == nil {
                    let store = navigationState.detailStore(for: item, session: session)
                    self.store = store
                }
            }
            .onChange(of: session.references.revision) { _, _ in
                if let store, let id = store.item.id, let current = session.references.updates[id] {
                    store.acceptResolvedMetadata(current)
                }
            }
            .playerPresentation(item: $playerItem)
            .gusTVTask(isPresented: $addingToCollection) { NavigationStack { AddToMediaCollectionView(item: store?.item ?? item) } }
            .gusTVTask(isPresented: $addingToPlaylist, onDismiss: { navigationState.restoreTVDetailFocus(item: item) }) {
                NavigationStack { AddToVideoPlaylistView(item: store?.item ?? item) }
                    .gusTVExitTask { addingToPlaylist = false }
            }
            .toolbar {
                #if !os(tvOS)
                    if !isRestricted, let store, store.item.id != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                let markWatched = store.item.userData?.isWatched != true
                                if store.item.type == .movie || store.item.type == .episode {
                                    Button("Add to Playlist", systemImage: MediaActionSymbols.addToPlaylist) { addingToPlaylist = true }
                                }
                                if store.item.type == .movie, CollectionPlatform.canManage && (navigationState.collectionStore(session: session).capabilities.create || navigationState.collectionStore(session: session).capabilities.addMembers) {
                                    Button("Add to Collection", systemImage: "rectangle.stack.badge.plus") { addingToCollection = true }
                                }
                                Divider()
                                Button(markWatched ? "Mark as Watched" : "Mark as Unwatched", systemImage: markWatched ? "checkmark.circle" : "arrow.counterclockwise") {
                                    Task { await store.setWatched(markWatched, nextUp: upNext) }
                                }
                                .disabled(store.isUpdatingUserData || store.needsUserDataRefresh)
                            } label: { Label("More", systemImage: "ellipsis") }
                                .gusIPadIconOnly()
                                .accessibilityIdentifier("Detail.actions")
                        }
                    }
                #endif
            }
            .sharePlaySharingPresentation(presentation: $sharePlayPresentation, errorMessage: $sharePlayErrorMessage)
            .downloadErrorAlert(downloads)
            .alert("Item Could Not Be Updated", isPresented: Binding(get: { nextUpError != nil }, set: {
                if !$0 {
                    nextUpError = nil
                }
            })) {
                Button("OK", role: .cancel) { nextUpError = nil }
            } message: { Text(nextUpError ?? "") }
            // Handoff: continue browsing this item on another device. Restricted items
            // (family safety) are never advertised.
            .userActivity(GusUserActivity.itemDetail, isActive: !isRestricted && (store?.item.id ?? item.id) != nil) { activity in
                GusUserActivity.configure(
                    activity,
                    item: store?.item ?? item,
                    serverID: session.server.id,
                    userID: session.user.id
                )
            }
    }

    private var detailNavigationTitle: String {
        #if os(iOS)
            if widthClass == .compact, !DeviceIdentity.usesIPadPresentation {
                return ""
            }
        #endif
        return store?.item.displayTitle ?? item.displayTitle
    }

    private func resumeTicks(for item: MediaItem) -> Int? {
        let hasDownload = downloads.localFileURL(for: item, serverID: session.server.id, userID: session.user.id) != nil
        let localTicks = hasDownload ? item.id.flatMap { localProgress.positionTicks(forItemID: $0, scope: session.references.scope) } : nil
        return PlaybackActionPosition.ticks(for: item, localTicks: localTicks)
    }

    private func detailContent(for store: ItemDetailStore) -> some View {
        let target = store.item.gusTVPlaybackTarget(nextUp: navigationState.home?.unifiedNextUp ?? [], episodes: store.seriesStore?.episodes ?? [])
        return GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CinematicDetailHero(
                        item: store.item,
                        playbackItem: target,
                        primaryPlayEnabled: target.map { ContentRatingGate.admitsStored($0) } ?? false,
                        playbackHasProgress: target.map { (resumeTicks(for: $0) ?? 0) > 0 } ?? false,
                        startFromBeginning: {
                            if let target, ContentRatingGate.admitsStored(target) {
                                playerItem = ItemRef(item: target, serverID: session.server.id, userID: session.user.id, playbackStart: .fromBeginning)
                            }
                        },
                        backdropURL: session.mediaProvider.backdropImageURL(for: store.item, context: .backdrop),
                        play: {
                            if let target, ContentRatingGate.admitsStored(target) {
                                playerItem = ItemRef(item: target, serverID: session.server.id, userID: session.user.id)
                            }
                        },
                        isInUpNext: upNext.contains(store.item, serverID: session.server.id, userID: session.user.id),
                        toggleUpNext: {
                            guard !updatingNextUp else { return }
                            updatingNextUp = true
                            Task {
                                defer { updatingNextUp = false }
                                if upNext.contains(store.item, serverID: session.server.id, userID: session.user.id) {
                                    do { try await upNext.removeFromNextUp(store.item, session: session) }
                                    catch { nextUpError = GusError(from: error).localizedDescription }
                                } else {
                                    upNext.toggle(store.item, serverID: session.server.id, userID: session.user.id)
                                    NextUpActivityStore.shared.restore(store.item, scope: session.references.scope)
                                }
                                playbackRefresh.markPlaybackProgressChanged()
                            }
                        }
                    ) {
                        ItemUserActionButton(
                            title: store.item.userData?.isFavorite == true
                                ? "Remove from Favorites"
                                : "Add to Favorites",
                            systemImage: store.item.userData?.isFavorite == true
                                ? "heart.fill"
                                : "heart",
                            action: {
                                Task { await store.toggleFavorite() }
                            }
                        )
                        .disabled(store.isUpdatingUserData || store.needsUserDataRefresh)
                        .accessibilityIdentifier("Detail.favorite")
                        .gusTVDetailActionFocus(id: "favorite", item: store.item)
                        #if os(tvOS)
                            if store.item.id != nil {
                                Menu {
                                    Button(store.item.userData?.isWatched == true ? "Mark as Unwatched" : "Mark as Watched", systemImage: "checkmark.circle") {
                                        Task { await store.setWatched(store.item.userData?.isWatched != true, nextUp: upNext) }
                                    }
                                    .disabled(store.isUpdatingUserData || store.needsUserDataRefresh)
                                    .accessibilityIdentifier("Detail.watched")
                                    if let target, ContentRatingGate.admitsStored(target) {
                                        Button("Start from Beginning", systemImage: "arrow.counterclockwise") {
                                            playerItem = ItemRef(item: target, serverID: session.server.id, userID: session.user.id, playbackStart: .fromBeginning)
                                        }
                                    }
                                    if store.item.type == .movie || store.item.type == .episode {
                                        Button("Add to Playlist", systemImage: MediaActionSymbols.addToPlaylist) { addingToPlaylist = true }
                                    }
                                    if store.item.type == .movie, navigationState.collectionStore(session: session).capabilities.addMembers {
                                        Button("Add to Collection", systemImage: "rectangle.stack.badge.plus") { addingToCollection = true }
                                    }
                                } label: {
                                    Label("More", systemImage: "ellipsis").gusDetailActionLabel()
                                }
                                .accessibilityIdentifier("Detail.more")
                                .gusTVDetailActionFocus(id: "more", item: store.item)
                            }
                        #endif
                        #if !os(tvOS)
                            if SharePlayCoordinator.canShare(store.item) {
                                ItemUserActionButton(
                                    title: "SharePlay",
                                    systemImage: "shareplay",
                                    action: {
                                        startSharePlay(for: store.item)
                                    }
                                )
                            }
                        #endif
                        if DownloadsAvailability.isSupported, session.mediaProvider.capabilities.supportsDownloads {
                            DownloadButton(item: store.item, iconOnly: true)
                                .accessibilityIdentifier("Detail.download")
                        }
                    }

                    VStack(alignment: .leading, spacing: 30) {
                        if store.isUpdatingUserData {
                            ProgressView("Updating…")
                        }
                        if let error = store.actionError {
                            VStack(alignment: .leading) {
                                Text(error).foregroundStyle(.secondary)
                                Button(store.needsUserDataRefresh ? String(localized: "Refresh Status") : String(localized: "Dismiss")) {
                                    if store.needsUserDataRefresh {
                                        Task { await store.refreshUserData() }
                                    } else {
                                        store.actionError = nil
                                    }
                                }
                            }
                        }
                        if let itemID = store.item.id {
                            SharedWithYouAttributionView(link: .item(id: itemID))
                        }

                        if let seriesStore = store.seriesStore {
                            SeriesEpisodesView(store: seriesStore).id("episodes")
                        }

                        if store.item.type == .movie, let id = store.item.id {
                            MovieCollectionMemberships(movieID: id).padding(.vertical)
                        }
                        DetailMetadataRows(item: store.item).id("metadata")

                        if !store.item.people.isEmpty {
                            CastRail(people: store.item.people).id("cast")
                        }

                        if !store.specialFeatures.isEmpty {
                            MediaRail(title: String(localized: "Special Features", comment: "Item detail section header for bonus/extra content"), items: store.specialFeatures, style: .backdrop, focusKey: "detail:" + ItemRef(item: item).id + ":extras", focusContext: "detail:" + ItemRef(item: item).id)
                        }

                        if !store.similarItems.isEmpty {
                            MediaRail(title: String(localized: "Recommended", comment: "Item detail section header for similar/recommended items"), items: store.similarItems, focusKey: "detail:" + ItemRef(item: item).id + ":recommended", focusContext: "detail:" + ItemRef(item: item).id)
                        }

                        AboutCardsView(
                            item: store.item,
                            posterURL: session.mediaProvider.primaryImageURL(for: store.item, context: .posterRail)
                        )
                    }
                    .scrollTargetLayout()
                    .padding(sectionPadding)
                    .frame(width: min(geometry.size.width, PageContentMetrics.maxWidth), alignment: .leading)
                    .frame(width: geometry.size.width)
                }
                .frame(width: geometry.size.width)
            }
            .scrollPosition(id: navigationState.scrollBinding(for: "detail:" + ItemRef(item: item).id))
        }
        .gusTVBrowseViewport()
        .gusTVDetailCanvas()
        .lookToScroll()
        .task {
            downloads.load(serverID: session.server.id, userID: session.user.id)
            upNext.load(serverID: session.server.id, userID: session.user.id)
            #if os(tvOS)
                if item.type == .movie {
                    await navigationState.collectionStore(session: session).loadPermissions()
                }
            #endif
        }
    }

    private var isRestricted: Bool {
        guard let limit = ContentRatingGate.Limit(rawValue: contentLimitRawValue), limit != .off else {
            return false
        }
        let current = store?.item ?? item
        return !ContentRatingGate.admits(current, limit: limit, hideUnrated: hideUnratedContent)
    }

    private var sectionPadding: EdgeInsets {
        #if os(tvOS)
            return EdgeInsets(top: 48, leading: 64, bottom: 64, trailing: 64)
        #elseif os(visionOS)
            return EdgeInsets(top: 30, leading: 36, bottom: 40, trailing: 36)
        #else
            return EdgeInsets(top: 24, leading: 20, bottom: 32, trailing: 20)
        #endif
    }

    #if !os(tvOS)
        private func startSharePlay(for item: MediaItem) {
            guard let activity = sharePlay.activity(for: item, session: session) else {
                sharePlayErrorMessage = String(localized: "This item can't be shared with SharePlay.", comment: "SharePlay error when an item cannot create a Group Activity")
                return
            }
            sharePlayPresentation = SharePlayPresentation(activity: activity)
        }
    #endif
}
