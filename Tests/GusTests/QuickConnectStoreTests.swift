import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("Quick Connect store")
struct QuickConnectStoreTests {
    @Test("decodes the enabled endpoint as a JSON boolean")
    func decodesEnabledEndpoint() throws {
        #expect(try QuickConnectAvailability.isEnabled(Data("true".utf8)))
        #expect(!(try QuickConnectAvailability.isEnabled(Data("false".utf8))))
    }

    @Test("marks disabled servers unavailable")
    func disabledServersAreUnavailable() async throws {
        let store = try QuickConnectStore(
            server: server(),
            availabilityLoader: { false },
            eventStream: { .finished },
            signIn: { _, _ in Issue.record("Disabled Quick Connect should not sign in") }
        )

        await store.refreshAvailability()

        #expect(store.availability == .unavailable)
        #expect(!store.isAvailable)
    }

    @Test("updates the polling code and signs in with the authenticated secret")
    func signsInWithAuthenticatedSecret() async throws {
        var signedInSecret: String?
        let store = try QuickConnectStore(
            server: server(),
            availabilityLoader: { true },
            eventStream: {
                AsyncThrowingStream { continuation in
                    continuation.yield(.polling(code: "123 456"))
                    continuation.yield(.authenticated(secret: "secret-1"))
                    continuation.finish()
                }
            },
            signIn: { _, secret in
                signedInSecret = secret
            }
        )

        await store.performQuickConnect()

        #expect(store.state == .signedIn)
        #expect(signedInSecret == "secret-1")
    }

    @Test("cancelling polling returns the store to idle")
    func cancellingPollingReturnsToIdle() async throws {
        let store = try QuickConnectStore(
            server: server(),
            availabilityLoader: { true },
            eventStream: {
                AsyncThrowingStream { continuation in
                    continuation.yield(.polling(code: "654 321"))
                }
            },
            signIn: { _, _ in Issue.record("Cancelled Quick Connect should not sign in") }
        )

        store.start()
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.state == .polling(code: "654 321"))

        store.cancel()

        #expect(store.state == .idle)
    }

    private func server() throws -> ServerConnection {
        try ServerConnection(
            id: "server-1",
            name: "Psych Office",
            url: #require(URL(string: "https://jellyfin.example.com"))
        )
    }
}

private extension AsyncThrowingStream where Element == QuickConnectFlowEvent, Failure == Error {
    static var finished: AsyncThrowingStream {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
