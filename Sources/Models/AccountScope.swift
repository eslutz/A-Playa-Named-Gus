import Foundation

/// Identifies the (server, user) pair that scopes per-account on-device state such as
/// Up Next pins and navigation preferences. `storageKey` is filesystem-safe and stable —
/// it must not change format, since persisted files are named with it.
struct AccountScope: Hashable {
    let serverID: String
    let userID: String

    var storageKey: String {
        let rawValue = "\(serverID)__\(userID)"
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return rawValue.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? String(scalar) : "_"
        }
        .joined()
    }
}
