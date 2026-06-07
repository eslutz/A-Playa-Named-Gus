import SwiftUI

/// A Playa Named Gus — an Apple-first, multiplatform Jellyfin client.
///
/// Pure SwiftUI lifecycle (no AppDelegate). The root `AppModel` is created here and
/// injected via `@Environment`; on visionOS an `ImmersiveSpace` hosts the "Gus Cinema".
@main
struct GusApp: App {
    @State private var appModel = AppModel()
    @State private var appNavigation = AppNavigationModel()
    @State private var playbackRefresh = PlaybackRefreshStore()
    @State private var offlineDownloads = OfflineDownloadStore()
    @State private var upNext = UpNextStore()
    private let shouldRestoreLastSession: Bool

    #if os(visionOS)
        @State private var cinema = CinemaModel()
    #endif

    init() {
        // Route `AsyncImage` (which uses `URLSession.shared`) through our tuned cache.
        URLCache.shared = JellyfinClientFactory.urlCache
        shouldRestoreLastSession = !ProcessInfo.processInfo.arguments.contains("--gus-skip-session-restore")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(appNavigation)
                .environment(playbackRefresh)
                .environment(offlineDownloads)
                .environment(upNext)
            #if os(visionOS)
                .environment(cinema)
            #endif
                .task {
                    guard shouldRestoreLastSession else { return }
                    appModel.restoreLastSession()
                }
                .onOpenURL { url in
                    appNavigation.open(url: url)
                }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
        #elseif os(visionOS)
        .defaultSize(width: 1200, height: 820)
        #endif
        .gusCommands(appModel: appModel, navigation: appNavigation)

        #if os(visionOS)
            ImmersiveSpace(id: GusCinema.spaceID) {
                GusCinema()
                    .environment(cinema)
            }
            .immersionStyle(selection: .constant(.progressive), in: .progressive)
        #endif
    }
}
