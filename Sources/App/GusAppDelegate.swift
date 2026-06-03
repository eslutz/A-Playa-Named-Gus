#if os(iOS) || os(visionOS)
    import UIKit

    final class GusAppDelegate: NSObject, UIApplicationDelegate {
        func application(
            _ application: UIApplication,
            handleEventsForBackgroundURLSession identifier: String,
            completionHandler: @escaping () -> Void
        ) {
            guard identifier == DownloadSessionCoordinator.backgroundIdentifier else {
                completionHandler()
                return
            }
            DownloadSessionCoordinator.shared.backgroundCompletionHandler = completionHandler
        }
    }
#endif
