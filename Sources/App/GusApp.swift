import SwiftUI

/// A Playa Named Gus — an Apple-first, multiplatform Jellyfin client.
///
/// Pure SwiftUI lifecycle (no AppDelegate). The root `AppModel` is created here and
/// injected via `@Environment`; on visionOS an `ImmersiveSpace` hosts the "Gus Cinema".
@main
struct GusApp: App {
    @State private var appModel = AppModel.shared
    @State private var appNavigation = AppNavigationModel()
    @State private var playbackRefresh = PlaybackRefreshStore()
    @State private var offlineDownloads = OfflineDownloadStore()
    @State private var upNext = UpNextStore()
    @AppStorage(AppearanceSetting.defaultsKey) private var appearanceRawValue = AppearanceSetting.system.rawValue
    private let shouldRestoreLastSession: Bool
    private let shouldInstallDebugPreviewSession: Bool
    private let shouldConnectToDemoServer: Bool
    private let launchRoute: AppRoute?

    #if os(visionOS)
        @State private var cinema = CinemaModel()
    #endif

    init() {
        // Route `AsyncImage` (which uses `URLSession.shared`) through our tuned cache.
        URLCache.shared = JellyfinClientFactory.urlCache
        DiagnosticsHub.shared.record(.appLaunched)
        DiagnosticsHub.shared.startMetricCollection()
        let arguments = ProcessInfo.processInfo.arguments
        shouldRestoreLastSession = !arguments.contains("--gus-skip-session-restore")
        #if DEBUG
            shouldInstallDebugPreviewSession = arguments.contains("--gus-debug-preview-session")
            shouldConnectToDemoServer = arguments.contains("--gus-demo-server")
            // "--gus-route search" opens a fixed destination after launch — used by
            // Scripts/screenshots.sh to capture scenes without UI scripting.
            if let flagIndex = arguments.firstIndex(of: "--gus-route"),
               arguments.indices.contains(flagIndex + 1)
            {
                launchRoute = AppRoute(rawValue: arguments[flagIndex + 1])
            } else {
                launchRoute = nil
            }
        #else
            shouldInstallDebugPreviewSession = false
            shouldConnectToDemoServer = false
            launchRoute = nil
        #endif
    }

    private var appearance: AppearanceSetting {
        AppearanceSetting(rawValue: appearanceRawValue) ?? .system
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
                    #if DEBUG
                        if shouldInstallDebugPreviewSession {
                            appModel.installDebugPreviewSession()
                            return
                        }
                        if shouldConnectToDemoServer {
                            await appModel.connectToLocalDemoServer()
                            if let launchRoute {
                                appNavigation.open(url: launchRoute.url)
                            }
                            return
                        }
                    #endif
                    guard shouldRestoreLastSession else { return }
                    appModel.restoreLastSession()
                }
                .onOpenURL { url in
                    appNavigation.open(url: url)
                }
                // nil follows the system; light/dark force the scheme on every platform.
                .preferredColorScheme(appearance.colorScheme)
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
