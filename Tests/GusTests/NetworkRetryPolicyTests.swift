import Foundation
@testable import Gus
import Testing

@Suite("Network retry policy")
struct NetworkRetryPolicyTests {
    @Test("retries transient URL errors and returns the successful result")
    func retriesTransientErrors() async throws {
        let policy = NetworkRetryPolicy(maxRetries: 2, initialDelay: .zero) { _ in }
        var attempts = 0

        let value = try await policy.run {
            attempts += 1
            if attempts < 3 {
                throw URLError(.timedOut)
            }
            return "loaded"
        }

        #expect(value == "loaded")
        #expect(attempts == 3)
    }

    @Test("does not retry cancellation")
    func doesNotRetryCancellation() async {
        let policy = NetworkRetryPolicy(maxRetries: 2, initialDelay: .zero) { _ in }
        var attempts = 0

        do {
            _ = try await policy.run {
                attempts += 1
                throw CancellationError()
            } as String
            Issue.record("Expected cancellation to be thrown")
        } catch is CancellationError {
            #expect(attempts == 1)
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }

    @Test("does not retry non-transient URL errors")
    func doesNotRetryNonTransientErrors() async {
        let policy = NetworkRetryPolicy(maxRetries: 2, initialDelay: .zero) { _ in }
        var attempts = 0

        do {
            _ = try await policy.run {
                attempts += 1
                throw URLError(.badServerResponse)
            } as String
            Issue.record("Expected bad server response to be thrown")
        } catch let error as URLError {
            #expect(error.code == .badServerResponse)
            #expect(attempts == 1)
        } catch {
            Issue.record("Expected URLError, got \(error)")
        }
    }
}
