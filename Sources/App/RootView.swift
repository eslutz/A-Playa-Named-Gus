import SwiftUI

/// Switches between the signed-out connect flow and the signed-in app, injecting the
/// active `SessionStore` into the signed-in tree.
///
/// Replaces Swiftfin's root coordinator: a plain `if let` on `AppModel.currentSession`.
struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(OfflineDownloadStore.self) private var downloads
    @State private var audio = AudioPlaybackCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .environment(audio)
            .onChange(of: activeAccount) { _, _ in audio.stop() }
    }

    private var activeAccount: AccountScope? {
        appModel.currentSession.map { AccountScope(serverID: $0.server.id, userID: $0.user.id) }
    }

    @ViewBuilder private var content: some View {
        if let session = appModel.currentSession {
            RootContainer()
                .id(SessionCredential(user: session.user).account)
                .environment(session)
                .task(id: scenePhase) {
                    downloads.load(serverID: session.server.id, userID: session.user.id)
                    guard scenePhase == .active else { return }
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
