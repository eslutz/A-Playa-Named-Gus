import Foundation

enum AsyncStreamBridge {
    /// Bridges a producer task into an `AsyncThrowingStream` with standard lifetime
    /// rules: cancellation terminates quietly (no error), other failures finish the
    /// stream throwing, and consumer termination cancels the producer. Shared by the
    /// Quick Connect and server-discovery stores.
    static func stream<Element: Sendable>(
        _ produce: @escaping @Sendable (AsyncThrowingStream<Element, Error>.Continuation) async throws -> Void
    ) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await produce(continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
