#if os(iOS)
    import Intents
    import UIKit

    /// SwiftUI owns the UI; UIKit bridges background URLSession wake events and Siri intents.
    @MainActor
    final class DownloadAppDelegate: NSObject, UIApplicationDelegate {
        func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
            intent is INPlayMediaIntent ? SiriMediaHandler() : nil
        }

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
