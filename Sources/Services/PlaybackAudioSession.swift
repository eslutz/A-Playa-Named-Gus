import AVFoundation
import Foundation

/// Serialize activation and teardown across audio/video owners. An asynchronous
/// activation that finishes after dismissal must precede that owner's deactivation.
@MainActor
final class PlaybackAudioSessionQueue {
    private var pending: Task<Void, Never>?

    @discardableResult
    func enqueue(_ operation: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        let previous = pending
        let task = Task.detached {
            await previous?.value
            await operation()
        }
        pending = task
        return task
    }
}

/// AVAudioSession category changes and legacy activation can block. Run them away
/// from MainActor; use the native asynchronous activation APIs on OS 27 and newer.
@MainActor
enum PlaybackAudioSession {
    private static let queue = PlaybackAudioSessionQueue()

    static func activate(video: Bool) async {
        let operation = queue.enqueue {
            #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
                let session = AVAudioSession.sharedInstance()
                #if os(watchOS)
                    try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
                #else
                    try? session.setCategory(.playback, mode: video ? .moviePlayback : .default)
                #endif
                if #available(iOS 27, tvOS 27, visionOS 27, watchOS 5, *) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        session.activate(options: []) { _, _ in continuation.resume() }
                    }
                } else {
                    try? session.setActive(true)
                }
            #endif
        }
        await operation.value
    }

    static func deactivate() {
        queue.enqueue {
            #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
                let session = AVAudioSession.sharedInstance()
                if #available(iOS 27, tvOS 27, visionOS 27, watchOS 27, *) {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        session.deactivate(options: .notifyOthersOnDeactivation) { _, _ in continuation.resume() }
                    }
                } else {
                    try? session.setActive(false, options: .notifyOthersOnDeactivation)
                }
            #endif
        }
    }
}
