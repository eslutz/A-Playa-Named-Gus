import Foundation

/// Retains the system completion until the coordinator drains all ordered file events.
/// Foundation-only so the same shared download store also builds on watchOS/macOS.
@MainActor
final class DownloadBackgroundEvents {
    static let shared = DownloadBackgroundEvents()
    private var completion: (() -> Void)?

    func register(_ completion: @escaping () -> Void) {
        // Apple delivers one completion per session wake. Preserve any prior wake.
        let previous = self.completion
        self.completion = {
            previous?()
            completion()
        }
    }

    func finish() {
        let callback = completion
        completion = nil
        callback?()
    }
}
