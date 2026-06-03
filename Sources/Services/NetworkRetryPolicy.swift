import Foundation

/// Opt-in retry wrapper for idempotent foreground loads.
///
/// `waitsForConnectivity` already lets a request wait for the network. This policy only
/// retries operations that actually fail with a transient `URLError`.
struct NetworkRetryPolicy {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    static let idempotent = NetworkRetryPolicy(maxRetries: 2, initialDelay: .milliseconds(250))

    let maxRetries: Int
    let initialDelay: Duration
    private let sleep: Sleep

    init(
        maxRetries: Int = 2,
        initialDelay: Duration = .milliseconds(250),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.maxRetries = maxRetries
        self.initialDelay = initialDelay
        self.sleep = sleep
    }

    func run<Value>(_ operation: () async throws -> Value) async throws -> Value {
        var attempt = 0

        while true {
            do {
                return try await operation()
            } catch {
                if error is CancellationError {
                    throw error
                }

                guard attempt < maxRetries, Self.isTransient(error) else {
                    throw error
                }

                attempt += 1
                try await sleep(delay(forAttempt: attempt))
            }
        }
    }

    static func isTransient(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
            return true
        case .cancelled:
            return false
        default:
            return false
        }
    }

    private func delay(forAttempt attempt: Int) -> Duration {
        guard attempt > 1 else { return initialDelay }
        return initialDelay * (1 << (attempt - 1))
    }
}
