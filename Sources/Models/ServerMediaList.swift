import Foundation

/// Native server playlists own their membership; Gus stores only account-scoped cursors and snapshots.
enum ServerMediaListKind: String, CaseIterable, Codable, Sendable {
    case playlist
}

/// The server's member identity. Recent Jellyfin versions use the media GUID for
/// playlist entries; older versions can return a distinct occurrence GUID.
struct ServerMediaListEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var item: MediaItem
}

struct ServerMediaList: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var kind: ServerMediaListKind
    var entries: [ServerMediaListEntry]
    var canEdit: Bool
    var entriesLoaded: Bool
}

/// Jellyfin uses both dashed GUIDs and compact GUIDs. Playlist occurrence APIs compare
/// compact strings, so every outbound list/entry ID uses the lowercased N format.
enum ServerMediaListID {
    static func uuid(_ string: String) -> UUID? {
        if let id = UUID(uuidString: string) {
            return id
        }
        guard string.count == 32, string.utf8.allSatisfy({
            (48 ... 57).contains($0) || (65 ... 70).contains($0) || (97 ... 102).contains($0)
        }) else { return nil }
        let boundaries = [8, 12, 16, 20]
        let dashed = string.enumerated().map { index, character in
            (boundaries.contains(index) ? "-" : "") + String(character)
        }.joined()
        return UUID(uuidString: dashed)
    }

    static func string(_ id: UUID) -> String {
        id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}
