import SwiftUI

/// Item detail surface re-expressed from the Swiftfin visionOS PR layout using A Playa Named Gus's
/// native SwiftUI stack: cinematic header, inline actions, metadata rows, and about cards.
struct ItemDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    @Environment(PlaybackRefreshStore.self) private var playbackRefresh
    @Environment(UpNextStore.self) private var upNext
    let item: MediaItem

    @State private var playerItem: ItemRef?
    @State private var store: ItemDetailStore?
    // Read via @AppStorage so a changed household limit re-gates already-pushed screens.
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimitRawValue = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnratedContent = false

    var body: some View {
        Group {
            if isRestricted {
                RestrictedContentView()
            } else if let store {
                LoadingStateView(state: store.state) {
                    detailContent(for: store)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(store?.item.displayTitle ?? item.displayTitle)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(iOS) || os(visionOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .task {
            if store == nil {
                let store = ItemDetailStore(item: item, session: session)
                self.store = store
                await store.load()
            }
        }
        .playerPresentation(item: $playerItem)
        .downloadErrorAlert(downloads)
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

    private func detailContent(for store: ItemDetailStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CinematicDetailHero(
                    item: store.item,
                    backdropURL: session.mediaProvider.backdropImageURL(for: store.item, context: .backdrop),
                    play: {
                        playerItem = ItemRef(item: store.item)
                    },
                    isInUpNext: upNext.contains(store.item, serverID: session.server.id, userID: session.user.id),
                    toggleUpNext: {
                        upNext.toggle(store.item, serverID: session.server.id, userID: session.user.id)
                        playbackRefresh.markPlaybackProgressChanged()
                    }
                ) {
                    ItemUserActionButton(
                        title: store.item.userData?.isWatched == true
                            ? "Mark as Unwatched"
                            : "Mark as Watched",
                        systemImage: store.item.userData?.isWatched == true
                            ? "checkmark.circle.fill"
                            : "checkmark.circle",
                        action: {
                            Task { await store.toggleWatched() }
                        }
                    )
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
                    if store.item.type == .book {
                        BookActionButtons(item: store.item)
                    }
                    if DownloadsAvailability.isSupported, session.mediaProvider.capabilities.supportsDownloads {
                        DownloadButton(item: store.item, iconOnly: true)
                    }
                }

                VStack(alignment: .leading, spacing: 30) {
                    if let seriesStore = store.seriesStore {
                        SeriesEpisodesView(store: seriesStore)
                    }

                    DetailMetadataRows(item: store.item)

                    if !store.item.people.isEmpty {
                        CastRail(people: store.item.people)
                    }

                    if !store.specialFeatures.isEmpty {
                        MediaRail(title: String(localized: "Special Features", comment: "Item detail section header for bonus/extra content"), items: store.specialFeatures, style: .backdrop)
                    }

                    if !store.similarItems.isEmpty {
                        MediaRail(title: String(localized: "Recommended", comment: "Item detail section header for similar/recommended items"), items: store.similarItems)
                    }

                    AboutCardsView(
                        item: store.item,
                        posterURL: session.mediaProvider.primaryImageURL(for: store.item, context: .posterRail)
                    )
                }
                .padding(sectionPadding)
            }
            .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .lookToScroll()
        .task {
            downloads.load(serverID: session.server.id, userID: session.user.id)
            upNext.load(serverID: session.server.id, userID: session.user.id)
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
        #if os(visionOS) || os(tvOS)
            return EdgeInsets(top: 30, leading: 36, bottom: 40, trailing: 36)
        #else
            return EdgeInsets(top: 24, leading: 20, bottom: 32, trailing: 20)
        #endif
    }
}
