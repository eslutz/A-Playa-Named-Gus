import SwiftUI

/// Gus — an Apple-first, multiplatform Jellyfin client.
///
/// Pure SwiftUI lifecycle (no AppDelegate). The root `AppModel` is created here and
/// injected via `@Environment`; on visionOS an `ImmersiveSpace` hosts the "Gus Cinema".
@main
struct GusApp: App {
    @State private var appModel = AppModel()
    @State private var playbackRefresh = PlaybackRefreshStore()

    #if os(visionOS)
        @State private var cinema = CinemaModel()
    #endif

    init() {
        // Route `AsyncImage` (which uses `URLSession.shared`) through our tuned cache.
        URLCache.shared = JellyfinClientFactory.urlCache
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(playbackRefresh)
            #if os(visionOS)
                .environment(cinema)
            #endif
                .task { appModel.restoreLastSession() }
        }

        #if os(visionOS)
            ImmersiveSpace(id: GusCinema.spaceID) {
                GusCinema()
                    .environment(cinema)
            }
            .immersionStyle(selection: .constant(.progressive), in: .progressive)
        #endif
    }
}
