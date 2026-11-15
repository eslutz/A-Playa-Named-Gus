import AVFoundation
import Foundation

/// AVPlayerItem readiness and resume seeking share a native preparation budget,
/// independently of server negotiation. This owns no persistent observer or timer.
@MainActor
enum NativePlaybackPreparation {
    static func waitUntilReady(_ item: AVPlayerItem) async throws {
        let waiter = ReadinessWaiter()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter.continuation = continuation
                guard !Task.isCancelled else { waiter.finish(.failure(CancellationError())); return }
                waiter.observation = item.observe(\.status, options: [.initial, .new]) { item, _ in
                    let status = item.status
                    let error = item.error
                    Task { @MainActor in
                        switch status {
                        case .readyToPlay: waiter.finish(.success(()))
                        case .failed: waiter.finish(.failure(error ?? URLError(.cannotDecodeContentData)))
                        default: break
                        }
                    }
                }
            }
        } onCancel: { Task { @MainActor in waiter.finish(.failure(CancellationError())) } }
    }

    @MainActor
    private final class ReadinessWaiter {
        var observation: NSKeyValueObservation?
        var continuation: CheckedContinuation<Void, Error>?
        func finish(_ result: Result<Void, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            observation?.invalidate()
            observation = nil
            continuation.resume(with: result)
        }
    }

    static func prepare(_ player: AVPlayer, item: AVPlayerItem, startTicks: Int?, finishing: @escaping @MainActor () async throws -> Void = {}, seek: @escaping @MainActor (AVPlayer, Int) async throws -> Void) async throws {
        try await PlaybackDeadline.run(for: .seconds(45)) {
            try await waitUntilReady(item)
            if let startTicks {
                try await seek(player, startTicks)
            }
            try await finishing()
            try Task.checkCancellation()
            guard player.currentItem === item else { throw CancellationError() }
            if item.status == .failed {
                throw item.error ?? URLError(.cannotDecodeContentData)
            }
        }
    }
}
