import Foundation

/// Identifies the Keychain entry that holds a user's access token.
///
/// The token itself is never stored in a `Codable` model — only this
/// `serverID:userID` account string, which `KeychainStore` uses as the
/// `kSecAttrAccount` for a `kSecClassGenericPassword` item.
struct SessionCredential: Codable, Hashable {

    let serverID: String
    let userID: String

    /// Keychain account string: `"<serverID>:<userID>"`.
    var account: String { "\(serverID):\(userID)" }

    init(serverID: String, userID: String) {
        self.serverID = serverID
        self.userID = userID
    }

    init(user: StoredUser) {
        self.serverID = user.serverID
        self.userID = user.id
    }
}
