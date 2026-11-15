import Foundation

/// Resolution fallbacks inherit the caller's total budget. A known late response
/// may be released, but must not start another allocation after that budget ends.
enum PlaybackResolutionBudget {
    @TaskLocal static var deadline: ContinuousClock.Instant?
    @TaskLocal private static var ownerIsCurrent: (@MainActor @Sendable () -> Bool)?

    @MainActor
    static func check() throws {
        try Task.checkCancellation()
        if let ownerIsCurrent, !ownerIsCurrent() {
            throw CancellationError()
        }
        if let deadline, ContinuousClock.now >= deadline {
            throw PlaybackDeadline.Timeout()
        }
    }

    @MainActor
    static func withValue<Value: Sendable>(deadline: ContinuousClock.Instant, ownerIsCurrent: @escaping @MainActor @Sendable () -> Bool, operation: @MainActor () async throws -> Value) async rethrows -> Value {
        try await $deadline.withValue(deadline) {
            try await $ownerIsCurrent.withValue(ownerIsCurrent, operation: operation)
        }
    }
}

/// A wall-clock budget that can return even when a transport ignores cancellation.
/// Allocating requests may finish privately so a known late resource can be released.
@MainActor
enum PlaybackDeadline {
    struct Timeout: LocalizedError, Sendable {
        var errorDescription: String? {
            String(localized: "Playback took too long. Try again.")
        }
    }

    static func run<Value: Sendable>(
        for duration: Duration,
        cancelOperation: Bool = true,
        onDiscard: @escaping @MainActor (Value) async -> Void = { _ in },
        operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        let race = Race<Value>(cancelOperation: cancelOperation)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.continuation = continuation
                guard !Task.isCancelled else { race.cancel(); return }
                race.operation = Task {
                    do {
                        let value = try await operation()
                        if !race.finish(.success(value)) {
                            await onDiscard(value)
                        }
                    } catch {
                        _ = race.finish(.failure(error))
                    }
                    race.operation = nil
                }
                race.timer = Task {
                    do { try await Task.sleep(for: duration) } catch { return }
                    if race.finish(.failure(Timeout())), cancelOperation {
                        race.operation?.cancel()
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in race.cancel() }
        }
    }

    @MainActor
    private final class Race<Value: Sendable> {
        var continuation: CheckedContinuation<Value, Error>?
        var operation: Task<Void, Never>?
        var timer: Task<Void, Never>?
        let cancelOperation: Bool

        init(cancelOperation: Bool) {
            self.cancelOperation = cancelOperation
        }

        @discardableResult func finish(_ result: Result<Value, Error>) -> Bool {
            guard let continuation else { return false }
            self.continuation = nil
            timer?.cancel()
            timer = nil
            continuation.resume(with: result)
            return true
        }

        func cancel() {
            if finish(.failure(CancellationError())), cancelOperation {
                operation?.cancel()
            }
        }
    }
}
