import Foundation
@testable import Gus
import Testing

@MainActor
struct NativeArtworkTransportTests {
    @Test("same public URL is isolated by account and credential lease without disk or authentication defaults")
    func nativeCacheIdentity() throws {
        let account = AccountScope(serverID: "private-server", userID: "private-user")
        let first = NativeArtworkTransport(scope: account, generation: UUID())
        let nextLease = NativeArtworkTransport(scope: account, generation: UUID())
        let other = NativeArtworkTransport(scope: AccountScope(serverID: account.serverID, userID: "other-user"), generation: UUID())
        defer { first.invalidate(); nextLease.invalidate(); other.invalidate() }
        let url = try #require(URL(string: "https://images.example.net/poster.jpg?tag=current&maxWidth=260"))
        let request = URLRequest(url: url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "public, max-age=3600"]))
        first.cache.storeCachedResponse(CachedURLResponse(response: response, data: Data([1, 2, 3])), for: request)
        #expect(first.cache.cachedResponse(for: request)?.data == Data([1, 2, 3]))
        #expect(other.cache.cachedResponse(for: request) == nil)
        #expect(nextLease.cache.cachedResponse(for: request) == nil)
        #expect(first.identity != other.identity && first.identity != nextLease.identity)
        #expect(!first.identity.contains(account.serverID) && !first.identity.contains(account.userID))
        #expect(first.cache.diskCapacity == 0)
        #expect(first.cache.memoryCapacity <= 8 * 1024 * 1024)
        #expect(first.session.configuration.httpAdditionalHeaders?["Authorization"] == nil)
        #expect(first.session.configuration.httpCookieStorage == nil)
        #expect(first.session.configuration.urlCredentialStorage == nil)
        first.invalidate()
        first.invalidate()
        #expect(!first.isActive)
        #expect(first.cache.cachedResponse(for: request) == nil)
    }
}
