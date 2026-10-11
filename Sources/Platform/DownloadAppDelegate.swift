#if os(iOS)
    import UIKit

    /// SwiftUI owns the UI; UIKit bridges only background URLSession wake events.
    @MainActor
    final class DownloadAppDelegate: NSObject, UIApplicationDelegate {
        func application(
            _ application: UIApplication,
            handleEventsForBackgroundURLSession identifier: String,
            completionHandler: @escaping () -> Void
        ) {
            guard identifier == DownloadSessionCoordinator.backgroundIdentifier else {
                completionHandler()
                return
            }
            DownloadBackgroundEvents.shared.register(completionHandler)
            OfflineDownloadStore.shared.bootstrapBackgroundTransfers()
        }
    }
#endif
