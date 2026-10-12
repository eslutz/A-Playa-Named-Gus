import AVFoundation
import Foundation

#if DEBUG
    struct PlaybackAudioSessionActivationResult: Sendable {
        let succeeded: Bool
        let errorDomain: String?
        let errorCode: Int?
    }
#endif

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

/// Run audio-session category changes away from MainActor and use native
/// asynchronous activation and deactivation.
@MainActor
enum PlaybackAudioSession {
    private static let queue = PlaybackAudioSessionQueue()

    #if DEBUG
        private(set) static var lastActivationResult: PlaybackAudioSessionActivationResult?
    #endif

    static func activate(video: Bool) async {
        #if DEBUG
            lastActivationResult = nil
        #endif
        let operation = queue.enqueue {
            #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
                let session = AVAudioSession.sharedInstance()
                #if os(watchOS)
                    try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
                #else
                    try? session.setCategory(.playback, mode: video ? .moviePlayback : .default)
                #endif
                #if DEBUG
                    let result = await withCheckedContinuation { (continuation: CheckedContinuation<PlaybackAudioSessionActivationResult, Never>) in
                        session.activate(options: []) { succeeded, error in
                            let error = error as NSError?
                            continuation.resume(returning: PlaybackAudioSessionActivationResult(
                                succeeded: succeeded,
                                errorDomain: error?.domain,
                                errorCode: error?.code
                            ))
                        }
                    }
                    await MainActor.run { lastActivationResult = result }
                #else
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        session.activate(options: []) { _, _ in continuation.resume() }
                    }
                #endif

            #endif
        }
        await operation.value
    }

    static func deactivate() {
        queue.enqueue {
            #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
                let session = AVAudioSession.sharedInstance()
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    session.deactivate(options: .notifyOthersOnDeactivation) { _, _ in continuation.resume() }
                }

            #endif
        }
    }
}
