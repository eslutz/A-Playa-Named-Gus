import SwiftUI

// CoreSpotlight imports on tvOS but its indexing/continuation symbols are
// marked unavailable there, so the gate needs the explicit os check.
#if canImport(CoreSpotlight) && !os(tvOS)
    import CoreSpotlight
#endif

/// A Playa Named Gus — an Apple-first, multiplatform Jellyfin client.
///
/// Pure SwiftUI lifecycle (no AppDelegate). The root `AppModel` is created here and
/// injected via `@Environment`; on visionOS an `ImmersiveSpace` hosts the "Gus Cinema".
@main
struct GusApp: App {
    @State private var appModel = AppModel.shared
    @State private var appNavigation = AppNavigationModel.shared
    @State private var playbackRefresh = PlaybackRefreshStore()
    @State private var offlineDownloads = OfflineDownloadStore()
    @State private var upNext = UpNextStore()
    @State private var navigationPreferences = NavigationPreferencesStore()
    @AppStorage(AppearanceSetting.defaultsKey) private var appearanceRawValue = AppearanceSetting.system.rawValue
    private let shouldRestoreLastSession: Bool
    private let shouldInstallDebugPreviewSession: Bool
    private let shouldConnectToDemoServer: Bool
    private let launchRouteURL: URL?

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
            // "--gus-route <path>" opens a destination after launch — used by
            // Scripts/screenshots.sh to capture scenes without UI scripting. The value
            // is any gus:// path: fixed routes ("search", "settings") or content links
            // ("item/<id>", "play/<id>").
            if let flagIndex = arguments.firstIndex(of: "--gus-route"),
               arguments.indices.contains(flagIndex + 1)
            {
                launchRouteURL = URL(string: "gus://\(arguments[flagIndex + 1])")
            } else {
                launchRouteURL = nil
            }
        #else
            shouldInstallDebugPreviewSession = false
            shouldConnectToDemoServer = false
            launchRouteURL = nil
        #endif
    }

    private var appearance: AppearanceSetting {
        AppearanceSetting(rawValue: appearanceRawValue) ?? .system
    }

    private func continueActivity(_ activity: NSUserActivity) {
        guard let link = GusUserActivity.contentLink(
            from: activity,
            currentServerID: appModel.currentSession?.server.id,
            currentUserID: appModel.currentSession?.user.id
        ) else { return }
        appNavigation.open(link)
    }

    private func continueSpotlightActivity(_ activity: NSUserActivity) {
        #if canImport(CoreSpotlight) && !os(tvOS)
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let link = SpotlightIndexer.contentLink(
                      forSearchableItemIdentifier: identifier,
                      currentServerID: appModel.currentSession?.server.id,
                      currentUserID: appModel.currentSession?.user.id
                  )
            else { return }
            appNavigation.open(link)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(appNavigation)
                .environment(playbackRefresh)
                .environment(offlineDownloads)
                .environment(upNext)
                .environment(navigationPreferences)
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
                            if let launchRouteURL {
                                appNavigation.open(url: launchRouteURL)
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
                // Handoff continuations from another device's detail/player surface.
                .onContinueUserActivity(GusUserActivity.itemDetail) { activity in
                    continueActivity(activity)
                }
                .onContinueUserActivity(GusUserActivity.playback) { activity in
                    continueActivity(activity)
                }
                // Spotlight: tapping a donated library item opens its detail surface.
                .gusSpotlightContinuation { activity in
                    continueSpotlightActivity(activity)
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

private extension View {
    /// Registers the Core Spotlight continuation where the platform has Spotlight;
    /// passthrough elsewhere (watchOS, tvOS).
    @ViewBuilder
    func gusSpotlightContinuation(_ handler: @escaping (NSUserActivity) -> Void) -> some View {
        #if canImport(CoreSpotlight) && !os(tvOS)
            onContinueUserActivity(CSSearchableItemActionType, perform: handler)
        #else
            self
        #endif
    }
}
