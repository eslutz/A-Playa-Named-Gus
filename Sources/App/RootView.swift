import SwiftUI

/// Switches between the signed-out connect flow and the signed-in app, injecting the
/// active `SessionStore` into the signed-in tree.
///
/// Replaces Swiftfin's root coordinator: a plain `if let` on `AppModel.currentSession`.
struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(UpNextStore.self) private var upNext
    @Environment(SavedMediaStore.self) private var videoPlaylists
    @Environment(ServerMediaListsStore.self) private var serverLists
    @Environment(OfflineDownloadStore.self) private var downloads
    @StoredContentPolicy private var contentPolicy
    #if os(iOS)
        private var audio: AudioPlaybackCoordinator {
            appModel.audioPlayback
        }
    #else
        @State private var audio = AudioPlaybackCoordinator()
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .gusIPhoneCanvas()
            .environment(audio)
            .disabled(appModel.isTransitioning)
            .overlay {
                if appModel.isTransitioning {
                    ProgressView("Finishing Playback…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .onChange(of: contentPolicy) { _, policy in
                if let track = audio.store?.currentTrack, !policy.admits(track) {
                    audio.stop()
                }
                if let session = appModel.currentSession {
                    SpotlightIndexer.deleteIndex(serverID: session.server.id, userID: session.user.id)
                }
            }
            .onChange(of: activeLease) { _, _ in
                #if !os(iOS)
                    audio.stop()
                #endif
                videoPlaylists.deactivate()
                serverLists.deactivate()
            }
    }

    private var activeLease: SessionLease? {
        appModel.currentSession?.lease
    }

    @ViewBuilder private var content: some View {
        if let session = appModel.currentSession {
            RootContainer(session: session)
                // Discard routes, in-flight searches and loaded media from the old
                // Apple ceiling, even if the manual limit happens to be identical.
                .id(contentPolicy.ageCeiling)
            #if canImport(DeclaredAgeRange) && (os(iOS) || os(macOS))
                .modifier(AgeRangeAccessHost(session: session))
            #endif
                .task(id: videoPlaylists.revision) {
                    upNext.reconcileSyncedIntents(scope: session.references.scope)
                    NextUpActivityStore.shared.reconcile(scope: session.references.scope)
                }
                .id(session.lease)
                .environment(session)
                .gusArtworkTransport(session.artworkTransport)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await videoPlaylists.activate(scope: session.references.scope)
                    upNext.reconcileSyncedIntents(scope: session.references.scope)
                    NextUpActivityStore.shared.reconcile(scope: session.references.scope)
                    await upNext.refresh(session: session)
                    guard !Task.isCancelled, activeLease == session.lease else { return }
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
                            activeLease == session.lease && session.isActive
                        }
                        try? await Task.sleep(for: .seconds(30))
                    }
                }
        } else {
            ConnectFlowView()
        }
    }
}
