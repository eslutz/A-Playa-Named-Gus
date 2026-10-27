import Foundation
import Observation

/// Order is fixed for a playback session; edits never redirect a running player.
struct PlaylistPlaybackSequence {
    private(set) var remainingIDs: [UUID]
    var currentID: UUID? {
        remainingIDs.first
    }

    init(entryIDs: [UUID], startID: UUID?, shuffled: Bool = false) {
        if shuffled {
            let first = startID.flatMap { entryIDs.contains($0) ? $0 : nil } ?? entryIDs.randomElement()
            remainingIDs = first.map { start in [start] + entryIDs.filter { $0 != start }.shuffled() } ?? []
            return
        }
        let start = startID.flatMap { entryIDs.firstIndex(of: $0) } ?? 0
        remainingIDs = Array(entryIDs.dropFirst(start))
    }

    mutating func remap(using transform: (UUID) -> UUID) {
        remainingIDs = remainingIDs.map(transform)
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
    private let serverLists: ServerMediaListsStore
    private let session: SessionStore
    private let downloads: OfflineDownloadStore
    private var sequence: PlaylistPlaybackSequence
    private var pending = false
    private var requestedTicks: Int?
    private var active = true
    private let startsFromBeginning: Bool

    init(playlistID: UUID, entryID: UUID?, fromBeginning: Bool, shuffled: Bool = false, playlists: VideoPlaylistsStore, session: SessionStore, downloads: OfflineDownloadStore, serverLists: ServerMediaListsStore = .shared) {
        self.playlistID = playlistID
        self.playlists = playlists
        self.serverLists = serverLists
        self.session = session
        self.downloads = downloads
        scope = session.references.scope
        serverLists.load(scope: scope)
        playlists.registerServerPlaylist(id: serverLists.resolvedID(playlistID, scope: scope), scope: scope)
        let playlist = serverLists.videoPlaylist(id: playlistID, scope: scope, supplemental: playlists)
        let entries = playlist?.entries ?? []
        let startID = entryID ?? (fromBeginning ? nil : playlist?.playbackAction.entryID)
        sequence = PlaylistPlaybackSequence(entryIDs: entries.map(\.id), startID: startID, shuffled: shuffled)
        startsFromBeginning = fromBeginning
    }

    private var stateID: UUID {
        serverLists.resolvedID(playlistID, scope: scope)
    }

    private func normalizeEntryIDs() {
        sequence.remap { serverLists.resolvedEntryID($0, inList: playlistID, scope: scope) }
    }

    func start(_ player: PlaybackStore) async {
        normalizeEntryIDs()
        let cursor = serverLists.videoPlaylist(id: playlistID, scope: scope, supplemental: playlists)?.cursor
        let ticks = startsFromBeginning || cursor?.finished == true ? 0 : (cursor?.entryID == sequence.currentID ? cursor?.positionTicks : nil)
        await prepareCurrent(player, ticks: ticks)
    }

    func completed(_ player: PlaybackStore) async {
        normalizeEntryIDs()
        guard active, !pending, let current = sequence.currentID else { return }
        let surviving = Set(serverLists.videoPlaylist(id: playlistID, scope: scope, supplemental: playlists)?.entries.map(\.id) ?? [])
        _ = sequence.advance(after: current, surviving: surviving)
        if sequence.currentID == nil {
            finished = true
            playlists.setCursor(id: stateID, entryID: nil, positionTicks: nil, finished: true, scope: scope)
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
        await prepareCurrent(player, ticks: player.hasStartedPlayback ? player.positionTicks : requestedTicks)
    }

    func checkpoint(_ player: PlaybackStore, activity: Bool = false) {
        normalizeEntryIDs()
        guard active, !pending, player.hasStartedPlayback, let id = sequence.currentID,
              serverLists.videoPlaylist(id: playlistID, scope: scope, supplemental: playlists)?.entries.contains(where: { $0.id == id }) == true else { return }
        playlists.setCursor(id: stateID, entryID: id, positionTicks: player.positionTicks, finished: false, scope: scope, activity: activity)
    }

    func stop(_ player: PlaybackStore) {
        checkpoint(player, activity: true)
        active = false
        player.teardown()
    }

    private func prepareCurrent(_ player: PlaybackStore, ticks: Int?) async {
        normalizeEntryIDs()
        guard active, !pending else { return }
        pending = true
        requestedTicks = ticks
        player.teardown()
        defer { pending = false }
        guard let current = sequence.currentID,
              let playlist = serverLists.videoPlaylist(id: playlistID, scope: scope, supplemental: playlists),
              let entry = playlist.entries.first(where: { $0.id == current })
        else {
            errorMessage = String(localized: "This playlist entry is no longer available.")
            return
        }
        guard playlist.entries.allSatisfy({ [.movie, .episode, .video].contains($0.reference.item.type) }) else {
            errorMessage = String(localized: "Play mixed media individually. Ordered video playback supports movies and episodes.")
            return
        }
        // Fail closed on unwritable storage, while keeping playback intent transient.
        guard playlists.canSavePlaybackState() else {
            errorMessage = playlists.errorMessage ?? String(localized: "Your changes couldn't be saved. Try again.")
            return
        }
        do {
            var item = entry.reference.item
            if downloads.localFileURL(for: item, serverID: scope.serverID, userID: scope.userID) == nil {
                item = try await session.references.currentItem(item)
            }
            try Task.checkCancellation()
            guard active else { return }
            normalizeEntryIDs()
            let resolvedCurrent = serverLists.resolvedEntryID(current, inList: playlistID, scope: scope)
            guard sequence.currentID == resolvedCurrent, serverLists.videoPlaylist(id: playlistID, scope: scope, supplemental: playlists)?.entries.contains(where: { $0.id == resolvedCurrent }) == true else {
                errorMessage = String(localized: "This playlist entry is no longer available.")
                return
            }
            guard ContentRatingGate.admitsStored(item) else { throw GusError.server(String(localized: "This item is restricted.")) }
            await player.playPlaylistItem(item, startTimeTicks: ticks)
            try Task.checkCancellation()
            guard active, player.hasStartedPlayback else { return }
            guard playlists.setCursor(id: stateID, entryID: resolvedCurrent, positionTicks: ticks, finished: false, scope: scope) else {
                errorMessage = playlists.errorMessage
                player.teardown()
                return
            }
        } catch {
            guard active, !GusError(from: error).isCancellation else { return }
            errorMessage = GusError(from: error).localizedDescription
        }
    }
}
