import Foundation
import JellyfinAPI

/// Builds `JellyfinClient` instances from a server URL (and optional access token),
/// wiring in Gus's device identity and a shared, image-tuned `URLCache`.
///
/// Pattern reference: Swiftfin's `UserSession` / `ConnectToServerViewModel` construct a
/// `JellyfinClient.Configuration` the same way; Gus centralizes it here.
enum JellyfinClientFactory {
    /// Shared cache, sized generously for poster/backdrop images served with cache headers.
    /// `AsyncImage` requests flow through the same `URLSession`, so they hit this cache.
    /// Distinct `maxWidth` values create distinct cache entries and server renders; Gus
    /// keeps those values to a fixed set in `ImageURLBuilder.ImageContext`.
    static let urlCache: URLCache = URLCache(
        memoryCapacity: 64 * 1024 * 1024, // 64 MB
        diskCapacity: 512 * 1024 * 1024, // 512 MB
        directory: FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("GusImageCache", isDirectory: true)
    )

    static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = urlCache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        return configuration
    }

    /// Builds a client. Pass `accessToken` to construct an already-authenticated client
    /// (e.g. when restoring a session from the Keychain); omit it for connect / sign-in.
    static func makeClient(url: URL, accessToken: String? = nil) -> JellyfinClient {
        let configuration = JellyfinClient.Configuration(
            url: url,
            accessToken: accessToken,
            client: DeviceIdentity.clientName,
            deviceName: DeviceIdentity.deviceName,
            deviceID: DeviceIdentity.deviceID,
            version: DeviceIdentity.appVersion
        )
        return JellyfinClient(
            configuration: configuration,
            sessionConfiguration: makeSessionConfiguration()
        )
    }
}
