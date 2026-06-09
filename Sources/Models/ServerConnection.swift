import Foundation

/// A Jellyfin server the user has connected to. Persisted (token-free) via `ServerStore`.
///
/// Mirrors the identity Swiftfin reads from `Paths.getPublicSystemInfo`
/// (`serverName` / `id`) — see `ConnectToServerViewModel` in the reference repo.
struct ServerConnection: Codable, Identifiable, Hashable {
    /// Backend provider that owns this server. Legacy records decode as Jellyfin.
    var providerKind: MediaProviderKind

    /// Server id reported by `PublicSystemInfo.id`.
    let id: String

    /// Human-readable server name (`PublicSystemInfo.serverName`).
    var name: String

    /// Normalized base URL, after following any connect-time redirect.
    var url: URL

    init(providerKind: MediaProviderKind = .jellyfin, id: String, name: String, url: URL) {
        self.providerKind = providerKind
        self.id = id
        self.name = name
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case providerKind
        case id
        case name
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerKind = try container.decodeIfPresent(MediaProviderKind.self, forKey: .providerKind) ?? .jellyfin
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(URL.self, forKey: .url)
    }
}
