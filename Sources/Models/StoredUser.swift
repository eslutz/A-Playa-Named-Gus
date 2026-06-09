import Foundation

/// A signed-in user, persisted **without** the access token (the token lives in the
/// Keychain, keyed by `SessionCredential.account`).
struct StoredUser: Codable, Identifiable, Hashable {
    /// Backend provider that owns this user. Legacy records decode as Jellyfin.
    var providerKind: MediaProviderKind

    /// User id (`UserDto.id`).
    let id: String

    /// Display name (`UserDto.name`).
    var name: String

    /// Owning server id — links this user to a `ServerConnection`.
    let serverID: String

    /// Optional primary image tag for an avatar (`UserDto.primaryImageTag`).
    var primaryImageTag: String?

    init(
        providerKind: MediaProviderKind = .jellyfin,
        id: String,
        name: String,
        serverID: String,
        primaryImageTag: String? = nil
    ) {
        self.providerKind = providerKind
        self.id = id
        self.name = name
        self.serverID = serverID
        self.primaryImageTag = primaryImageTag
    }

    private enum CodingKeys: String, CodingKey {
        case providerKind
        case id
        case name
        case serverID
        case primaryImageTag
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerKind = try container.decodeIfPresent(MediaProviderKind.self, forKey: .providerKind) ?? .jellyfin
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        serverID = try container.decode(String.self, forKey: .serverID)
        primaryImageTag = try container.decodeIfPresent(String.self, forKey: .primaryImageTag)
    }
}
