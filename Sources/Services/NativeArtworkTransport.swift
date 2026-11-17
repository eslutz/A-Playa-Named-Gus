import CryptoKit
import Foundation

/// One credential lease owns one native session and memory-only URLCache.
/// No cache registry or per-launch disk directories survive account retirement.
@MainActor
final class NativeArtworkTransport {
    let session: URLSession
    let cache: URLCache
    let identity: String
    private(set) var isActive = true

    init(scope: AccountScope, generation: UUID) {
        let encoded = (try? JSONEncoder().encode([scope.serverID, scope.userID])) ?? Data()
        identity = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined() + "-" + generation.uuidString
        #if os(watchOS)
            let memory = 2 * 1024 * 1024
        #else
            let memory = 8 * 1024 * 1024
        #endif
        cache = URLCache(memoryCapacity: memory, diskCapacity: 0, directory: nil)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        // This transport also serves public Seerr artwork. Authentication belongs
        // on an origin-appropriate request, never on these shared session defaults.
        let cleanup = NativeArtworkSessionCleanup(cache: cache)
        session = URLSession(configuration: configuration, delegate: cleanup, delegateQueue: nil)
    }

    func invalidate() {
        guard isActive else { return }
        isActive = false
        session.invalidateAndCancel()
        cache.removeAllCachedResponses()
    }

    deinit { session.invalidateAndCancel() }
}

/// Clear again after URLSession cancellation so a late native task cannot leave
/// responses retained in an outgoing lease's cache.
private final class NativeArtworkSessionCleanup: NSObject, URLSessionDelegate {
    private let cache: URLCache
    init(cache: URLCache) {
        self.cache = cache
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        cache.removeAllCachedResponses()
    }
}
