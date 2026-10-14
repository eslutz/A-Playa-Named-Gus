import Observation
import SwiftUI

/// Owns the audio queue independently of the visible player; closing keeps prepared audio.
@MainActor @Observable
final class AudioPlaybackCoordinator {
    private(set) var store: AudioPlayerStore?
    var isPresented = false
    private var preparation: Task<Void, Never>?
    private var playbackStart: PlaybackStartIntent = .automatic

    func play(
        tracks: [MediaItem],
        startIndex: Int = 0,
        shuffled: Bool = false,
        localOnly: Bool = false,
        playbackStart: PlaybackStartIntent = .automatic,
        session: SessionStore,
        downloads: OfflineDownloadStore
    ) {
        stop()
        self.playbackStart = playbackStart
        let player = AudioPlayerStore(session: session, tracks: tracks, startIndex: startIndex, downloads: downloads, localOnly: localOnly)
        if shuffled {
            player.toggleShuffle()
        }
        store = player
        isPresented = true
        preparation = Task { await player.start(resume: playbackStart == .automatic) }
    }

    func retry() {
        guard let store else { return }
        preparation?.cancel()
        preparation = Task { await store.start(resume: playbackStart == .automatic) }
    }

    func close() {
        if store?.state == .loading || store?.state == .idle {
            stop()
        } else {
            isPresented = false
        }
    }

    func reopen() {
        if store != nil {
            isPresented = true
        }
    }

    func stop() {
        preparation?.cancel()
        preparation = nil
        store?.teardown()
        store = nil
        isPresented = false
    }
}
