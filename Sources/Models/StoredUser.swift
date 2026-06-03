import Foundation

/// A signed-in user, persisted **without** the access token (the token lives in the
/// Keychain, keyed by `SessionCredential.account`).
struct StoredUser: Codable, Identifiable, Hashable {
    /// User id (`UserDto.id`).
    let id: String

    /// Display name (`UserDto.name`).
    var name: String

    /// Owning server id — links this user to a `ServerConnection`.
    let serverID: String

    /// Optional primary image tag for an avatar (`UserDto.primaryImageTag`).
    var primaryImageTag: String?

    init(id: String, name: String, serverID: String, primaryImageTag: String? = nil) {
        self.id = id
        self.name = name
        self.serverID = serverID
        self.primaryImageTag = primaryImageTag
    }
}
