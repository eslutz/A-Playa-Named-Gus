import Foundation

/// Presentation-only intent; it never edits server history before playback starts.
enum PlaybackStartIntent: String, Codable, Hashable, Sendable {
    case automatic
    case fromBeginning

    var startTimeTicks: Int? {
        self == .fromBeginning ? 0 : nil
    }
}

/// One playback intent survives routing, queues, remote commands and native windows.
/// Track indexes are source-local; semantic snapshots are rematched against fresh metadata.
struct PlaybackRequest: Codable, Hashable, Sendable {
    enum SubtitleIntent: String, Codable, Hashable, Sendable { case automatic, off, explicit }
    var item: MediaItem
    var streamSelection: PlaybackStreamSelection
    var audioTrack: MediaStreamInfo?
    var subtitleTrack: MediaStreamInfo?
    var subtitleIntent: SubtitleIntent
    var start: PlaybackStartIntent
    var startPositionTicks: Int?
    var presentation: Stereo3DViewingMode
    var maxStreamingBitrate: Int?

    init(
        item: MediaItem,
        streamSelection: PlaybackStreamSelection = .none,
        audioTrack: MediaStreamInfo? = nil,
        subtitleTrack: MediaStreamInfo? = nil,
        subtitleIntent: SubtitleIntent? = nil,
        start: PlaybackStartIntent = .automatic,
        startPositionTicks: Int? = nil,
        presentation: Stereo3DViewingMode = .automatic,
        maxStreamingBitrate: Int? = nil
    ) {
        self.item = item
        self.streamSelection = streamSelection
        self.audioTrack = audioTrack
        self.subtitleTrack = subtitleTrack
        self.subtitleIntent = subtitleIntent ?? (streamSelection.subtitleStreamIndex == nil ? .automatic : streamSelection.subtitleStreamIndex == -1 ? .off : .explicit)
        self.start = start
        self.startPositionTicks = startPositionTicks.map { max(0, $0) }
        self.presentation = presentation
        self.maxStreamingBitrate = maxStreamingBitrate.map { max(1, $0) }
    }

    var requestedStartTicks: Int? {
        start == .fromBeginning ? 0 : startPositionTicks
    }

    /// A cut switch retains semantic intent but never reuses source-local indexes.
    func selectingMediaSource(_ id: String, startPositionTicks ticks: Int) -> PlaybackRequest {
        var result = self
        result.streamSelection = PlaybackStreamSelection(audioStreamIndex: nil, subtitleStreamIndex: subtitleIntent == .off ? -1 : nil, mediaSourceID: id)
        result.start = .automatic
        result.startPositionTicks = max(0, ticks)
        return result
    }

    /// Cross-device intent carries identity and choices, never file paths, image URLs,
    /// negotiated stream URLs, user data, or credentials from a populated MediaItem.
    var sharingIntent: PlaybackRequest {
        var result = self
        result.item = MediaItem(providerKind: item.providerKind, id: item.id, type: item.type)
        return result
    }

    @MainActor
    func selection(in source: MediaSource) -> PlaybackStreamSelection {
        var selection = streamSelection
        if let audioTrack {
            selection.audioStreamIndex = PlaybackTrackMemory.match(audioTrack, in: source.mediaStreams)
        }
        switch subtitleIntent {
        case .automatic: selection.subtitleStreamIndex = nil
        case .off: selection.subtitleStreamIndex = -1
        case .explicit:
            if let subtitleTrack {
                selection.subtitleStreamIndex = PlaybackTrackMemory.match(subtitleTrack, in: source.mediaStreams)
            }
        }
        return selection
    }
}

/// Identity uses the incoming command, never the player's changing progress snapshot.
/// A new cut, track or start command for the same item must retire its prior store.
struct PlaybackPresentationIdentity: Hashable {
    let request: PlaybackRequest
    let sessionGeneration: UUID
    var localOnly = false
    var playlistID: UUID?
    var playlistEntryID: UUID?
    var playlistFromBeginning = false
    var playlistShuffled = false
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
