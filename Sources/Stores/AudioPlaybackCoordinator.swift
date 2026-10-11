import Observation
import SwiftUI

/// Owns the audio queue independently of the visible player; closing keeps prepared audio.
@MainActor @Observable
final class AudioPlaybackCoordinator {
    private(set) var store: AudioPlayerStore?
    var isPresented = false
    private var preparation: Task<Void, Never>?

    func play(
        tracks: [MediaItem],
        startIndex: Int = 0,
        shuffled: Bool = false,
        localOnly: Bool = false,
        session: SessionStore,
        downloads: OfflineDownloadStore
    ) {
        stop()
        let player = AudioPlayerStore(session: session, tracks: tracks, startIndex: startIndex, downloads: downloads, localOnly: localOnly)
        if shuffled {
            player.toggleShuffle()
        }
        store = player
        isPresented = true
        preparation = Task { await player.start() }
    }

    func retry() {
        guard let store else { return }
        preparation?.cancel()
        preparation = Task { await store.start() }
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
