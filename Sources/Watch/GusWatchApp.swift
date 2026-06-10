import SwiftUI

/// A Playa Named Gus for Apple Watch — the companion defined in
/// `Documentation/watchos-brief.md`: a remote for the household's other Jellyfin
/// clients first, a lightweight standalone client (browse, on-watch audio, offline
/// audio) second. Standalone-capable: signs in by itself via Quick Connect, with
/// WatchConnectivity hand-off from the iPhone as an accelerator.
@main
struct GusWatchApp: App {
    @State private var appModel = AppModel.shared
    @State private var offlineDownloads = OfflineDownloadStore()

    init() {
        DiagnosticsHub.shared.record(.appLaunched)
        WatchCredentialReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(appModel)
                .environment(offlineDownloads)
                .task {
                    appModel.restoreLastSession()
                }
        }
    }
}

/// Signed-out → connect flow; signed-in → the paged watch experience.
struct WatchRootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let session = appModel.currentSession {
            WatchSignedInView()
                .environment(session)
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
