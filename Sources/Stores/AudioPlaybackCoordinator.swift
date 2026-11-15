import Observation
import SwiftUI

/// Owns the audio queue independently of the visible player; closing keeps prepared audio.
@MainActor @Observable
final class AudioPlaybackCoordinator {
    private(set) var store: AudioPlayerStore?
    var isPresented = false
    private var preparation: Task<Void, Never>?
    private var startsShuffled = false

    func play(
        tracks: [MediaItem],
        startIndex: Int = 0,
        shuffled: Bool = false,
        localOnly: Bool = false,
        request: PlaybackRequest? = nil,
        continuation: AudioQueueContinuation? = nil,
        session: SessionStore,
        downloads: OfflineDownloadStore
    ) {
        stop()
        startsShuffled = shuffled
        let player = AudioPlayerStore(session: session, tracks: tracks, startIndex: startIndex, request: request ?? (tracks.indices.contains(startIndex) ? PlaybackRequest(item: tracks[startIndex]) : nil), continuation: continuation, downloads: downloads, localOnly: localOnly)
        store = player
        isPresented = true
        preparation = Task {
            if shuffled, !(await player.collectForShuffle()) {
                return
            }
            guard !Task.isCancelled else { return }
            await player.start()
        }
    }

    func retry() {
        guard let store else { return }
        preparation?.cancel()
        preparation = Task {
            if startsShuffled, !(await store.collectForShuffle()) {
                return
            }
            guard !Task.isCancelled else { return }
            await store.start()
        }
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
