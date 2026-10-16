import SwiftUI

/// Shared native actions for media links, with removal scoped to the containing group.
private struct MediaItemContextMenu<Actions: View>: ViewModifier {
    @Environment(RootNavigationState.self) private var root
    @Environment(SessionStore.self) private var session
    @Environment(UpNextStore.self) private var upNext
    @Environment(PlaybackRefreshStore.self) private var playbackRefresh
    let item: MediaItem?
    let groupName: String?
    let canRemove: Bool
    let allowsAddingToNextUp: Bool
    let remove: (() async -> Void)?
    @ViewBuilder let additionalActions: () -> Actions
    @State private var addingToPlaylist = false
    @State private var addingToCollection = false
    @State private var updating = false
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .task { await root.collectionStore(session: session).loadPermissions() }
            .contextMenu {
                if let item, item.id != nil, ContentRatingGate.admitsStored(item) {
                    if [.movie, .episode, .video, .series].contains(item.type) {
                        Button("Add to Next Up", systemImage: MediaActionSymbols.addToNextUp) { addToNextUp(item) }
                            .disabled(!allowsAddingToNextUp)
                    }
                    if [.movie, .episode, .video].contains(item.type) {
                        Button("Add to Playlist", systemImage: MediaActionSymbols.addToPlaylist) { addingToPlaylist = true }
                    }
                    if CollectionPlatform.canManage && (root.collectionStore(session: session).capabilities.addMembers || root.collectionStore(session: session).capabilities.create) {
                        Button("Add to Collection", systemImage: "rectangle.stack.badge.plus") { addingToCollection = true }
                    }
                    if [.movie, .episode].contains(item.type) {
                        Divider()
                        Button("Mark Watched", systemImage: "checkmark.circle") { mark(item, watched: true) }
                            .disabled(updating)
                        Button("Mark Unwatched", systemImage: "arrow.counterclockwise") { mark(item, watched: false) }
                            .disabled(updating)
                    }
                }
                additionalActions()
                if let groupName, let remove {
                    Divider()
                    Button("Remove from \(groupName)", systemImage: "minus.circle", role: .destructive) {
                        Task { await remove() }
                    }
                    .disabled(!canRemove || updating)
                }
            }
            .sheet(isPresented: $addingToPlaylist) {
                if let item {
                    NavigationStack { AddToVideoPlaylistView(item: current(item)) }
                }
            }
            .sheet(isPresented: $addingToCollection) {
                if let item {
                    NavigationStack { AddToMediaCollectionView(item: current(item)) }
                }
            }
            .alert("Item Could Not Be Updated", isPresented: Binding(get: { errorMessage != nil }, set: {
                if !$0 {
                    errorMessage = nil
                }
            })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
    }

    private func current(_ item: MediaItem) -> MediaItem {
        item.id.flatMap { session.references.updates[$0] } ?? item
    }

    private func addToNextUp(_ item: MediaItem) {
        let item = current(item)
        let scope = session.references.scope
        if !upNext.contains(item, serverID: scope.serverID, userID: scope.userID) {
            upNext.toggle(item, serverID: scope.serverID, userID: scope.userID)
        }
        if let id = NextUpBuilder.mediaID(item) {
            NextUpActivityStore.shared.setDismissed(id, dismissed: false, scope: scope)
        }
        errorMessage = upNext.errorMessage ?? NextUpActivityStore.shared.errorMessage
    }

    private func mark(_ item: MediaItem, watched: Bool) {
        guard !updating else { return }
        updating = true
        Task {
            defer { updating = false }
            let store = ItemDetailStore(item: current(item), session: session)
            await store.setWatched(watched)
            errorMessage = store.actionError
            await upNext.refresh(session: session, force: true)
            // Also reconcile partial success if a subsequent request failed.
            playbackRefresh.markPlaybackProgressChanged()
        }
    }
}

extension View {
    func mediaItemContextMenu(item: MediaItem?, groupName: String? = nil, canRemove: Bool = true, allowsAddingToNextUp: Bool = true, remove: (() async -> Void)? = nil) -> some View {
        mediaItemContextMenu(item: item, groupName: groupName, canRemove: canRemove, allowsAddingToNextUp: allowsAddingToNextUp, remove: remove) { EmptyView() }
    }

    func mediaItemContextMenu<Actions: View>(item: MediaItem?, groupName: String? = nil, canRemove: Bool = true, allowsAddingToNextUp: Bool = true, remove: (() async -> Void)? = nil, @ViewBuilder additionalActions: @escaping () -> Actions) -> some View {
        modifier(MediaItemContextMenu(item: item, groupName: groupName, canRemove: canRemove, allowsAddingToNextUp: allowsAddingToNextUp, remove: remove, additionalActions: additionalActions))
    }
}
