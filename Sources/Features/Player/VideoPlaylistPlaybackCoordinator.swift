import Foundation
import Observation

/// Order is fixed for a playback session; edits never redirect a running player.
struct PlaylistPlaybackSequence {
    private(set) var remainingIDs: [UUID]
    var currentID: UUID? {
        remainingIDs.first
    }

    init(entryIDs: [UUID], startID: UUID?) {
        let start = startID.flatMap { entryIDs.firstIndex(of: $0) } ?? 0
        remainingIDs = Array(entryIDs.dropFirst(start))
    }

    /// A late completion for an earlier entry cannot consume the current entry.
    mutating func advance(after completedID: UUID, surviving: Set<UUID>) -> UUID? {
        guard currentID == completedID else { return currentID }
        remainingIDs.removeFirst()
        remainingIDs.removeAll { !surviving.contains($0) }
        return currentID
    }
}

@MainActor @Observable
final class VideoPlaylistPlaybackCoordinator {
    private(set) var errorMessage: String?
    private(set) var finished = false
    private let playlistID: UUID
    private let scope: AccountScope
    private let playlists: VideoPlaylistsStore
    private let session: SessionStore
    private let downloads: OfflineDownloadStore
    private var sequence: PlaylistPlaybackSequence
    private var pending = false
    private var active = true
    private let startsFromBeginning: Bool

    init(playlistID: UUID, entryID: UUID?, fromBeginning: Bool, playlists: VideoPlaylistsStore, session: SessionStore, downloads: OfflineDownloadStore) {
        self.playlistID = playlistID
        self.playlists = playlists
        self.session = session
        self.downloads = downloads
        scope = session.references.scope
        let entries = playlists.playlist(id: playlistID, scope: scope)?.entries ?? []
        sequence = PlaylistPlaybackSequence(entryIDs: entries.map(\.id), startID: entryID)
        startsFromBeginning = fromBeginning
    }

    func start(_ player: PlaybackStore) async {
        let cursor = playlists.playlist(id: playlistID, scope: scope)?.cursor
        let ticks = startsFromBeginning ? 0 : (cursor?.entryID == sequence.currentID ? cursor?.positionTicks : nil)
        await prepareCurrent(player, ticks: ticks)
    }

    func completed(_ player: PlaybackStore) async {
        guard active, !pending, let current = sequence.currentID else { return }
        let surviving = Set(playlists.playlist(id: playlistID, scope: scope)?.entries.map(\.id) ?? [])
        _ = sequence.advance(after: current, surviving: surviving)
        if sequence.currentID == nil {
            finished = true
            playlists.setCursor(id: playlistID, entryID: nil, positionTicks: nil, finished: true, scope: scope)
            player.teardown()
        } else {
            await prepareCurrent(player, ticks: 0)
        }
    }

    func skip(_ player: PlaybackStore) async {
        player.teardown()
        errorMessage = nil
        await completed(player)
    }

    func retry(_ player: PlaybackStore) async {
        errorMessage = nil
        await prepareCurrent(player, ticks: playlists.playlist(id: playlistID, scope: scope)?.cursor?.positionTicks)
    }

    func checkpoint(_ player: PlaybackStore, activity: Bool = false) {
        guard active, player.player != nil, let id = sequence.currentID,
              playlists.playlist(id: playlistID, scope: scope)?.entries.contains(where: { $0.id == id }) == true else { return }
        playlists.setCursor(id: playlistID, entryID: id, positionTicks: player.positionTicks, finished: false, scope: scope, activity: activity)
    }

    func stop(_ player: PlaybackStore) {
        checkpoint(player, activity: true)
        active = false
        player.teardown()
    }

    private func prepareCurrent(_ player: PlaybackStore, ticks: Int?) async {
        guard active, !pending else { return }
        pending = true
        player.teardown()
        defer { pending = false }
        guard let current = sequence.currentID,
              let entry = playlists.playlist(id: playlistID, scope: scope)?.entries.first(where: { $0.id == current })
        else {
            errorMessage = String(localized: "This playlist entry is no longer available.")
            return
        }
        // Commit the selected instance before resolving or starting playback.
        playlists.setCursor(id: playlistID, entryID: current, positionTicks: ticks, finished: false, scope: scope)
        do {
            var item = entry.reference.item
            if downloads.localFileURL(for: item, serverID: scope.serverID, userID: scope.userID) == nil {
                item = try await session.references.currentItem(item)
            }
            try Task.checkCancellation()
            guard active else { return }
            guard playlists.playlist(id: playlistID, scope: scope)?.entries.contains(where: { $0.id == current }) == true else {
                errorMessage = String(localized: "This playlist entry is no longer available.")
                return
            }
            guard ContentRatingGate.admitsStored(item) else { throw GusError.server(String(localized: "This item is restricted.")) }
            await player.playPlaylistItem(item, startTimeTicks: ticks)
        } catch {
            guard active, !GusError(from: error).isCancellation else { return }
            errorMessage = GusError(from: error).localizedDescription
        }
    }
}
