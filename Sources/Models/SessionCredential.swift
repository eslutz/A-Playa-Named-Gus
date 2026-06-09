import Foundation

/// Identifies the Keychain entry that holds a user's access token.
///
/// The token itself is never stored in a `Codable` model — only this
/// `serverID:userID` account string, which `KeychainStore` uses as the
/// `kSecAttrAccount` for a `kSecClassGenericPassword` item.
struct SessionCredential: Codable, Hashable {
    let providerKind: MediaProviderKind
    let serverID: String
    let userID: String

    /// Keychain account string: `"<provider>:<serverID>:<userID>"`.
    var account: String {
        "\(providerKind.rawValue):\(serverID):\(userID)"
    }

    /// Legacy pre-provider account string. Used only to migrate existing Jellyfin tokens.
    var legacyAccount: String {
        "\(serverID):\(userID)"
    }

    init(providerKind: MediaProviderKind = .jellyfin, serverID: String, userID: String) {
        self.providerKind = providerKind
        self.serverID = serverID
        self.userID = userID
    }

    init(user: StoredUser) {
        providerKind = user.providerKind
        serverID = user.serverID
        userID = user.id
    }

    private enum CodingKeys: String, CodingKey {
        case providerKind
        case serverID
        case userID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerKind = try container.decodeIfPresent(MediaProviderKind.self, forKey: .providerKind) ?? .jellyfin
        serverID = try container.decode(String.self, forKey: .serverID)
        userID = try container.decode(String.self, forKey: .userID)
    }
}
