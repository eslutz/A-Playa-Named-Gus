import Foundation

/// A Jellyfin server the user has connected to. Persisted (token-free) via `ServerStore`.
///
/// Mirrors the identity Swiftfin reads from `Paths.getPublicSystemInfo`
/// (`serverName` / `id`) — see `ConnectToServerViewModel` in the reference repo.
struct ServerConnection: Codable, Identifiable, Hashable {
    /// Server id reported by `PublicSystemInfo.id`.
    let id: String

    /// Human-readable server name (`PublicSystemInfo.serverName`).
    var name: String

    /// Normalized base URL, after following any connect-time redirect.
    var url: URL
}
