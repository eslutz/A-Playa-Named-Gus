import AVFoundation
import Observation
import SwiftUI

/// Owns the audio queue independently of the visible player; closing keeps prepared audio.
@MainActor @Observable
final class AudioPlaybackCoordinator {
    private(set) var store: AudioPlayerStore?
    var isPresented = false
    private var preparation: Task<Void, Never>?
    private var startsShuffled = false

    #if os(iOS)
        private var routeChanges: Task<Void, Never>?
    #endif

    @discardableResult
    func play(
        tracks: [MediaItem],
        startIndex: Int = 0,
        shuffled: Bool = false,
        localOnly: Bool = false,
        request: PlaybackRequest? = nil,
        continuation: AudioQueueContinuation? = nil,
        session: SessionStore,
        downloads: OfflineDownloadStore,
        presentOnPhone: Bool = true
    ) -> AudioPlayerStore {
        stop()
        startsShuffled = shuffled
        let player = AudioPlayerStore(session: session, tracks: tracks, startIndex: startIndex, request: request ?? (tracks.indices.contains(startIndex) ? PlaybackRequest(item: tracks[startIndex]) : nil), continuation: continuation, downloads: downloads, localOnly: localOnly)
        store = player
        isPresented = presentOnPhone
        session.onInvalidation(of: self) { [weak player] owner in
            if let player, owner.store === player {
                owner.stop()
            }
        }
        #if os(iOS)
            observeRouteChanges(for: player)
        #endif
        preparation = Task {
            if shuffled, !(await player.collectForShuffle()) {
                return
            }
            guard !Task.isCancelled else { return }
            await player.start()
        }
        return player
    }

    func waitForPreparation(of player: AudioPlayerStore) async {
        guard store === player else { return }
        await preparation?.value
    }

    #if os(iOS)
        private func observeRouteChanges(for player: AudioPlayerStore) {
            let session = AVAudioSession.sharedInstance()
            routeChanges = Task { [weak self, weak player] in
                for await notification in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
                    guard let self, let player, self.store === player else { return }
                    guard let previous = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
                          previous.outputs.contains(where: { $0.portType == .carAudio }),
                          !session.currentRoute.outputs.contains(where: { $0.portType == .carAudio })
                    else { continue }
                    player.pauseForRouteLoss()
                }
            }
        }
    #endif

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
        #if os(iOS)
            routeChanges?.cancel()
            routeChanges = nil
        #endif
        preparation?.cancel()
        preparation = nil
        store?.teardown()
        store = nil
        isPresented = false
    }
}
