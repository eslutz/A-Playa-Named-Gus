import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("Server discovery store")
struct ServerDiscoveryStoreTests {
    @Test("deduplicates discovered servers by id or URL")
    func deduplicatesByIDOrURL() async throws {
        let serverA = try discoveredServer(id: "server-a", name: "Office", url: "http://192.168.1.2:8096")
        let duplicateID = try discoveredServer(id: "server-a", name: "Office Alternate", url: "http://192.168.1.3:8096")
        let duplicateURL = try discoveredServer(id: "server-b", name: "Office Duplicate", url: "http://192.168.1.2:8096")
        let serverC = try discoveredServer(id: "server-c", name: "Living Room", url: "http://192.168.1.4:8096")
        let store = ServerDiscoveryStore(
            discoveryStream: {
                AsyncThrowingStream { continuation in
                    [serverA, duplicateID, duplicateURL, serverC].forEach { continuation.yield($0) }
                    continuation.finish()
                }
            }
        )

        await store.findServers()

        #expect(store.servers == [serverA, serverC])
        #expect(store.state == .found)
    }

    @Test("empty discovery results surface an empty state")
    func emptyDiscoveryResultsSurfaceEmptyState() async {
        let store = ServerDiscoveryStore(discoveryStream: { .finished })

        await store.findServers()

        #expect(store.servers.isEmpty)
        #expect(store.state == .empty)
    }

    @Test("discovery errors surface a failed state")
    func discoveryErrorsSurfaceFailedState() async {
        let store = ServerDiscoveryStore(
            discoveryStream: {
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: DiscoveryTestError.failed)
                }
            }
        )

        await store.findServers()

        #expect(store.servers.isEmpty)
        guard case .failed = store.state else {
            Issue.record("Expected discovery to fail")
            return
        }
    }

    @Test("cancelling discovery returns to idle")
    func cancellingDiscoveryReturnsToIdle() async throws {
        let server = try discoveredServer(id: "server-a", name: "Office", url: "http://192.168.1.2:8096")
        let store = ServerDiscoveryStore(
            discoveryStream: {
                AsyncThrowingStream { continuation in
                    continuation.yield(server)
                }
            }
        )

        store.start()
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.servers == [server])

        store.cancel()

        #expect(store.state == .idle)
    }

    private func discoveredServer(id: String, name: String, url: String) throws -> DiscoveredServer {
        try DiscoveredServer(id: id, name: name, url: #require(URL(string: url)))
    }
}

private enum DiscoveryTestError: Error {
    case failed
}

private extension AsyncThrowingStream where Element == DiscoveredServer, Failure == Error {
    static var finished: AsyncThrowingStream {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
