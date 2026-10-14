import Foundation

/// Presentation-only intent; it never edits server history before playback starts.
enum PlaybackStartIntent: String, Codable, Hashable, Sendable {
    case automatic
    case fromBeginning

    var startTimeTicks: Int? {
        self == .fromBeginning ? 0 : nil
    }
}

/// Shared by the detail label and video preparation, including an acknowledged local zero.
enum PlaybackActionPosition {
    static func ticks(for item: MediaItem, localTicks: Int?) -> Int? {
        let position: Int
        if let localTicks {
            position = max(0, localTicks)
        } else {
            guard let ticks = item.userData?.playbackPositionTicks, ticks > 0 else { return nil }
            position = ticks
        }
        if let duration = item.runTimeTicks, duration > 0, position >= duration {
            return 0
        }
        return position
    }
}

struct PlaylistPlaybackAction {
    let entryID: UUID?
    let hasProgress: Bool
    let isUnavailable: Bool
}

extension VideoPlaylist {
    var playbackAction: PlaylistPlaybackAction {
        guard let cursor, !cursor.finished, let savedID = cursor.entryID else {
            return PlaylistPlaybackAction(entryID: entries.first?.id, hasProgress: false, isUnavailable: false)
        }
        guard let index = entries.firstIndex(where: { $0.id == savedID }) else {
            return PlaylistPlaybackAction(entryID: nil, hasProgress: true, isUnavailable: true)
        }
        return PlaylistPlaybackAction(entryID: savedID, hasProgress: index > 0 || (cursor.positionTicks ?? 0) > 0, isUnavailable: false)
    }
}

/// Native drag payload is scoped to one account and one playlist occurrence.
struct PlaylistItemDrag: Codable, Sendable {
    let scope: AccountScope
    let playlistID: UUID
    let entryID: UUID

    struct Move: Equatable {
        let entryID: UUID
        let before: UUID?
    }

    func destination(in entries: [UUID], scope: AccountScope, playlistID: UUID, before: UUID?) -> Move? {
        guard self.scope == scope, self.playlistID == playlistID,
              let original = entries.firstIndex(of: entryID), before != entryID else { return nil }
        if let before, !entries.contains(before) {
            return nil
        }
        var updated = entries
        updated.remove(at: original)
        let destination = before.flatMap { updated.firstIndex(of: $0) } ?? updated.endIndex
        updated.insert(entryID, at: destination)
        guard updated != entries else { return nil }
        return Move(entryID: entryID, before: before)
    }
}
