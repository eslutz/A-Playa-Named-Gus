import Foundation

/// The backend family that owns a server, account, media item, or persisted artifact.
enum MediaProviderKind: String, Codable, Hashable {
    case jellyfin
}
