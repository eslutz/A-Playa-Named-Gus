import Foundation

// Typed navigation values so a `NavigationStack` can distinguish "open this library"
// from "open this item" even though both wrap a `MediaItem`.
//
// Hashing/equality is by item id.

struct LibraryRef: Hashable, Identifiable {
    let item: MediaItem
    /// Deterministic for id-less items: `sheet(item:)`/`fullScreenCover(item:)` compare
    /// ids across body evaluations, so a fresh UUID per access would re-present forever.
    var id: String {
        item.id ?? "untitled-\(item.name ?? item.type?.rawValue ?? "library")"
    }

    static func == (lhs: LibraryRef, rhs: LibraryRef) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Codable so macOS can hand the ref to the dedicated player window scene
/// (`WindowGroup(for:)` round-trips presented values through Codable).
struct ItemRef: Hashable, Identifiable, Codable {
    let item: MediaItem
    /// Local playback intent and account identity survive a macOS player window.
    var localOnly: Bool? = nil
    var serverID: String? = nil
    var userID: String? = nil
    var playlistID: UUID? = nil
    var playlistEntryID: UUID? = nil
    var playlistFromBeginning: Bool? = nil
    /// See LibraryRef.id — must stay stable across accesses.
    var id: String {
        if let playlistID, let playlistEntryID {
            return "playlist-\(playlistID)-\(playlistEntryID)"
        }
        return item.id ?? "untitled-\(item.name ?? item.type?.rawValue ?? "item")"
    }

    static func == (lhs: ItemRef, rhs: ItemRef) -> Bool {
        lhs.id == rhs.id && lhs.serverID == rhs.serverID && lhs.userID == rhs.userID && lhs.localOnly == rhs.localOnly && lhs.playlistFromBeginning == rhs.playlistFromBeginning
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(serverID)
        hasher.combine(userID)
        hasher.combine(localOnly)
        hasher.combine(playlistFromBeginning)
    }
}

struct VideoPlaylistRef: Hashable {
    let id: UUID
}
