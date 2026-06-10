import AVFoundation
import MediaPlayer

/// Feeds the system Now Playing transport from an `AVPlayer`.
///
/// Replaces Swiftfin's custom NowPlayable plumbing with `MPNowPlayingInfoCenter`
/// (title/artist/duration/elapsed) + `MPRemoteCommandCenter` (play/pause/seek), driven by
/// an `AVPlayer` periodic time observer. `MediaPlayer` is available on all five platforms.
@MainActor
final class NowPlayingController {
    private weak var player: AVPlayer?
    private var timeObserver: Any?
    private var artworkTask: Task<Void, Never>?

    func start(player: AVPlayer, item: MediaItem, artworkURL: URL?) {
        self.player = player
        artworkTask?.cancel()

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = item.displayTitle
        if let series = item.seriesName {
            info[MPMediaItemPropertyArtist] = series
        } else if let artist = item.albumArtist ?? (item.artists.isEmpty ? nil : item.artists.joined(separator: ", ")) {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let album = item.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let ticks = item.runTimeTicks, ticks > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = Double(ticks) / 10_000_000
        }
        let isAudioItem = item.type == .audio
        info[MPNowPlayingInfoPropertyMediaType] = (isAudioItem ? MPNowPlayingInfoMediaType.audio : .video).rawValue
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtwork(from: artworkURL)

        configureRemoteCommands(for: player)

        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.updateElapsed(time.seconds, rate: Double(player.rate))
            }
        }
    }

    func stop() {
        artworkTask?.cancel()
        artworkTask = nil
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
    }

    private func updateElapsed(_ seconds: Double, rate: Double) {
        guard seconds.isFinite else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(from url: URL?) {
        guard let url else { return }
        artworkTask = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled, let artwork = NowPlayingArtworkFactory.artwork(from: data) else { return }
                await MainActor.run {
                    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    info[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            } catch {
                // Artwork is polish; playback and transport controls should continue.
            }
        }
    }

    private func configureRemoteCommands(for player: AVPlayer) {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.removeTarget(nil)
        center.playCommand.addTarget { _ in
            player.play()
            return .success
        }

        center.pauseCommand.removeTarget(nil)
        center.pauseCommand.addTarget { _ in
            player.pause()
            return .success
        }

        center.togglePlayPauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.addTarget { _ in
            if player.rate == 0 { player.play() } else { player.pause() }
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.removeTarget(nil)
        center.skipForwardCommand.addTarget { event in
            guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            let target = player.currentTime() + CMTime(seconds: event.interval, preferredTimescale: 1)
            player.seek(to: target)
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.removeTarget(nil)
        center.skipBackwardCommand.addTarget { event in
            guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            let target = player.currentTime() - CMTime(seconds: event.interval, preferredTimescale: 1)
            player.seek(to: target)
            return .success
        }

        // Lock screen / Control Center scrubber.
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            player.seek(
                to: CMTime(seconds: event.positionTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            return .success
        }
    }
}
