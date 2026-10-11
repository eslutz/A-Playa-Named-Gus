import SwiftUI

/// A Playa Named Gus for Apple Watch — the companion defined in
/// `Documentation/watchos-brief.md`: a remote for the household's other Jellyfin
/// clients first, a lightweight standalone client (browse, on-watch audio, offline
/// audio) second. Standalone-capable: signs in by itself via Quick Connect, with
/// WatchConnectivity hand-off from the iPhone as an accelerator.
@main
struct GusWatchApp: App {
    @State private var appModel = AppModel.shared
    @State private var offlineDownloads = OfflineDownloadStore.shared
    private let shouldConnectToDemoServer: Bool

    init() {
        DiagnosticsHub.shared.record(.appLaunched)
        WatchCredentialReceiver.shared.activate()
        #if DEBUG
            // Mirrors the iOS app's --gus-demo-server flag so Scripts/screenshots.sh can
            // capture signed-in watch scenes against the local demo Jellyfin server.
            shouldConnectToDemoServer = ProcessInfo.processInfo.arguments.contains("--gus-demo-server")
        #else
            shouldConnectToDemoServer = false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(appModel)
                .environment(offlineDownloads)
                .task {
                    #if DEBUG
                        if shouldConnectToDemoServer {
                            await appModel.connectToLocalDemoServer()
                            return
                        }
                    #endif
                    appModel.restoreLastSession()
                }
        }
    }
}

/// Signed-out → connect flow; signed-in → the paged watch experience.
struct WatchRootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(OfflineDownloadStore.self) private var downloads
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if let session = appModel.currentSession {
            WatchSignedInView()
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
            NavigationStack {
                WatchConnectView()
            }
        }
    }
}

/// Vertical pages: Remote, Resume, Browse, Downloads, Settings.
private struct WatchSignedInView: View {
    var body: some View {
        TabView {
            NavigationStack {
                WatchRemoteView()
            }
            NavigationStack {
                WatchResumeView()
            }
            NavigationStack {
                WatchBrowseView()
            }
            NavigationStack {
                WatchDownloadsView()
            }
            NavigationStack {
                WatchSettingsView()
            }
        }
        .tabViewStyle(.verticalPage)
    }
}
