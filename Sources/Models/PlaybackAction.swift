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
    /// Device-local presentation request checked against the reloaded photo's parent.
    var slideshowAlbumID: String? = nil

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
        result.slideshowAlbumID = nil
        result.item = MediaItem(providerKind: item.providerKind, id: item.id, type: item.type)
        return result
    }

    static func decodeSharingIntent(_ data: Data) -> PlaybackRequest? {
        guard data.count <= 8192,
              let decoded = try? JSONDecoder().decode(PlaybackRequest.self, from: data),
              decoded.startPositionTicks.map({ $0 >= 0 }) ?? true,
              decoded.streamSelection.audioStreamIndex.map({ $0 >= 0 }) ?? true,
              decoded.streamSelection.subtitleStreamIndex.map({ $0 >= -1 }) ?? true else { return nil }
        return decoded.sharingIntent
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

    static func canResume(at ticks: Int, durationTicks: Int?) -> Bool {
        guard ticks >= 0 else { return false }
        guard let durationTicks, durationTicks > 0 else { return true }
        return ticks < durationTicks
    }
}

/// A retained choice belongs to one active credential installation and purge epoch.
/// Only a matching player checkpoint or explicit remote readback consumes its start.
/// Source/semantic-track choices remain in the parent's base PlaybackRequest.
@MainActor
struct PlaybackStartOverride {
    let id = UUID()
    private let scope: AccountScope
    private let leaseGeneration: UUID
    private let writerToken: UUID
    private let itemID: String?
    private let requestedSourceID: String?
    private let sourceID: String?
    private let checkpointGeneration: UUID?
    private let ticks: Int
    private let start: PlaybackStartIntent

    init(request: PlaybackRequest, ticks: Int, fromBeginning: Bool, session: SessionStore, progress: OfflinePlaybackProgressStore, downloads: OfflineDownloadStore? = nil) {
        let scope = session.references.scope
        let itemID = request.item.id
        let sourceID = PlaybackChoicePosition.sourceID(for: request, session: session, downloads: downloads)
        self.scope = scope
        leaseGeneration = session.lease.generation
        writerToken = progress.writerToken(for: scope)
        self.itemID = itemID
        requestedSourceID = request.streamSelection.mediaSourceID
        self.sourceID = sourceID
        checkpointGeneration = itemID.flatMap { progress.playbackGeneration(forItemID: $0, scope: scope, mediaSourceID: sourceID) }
        self.ticks = max(0, ticks)
        start = fromBeginning ? .fromBeginning : .automatic
    }

    func applying(to request: PlaybackRequest, session: SessionStore, progress: OfflinePlaybackProgressStore, downloads: OfflineDownloadStore? = nil) -> PlaybackRequest {
        guard isCurrent(for: request, session: session, progress: progress, downloads: downloads),
              let itemID else { return request }
        let current = progress.playbackGeneration(forItemID: itemID, scope: scope, mediaSourceID: sourceID)
        guard current == nil || current == checkpointGeneration else { return request }
        var result = request
        result.start = start
        result.startPositionTicks = ticks
        return result
    }

    /// Remote confirmation is command/readback evidence, not local playing or progress.
    /// Missing source identity cannot confirm which version received the start command.
    func matchesRemoteReadback(request: PlaybackRequest, observed: RemoteSession, session: SessionStore, progress: OfflinePlaybackProgressStore, downloads: OfflineDownloadStore? = nil) -> Bool {
        guard isCurrent(for: request, session: session, progress: progress, downloads: downloads),
              let sourceID, observed.mediaSourceID == sourceID,
              observed.nowPlaying?.id == itemID, let position = observed.positionTicks, position >= 0 else { return false }
        let difference = position >= ticks ? position - ticks : ticks - position
        return difference <= PlaybackTime.ticks(fromSeconds: 5)
    }

    private func isCurrent(for request: PlaybackRequest, session: SessionStore, progress: OfflinePlaybackProgressStore, downloads: OfflineDownloadStore?) -> Bool {
        session.isActive && session.lease.generation == leaseGeneration && session.references.scope == scope
            && progress.writerToken(for: scope) == writerToken && request.item.id == itemID
            && request.streamSelection.mediaSourceID == requestedSourceID
            && PlaybackChoicePosition.sourceID(for: request, session: session, downloads: downloads) == sourceID
    }
}

/// Detail, Watch and CarPlay use the same source-specific position as preparation.
@MainActor
enum PlaybackChoicePosition {
    static func sourceID(for request: PlaybackRequest, session: SessionStore, downloads: OfflineDownloadStore? = nil) -> String? {
        request.streamSelection.mediaSourceID ?? downloadedRecord(for: request, session: session, downloads: downloads)?.mediaSourceID ?? request.item.mediaSources.first?.id
    }

    static func ticks(for request: PlaybackRequest, session: SessionStore, progress: OfflinePlaybackProgressStore, downloads: OfflineDownloadStore? = nil) -> Int? {
        position(for: request, session: session, progress: progress, downloads: downloads).ticks
    }

    /// Keep a checkpoint and its duration on the same cut, including when the server returns a different primary version.
    static func position(for request: PlaybackRequest, session: SessionStore, progress: OfflinePlaybackProgressStore, downloads: OfflineDownloadStore? = nil) -> (ticks: Int?, runTimeTicks: Int?) {
        let recorded = downloadedRecord(for: request, session: session, downloads: downloads)
        let sourceID = request.streamSelection.mediaSourceID ?? recorded?.mediaSourceID
        var item = recorded?.playbackItem ?? request.item
        if let sourceID {
            item.runTimeTicks = MediaPlaybackIdentity.runTimeTicks(for: item, mediaSourceID: sourceID)
        }
        let sourceScoped = recorded != nil || request.streamSelection.mediaSourceID != nil
        let checkpoint = sourceScoped ? item.id.flatMap { progress.positionTicks(forItemID: $0, scope: session.references.scope, mediaSourceID: sourceID) } : nil
        let ticks = PlaybackActionPosition.ticks(for: item, localTicks: request.requestedStartTicks ?? checkpoint ?? (sourceScoped ? 0 : nil))
        return (ticks, item.runTimeTicks)
    }

    private static func downloadedRecord(for request: PlaybackRequest, session: SessionStore, downloads: OfflineDownloadStore?) -> OfflineDownloadRecord? {
        guard let downloads, downloads.localFileURL(for: request.item, serverID: session.server.id, userID: session.user.id, mediaSourceID: request.streamSelection.mediaSourceID) != nil else { return nil }
        return downloads.record(for: request.item, serverID: session.server.id, userID: session.user.id, mediaSourceID: request.streamSelection.mediaSourceID)
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
