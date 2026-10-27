import SwiftUI

/// Switches between the signed-out connect flow and the signed-in app, injecting the
/// active `SessionStore` into the signed-in tree.
///
/// Replaces Swiftfin's root coordinator: a plain `if let` on `AppModel.currentSession`.
struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(UpNextStore.self) private var upNext
    @Environment(VideoPlaylistsStore.self) private var videoPlaylists
    @Environment(ServerMediaListsStore.self) private var serverLists
    @Environment(OfflineDownloadStore.self) private var downloads
    @State private var audio = AudioPlaybackCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .gusIPhoneCanvas()
            .environment(audio)
            .onChange(of: activeAccount) { _, _ in audio.stop(); videoPlaylists.deactivate(); serverLists.deactivate() }
    }

    private var activeAccount: AccountScope? {
        appModel.currentSession.map { AccountScope(serverID: $0.server.id, userID: $0.user.id) }
    }

    @ViewBuilder private var content: some View {
        if let session = appModel.currentSession {
            RootContainer()
                .task(id: videoPlaylists.revision) {
                    upNext.reconcileSyncedIntents(scope: session.references.scope)
                    NextUpActivityStore.shared.reconcile(scope: session.references.scope)
                }
                .id(SessionCredential(user: session.user).account)
                .environment(session)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await videoPlaylists.activate(scope: session.references.scope)
                    upNext.reconcileSyncedIntents(scope: session.references.scope)
                    NextUpActivityStore.shared.reconcile(scope: session.references.scope)
                    await upNext.refresh(session: session)
                    guard !Task.isCancelled, activeAccount == session.references.scope else { return }
                    serverLists.load(scope: session.references.scope)
                    await serverLists.refresh(session: session)
                }
                .task(id: scenePhase) {
                    downloads.load(serverID: session.server.id, userID: session.user.id)
                    guard scenePhase == .active else { return }
                    await downloads.refreshRemoteReferences(session: session)
                    await downloads.repairMissingArtwork(session: session)
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    // Artwork retries can be slow offline. Progress reconciliation has
                    // its own view-scoped task so it starts immediately and shares the
                    // same foreground/account cancellation lifetime.
                    OfflinePlaybackProgressStore.shared.retryUnavailable(scope: session.references.scope)
                    while !Task.isCancelled {
                        await OfflinePlaybackProgressStore.shared.sync(session: session) {
                            appModel.currentSession?.server.id == session.server.id &&
                                appModel.currentSession?.user.id == session.user.id
                        }
                        try? await Task.sleep(for: .seconds(30))
                    }
                }
        } else {
            ConnectFlowView()
        }
    }
}
