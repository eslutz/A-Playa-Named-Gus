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
    #if !os(tvOS)
        @State private var externalBook: ItemRef?
    #endif
    @State private var selectedSourceID: String?
    @State private var selectedSourceItemID: String?
    @State private var startOverride: PlaybackStartOverride?
    @State private var pendingSource: MediaSource?
    @State private var pendingSourceItem: MediaItem?
    @State private var pendingSourceFocusItem: MediaItem?
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
                LoadingStateView(state: store.state, retryAction: { Task { await store.load() } }, preservesContent: store.hasLoadedContent) {
                    detailContent(for: store)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .gusVisibleContent(.detail(ItemRef(item: store?.item ?? item).id), isLoading: store?.state.isLoading ?? true)
        .navigationTitle(detailNavigationTitle)
        .gusTVDetailTitle()
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                if store == nil {
                    let store = navigationState.detailStore(for: item, session: session)
                    self.store = store
                    if store.state == .idle {
                        await store.load()
                    }
                } else if store?.state == .idle {
                    await store?.load()
                }
            }
            .onChange(of: playbackRefresh.revision) { _, _ in
                if let store, store.item.isBookFormat {
                    Task { await store.refreshUserData() }
                }
            }
            .onChange(of: session.references.revision) { _, _ in
                if let store, let id = store.item.id, let current = session.references.updates[id] {
                    store.acceptResolvedMetadata(current)
                }
            }
            .confirmationDialog("Switch Version", isPresented: Binding(get: { pendingSource != nil }, set: {
                if !$0 {
                    pendingSource = nil; pendingSourceItem = nil
                }
            }), titleVisibility: .visible) {
                if let source = pendingSource, let target = pendingSourceItem {
                    Button("Start Over") { selectSource(source, for: target, position: 0) }
                    if let ticks = resumeTicks(for: target), ticks > 0 {
                        Button("Resume at \(Duration.seconds(PlaybackTime.seconds(fromTicks: ticks)).formatted(.time(pattern: .hourMinuteSecond)))") { selectSource(source, for: target, position: ticks) }
                            .disabled(!PlaybackActionPosition.canResume(at: ticks, durationTicks: source.runTimeTicks))
                    }
                    Button("Cancel", role: .cancel) { pendingSource = nil; pendingSourceItem = nil }
                }
            } message: { Text("Choose where playback should begin in this version. Versions may have different timelines.") }
            .onChange(of: pendingSource != nil) { wasPresented, isPresented in
                guard wasPresented, !isPresented, let focusItem = pendingSourceFocusItem else { return }
                pendingSourceFocusItem = nil
                navigationState.restoreTVDetailFocus(item: focusItem, openerID: "version")
            }
            .playerPresentation(item: $playerItem)
        #if !os(tvOS)
            .sheet(item: $externalBook) { ref in ExternalBookReaderSheet(item: ref.item) }
        #endif
            .gusTVTask(isPresented: $addingToCollection, onDismiss: { navigationState.restoreTVDetailFocus(item: store?.item ?? item) }) {
                NavigationStack { AddToMediaCollectionView(item: store?.item ?? item) }
                    .gusTVExitTask { addingToCollection = false }
            }
            .gusTVTask(isPresented: $addingToPlaylist, onDismiss: { navigationState.restoreTVDetailFocus(item: store?.item ?? item) }) {
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
                                if store.item.type == .movie || store.item.isBookFormat, CollectionPlatform.canManage && (navigationState.collectionStore(session: session).capabilities.create || navigationState.collectionStore(session: session).capabilities.addMembers) {
                                    Button("Add to Collection", systemImage: "rectangle.stack.badge.plus") { addingToCollection = true }
                                }
                                if store.item.type == .book {
                                    Button("Open in Another App", systemImage: "square.and.arrow.up") {
                                        externalBook = ItemRef(item: store.item)
                                    }
                                    .accessibilityIdentifier("Book.openExternally")
                                }
                                Divider()
                                Button(store.item.completionActionTitle, systemImage: markWatched ? "checkmark.circle" : "arrow.counterclockwise") {
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
        PlaybackChoicePosition.ticks(for: selectedRequest(for: item), session: session, progress: localProgress, downloads: downloads)
    }

    private func detailContent(for store: ItemDetailStore) -> some View {
        var presentationItem = store.item
        if presentationItem.isBookFormat {
            presentationItem.overview = BookDetailMetadata.synopsis(store.item.overview)
            if presentationItem.id == item.id {
                presentationItem.overview = presentationItem.overview ?? BookDetailMetadata.synopsis(item.overview)
                if presentationItem.genres.isEmpty {
                    presentationItem.genres = item.genres
                }
            }
        }
        let target = store.item.gusTVPlaybackTarget(nextUp: navigationState.home?.unifiedNextUp ?? [], episodes: store.seriesStore?.episodes ?? [])
        return GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CinematicDetailHero(
                        item: presentationItem,
                        bookProgress: bookDetailProgress(for: store.item),
                        playbackItem: target,
                        primaryPlayEnabled: target.map { ContentRatingGate.admitsStored($0) } ?? false,
                        playbackHasProgress: target.map { (resumeTicks(for: $0) ?? 0) > 0 } ?? false,
                        startFromBeginning: {
                            if let target, ContentRatingGate.admitsStored(target) {
                                playerItem = playbackReference(for: target, fromBeginning: true)
                            }
                        },
                        backdropURL: session.mediaProvider.backdropImageURL(for: store.item, context: .backdrop),
                        play: {
                            if let target, ContentRatingGate.admitsStored(target) {
                                playerItem = playbackReference(for: target)
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
                        if let target {
                            versionMenu(for: target, focusItem: store.item)
                        }
                        ItemUserActionButton(
                            title: store.item.userData?.isFavorite == true
                                ? "Remove from Favorites"
                                : "Add to Favorites",
                            compactTitle: "Favorite",
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
                                    Button(store.item.completionActionTitle, systemImage: "checkmark.circle") {
                                        Task { await store.setWatched(store.item.userData?.isWatched != true, nextUp: upNext) }
                                    }
                                    .disabled(store.isUpdatingUserData || store.needsUserDataRefresh)
                                    .accessibilityIdentifier("Detail.watched")
                                    if let target, ContentRatingGate.admitsStored(target) {
                                        Button("Start from Beginning", systemImage: "arrow.counterclockwise") {
                                            playerItem = playbackReference(for: target, fromBeginning: true)
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
                                .gusDetailActionControlStyle()
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
                                        startSharePlay(for: selectedRequest(for: store.item))
                                    }
                                )
                            }
                        #endif
                        if DownloadsAvailability.isSupported, session.mediaProvider.capabilities.supportsDownloads {
                            DownloadButton(request: selectedRequest(for: store.item), iconOnly: true)
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
                                if store.canKeepCurrentUserData {
                                    Button("Keep Current Status") { store.keepCurrentUserData() }
                                }
                            }
                        }
                        if let failure = store.relatedContentError {
                            VStack(alignment: .leading) {
                                Text(failure).foregroundStyle(.secondary)
                                Button("Retry Related Content") { Task { await store.retryRelatedContent() } }
                            }
                        }
                        if let itemID = store.item.id {
                            SharedWithYouAttributionView(link: .item(id: itemID))
                        }

                        if let seriesStore = store.seriesStore {
                            SeriesEpisodesView(store: seriesStore, preferredEpisode: target).id("episodes")
                        }

                        if store.item.type == .movie || store.item.isBookFormat, let id = store.item.id {
                            ItemCollectionMemberships(itemID: id, format: CollectionFormat(type: store.item.type)).padding(.vertical)
                        }
                        #if !os(tvOS)
                            DetailMetadataRows(item: presentationItem).id("metadata")
                        #endif

                        #if !os(tvOS)
                            if !store.item.isBookFormat, !store.item.people.isEmpty {
                                CastRail(people: store.item.people).id("cast")
                            }

                        #endif

                        if !store.specialFeatures.isEmpty {
                            MediaRail(title: String(localized: "Special Features", comment: "Item detail section header for bonus/extra content"), items: store.specialFeatures, style: .backdrop, focusKey: "detail:" + ItemRef(item: item).id + ":extras", focusContext: "detail:" + ItemRef(item: item).id)
                        }

                        if !store.similarItems.isEmpty {
                            MediaRail(title: String(localized: "Recommended", comment: "Item detail section header for similar/recommended items"), items: store.similarItems, focusKey: "detail:" + ItemRef(item: item).id + ":recommended", focusContext: "detail:" + ItemRef(item: item).id)
                        }

                        #if os(tvOS)
                            if !store.item.isBookFormat, !store.item.people.isEmpty {
                                CastRail(people: store.item.people).id("cast")
                            }
                            DetailMetadataRows(item: presentationItem).id("metadata")
                        #endif

                        if !presentationItem.isBookFormat {
                            AboutCardsView(
                                item: presentationItem,
                                posterURL: session.mediaProvider.primaryImageURL(for: store.item, context: .posterRail)
                            )
                        }
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
            if store.item.type == .movie || (store.item.isBookFormat && CollectionPlatform.canManage) {
                await navigationState.collectionStore(session: session).loadPermissions()
            }
        }
    }

    private func bookDetailProgress(for item: MediaItem) -> BookDetailProgress? {
        guard item.isBookFormat, let id = item.id else { return nil }
        let scope = session.references.scope
        if item.type == .book {
            let locator = BookProgressStore.shared.locatorJSON(forItemID: id, scope: scope)
            let ticks = localProgress.positionTicks(forItemID: id, scope: scope)
            return BookDetailProgress.reading(locator: locator, localTicks: ticks, data: item.userData)
        }
        let request = selectedRequest(for: item)
        let sourceID = PlaybackChoicePosition.sourceID(for: request, session: session, downloads: downloads)
        let checkpoint = localProgress.positionTicks(forItemID: id, scope: scope, mediaSourceID: sourceID)
        let downloaded = downloads.record(for: item, serverID: scope.serverID, userID: scope.userID, mediaSourceID: sourceID)
        return BookDetailProgress.listening(
            ticks: checkpoint ?? resumeTicks(for: item) ?? item.userData?.playbackPositionTicks,
            duration: MediaPlaybackIdentity.runTimeTicks(for: downloaded?.playbackItem ?? item, mediaSourceID: sourceID),
            percent: checkpoint == nil ? item.userData?.playedPercentage : nil,
            started: checkpoint != nil || item.userData?.lastPlayedAt != nil,
            completed: item.userData?.isWatched == true
        )
    }

    private func selectedRequest(for target: MediaItem) -> PlaybackRequest {
        let matches = selectedSourceItemID == target.id
        let sourceID = matches ? selectedSourceID : nil
        let request = PlaybackRequest(item: target, streamSelection: .init(audioStreamIndex: nil, subtitleStreamIndex: nil, mediaSourceID: sourceID))
        return startOverride?.applying(to: request, session: session, progress: localProgress, downloads: downloads) ?? request
    }

    private func playbackReference(for target: MediaItem, fromBeginning: Bool = false) -> ItemRef {
        var request = selectedRequest(for: target)
        if fromBeginning {
            request.start = .fromBeginning; request.startPositionTicks = 0
        }
        return ItemRef(item: target, serverID: session.server.id, userID: session.user.id, playbackRequest: request)
    }

    private func selectSource(_ source: MediaSource, for target: MediaItem, position: Int?) {
        selectedSourceID = source.id
        selectedSourceItemID = target.id
        let request = PlaybackRequest(item: target, streamSelection: .init(audioStreamIndex: nil, subtitleStreamIndex: nil, mediaSourceID: source.id))
        startOverride = PlaybackStartOverride(request: request, ticks: position ?? 0, fromBeginning: position == 0, session: session, progress: localProgress, downloads: downloads)
        pendingSource = nil
        pendingSourceItem = nil
    }

    @ViewBuilder private func versionMenu(for target: MediaItem, focusItem: MediaItem) -> some View {
        let sources = target.mediaSources.filter { $0.id != nil }
        if sources.count > 1 {
            Menu {
                ForEach(Array(sources.enumerated()), id: \.element.id) { offset, source in
                    Button(source.name ?? String(localized: "Version \(offset + 1)")) {
                        if (resumeTicks(for: target) ?? 0) > 0 {
                            pendingSourceFocusItem = focusItem
                            pendingSourceItem = target
                            pendingSource = source
                        } else {
                            selectSource(source, for: target, position: 0)
                            navigationState.restoreTVDetailFocus(item: focusItem, openerID: "version")
                        }
                    }.disabled(selectedSourceItemID == target.id && selectedSourceID == source.id)
                }
            } label: { Label("Version", systemImage: "square.stack").gusDetailActionLabel() }
                .gusDetailActionControlStyle()
                .accessibilityIdentifier("Detail.version")
                .gusTVDetailActionFocus(id: "version", item: focusItem)
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
            return EdgeInsets(top: 48, leading: 80, bottom: 80, trailing: 80)
        #elseif os(visionOS)
            return EdgeInsets(top: 30, leading: 36, bottom: 40, trailing: 36)
        #else
            return EdgeInsets(top: 24, leading: 20, bottom: 32, trailing: 20)
        #endif
    }

    #if !os(tvOS)
        private func startSharePlay(for request: PlaybackRequest) {
            var sharedRequest = request
            if sharedRequest.streamSelection.mediaSourceID == nil {
                sharedRequest.streamSelection.mediaSourceID = request.item.mediaSources.first?.id
            }
            guard request.item.mediaSources.count <= 1 || sharedRequest.streamSelection.mediaSourceID != nil else {
                sharePlayErrorMessage = String(localized: "The playback version could not be identified. Reload this item before sharing.")
                return
            }
            guard let activity = sharePlay.activity(for: sharedRequest, session: session) else {
                sharePlayErrorMessage = String(localized: "This item can't be shared with SharePlay.", comment: "SharePlay error when an item cannot create a Group Activity")
                return
            }
            sharePlayPresentation = SharePlayPresentation(activity: activity)
        }
    #endif
}
