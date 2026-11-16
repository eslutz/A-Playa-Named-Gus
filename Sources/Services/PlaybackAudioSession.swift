import AVFoundation
import Foundation

struct PlaybackAudioSessionActivationError: LocalizedError {
    let underlyingError: NSError?

    var errorDescription: String? {
        String(localized: "Couldn't start audio playback. Try again.", comment: "Audio session activation failure")
    }

    var diagnosticDomain: Int {
        switch underlyingError?.domain {
        case NSURLErrorDomain: 1
        case AVFoundationErrorDomain: 2
        case NSOSStatusErrorDomain: 3
        default: 0
        }
    }
}

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
    func enqueue<Value: Sendable>(_ operation: @escaping @Sendable () async -> Value) -> Task<Value, Never> {
        let previous = pending
        let task = Task.detached {
            await previous?.value
            return await operation()
        }
        pending = Task.detached { _ = await task.value }
        return task
    }
}

/// Run audio-session category changes away from MainActor and use native
/// asynchronous activation and deactivation where available. OS 26 fallbacks
/// stay on the same detached queue so synchronous calls never block MainActor.
@MainActor
enum PlaybackAudioSession {
    private static let queue = PlaybackAudioSessionQueue()

    #if DEBUG
        private(set) static var lastActivationResult: PlaybackAudioSessionActivationResult?
    #endif

    static func activate(
        video: Bool,
        configureCategory: @escaping @Sendable (Bool) throws -> Void = { try PlaybackAudioSession.configureNativeCategory(video: $0) },
        activateSession: @escaping @Sendable () async throws -> Void = { try await PlaybackAudioSession.activateNativeSession() }
    ) async throws {
        #if DEBUG
            lastActivationResult = nil
        #endif
        let operation = queue.enqueue { () -> Result<Void, any Error> in
            do {
                try configureCategory(video)
                try await activateSession()
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        let result = await operation.value
        #if DEBUG
            switch result {
            case .success:
                lastActivationResult = PlaybackAudioSessionActivationResult(succeeded: true, errorDomain: nil, errorCode: nil)
            case let .failure(error):
                let nativeError: NSError?
                if let activationError = error as? PlaybackAudioSessionActivationError {
                    nativeError = activationError.underlyingError
                } else {
                    nativeError = error as NSError
                }
                lastActivationResult = PlaybackAudioSessionActivationResult(succeeded: false, errorDomain: nativeError?.domain, errorCode: nativeError?.code)
            }
        #endif
        do {
            try result.get()
        } catch {
            // Cancellation remains normal lifecycle control. A native refusal is
            // recoverable presentation, with its original error retained for evidence.
            if GusError(from: error).isCancellation || error is PlaybackAudioSessionActivationError {
                throw error
            }
            throw PlaybackAudioSessionActivationError(underlyingError: error as NSError)
        }
    }

    private nonisolated static func configureNativeCategory(video: Bool) throws {
        #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
            let session = AVAudioSession.sharedInstance()
            #if os(watchOS)
                try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            #else
                try session.setCategory(.playback, mode: video ? .moviePlayback : .default)
            #endif
        #endif
    }

    private nonisolated static func activateNativeSession() async throws {
        #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
            let session = AVAudioSession.sharedInstance()
            if #available(iOS 27.0, tvOS 27.0, visionOS 27.0, watchOS 5.0, *) {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    session.activate(options: []) { succeeded, error in
                        do {
                            try requireActivation(succeeded: succeeded, error: error)
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            } else {
                try session.setActive(true)
            }
        #endif
    }

    nonisolated static func requireActivation(succeeded: Bool, error: (any Error)?) throws {
        if let error {
            throw error
        }
        guard succeeded else {
            throw PlaybackAudioSessionActivationError(underlyingError: nil)
        }
    }

    static func deactivate() {
        queue.enqueue {
            #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
                let session = AVAudioSession.sharedInstance()
                if #available(iOS 27.0, tvOS 27.0, visionOS 27.0, watchOS 27.0, *) {
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
