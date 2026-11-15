import AVFoundation
import MediaPlayer

/// Feeds the system Now Playing transport from an `AVPlayer`.
///
/// Replaces Swiftfin's custom NowPlayable plumbing with `MPNowPlayingInfoCenter`
/// (title/artist/duration/elapsed) + `MPRemoteCommandCenter` (play/pause/seek), driven by
/// an `AVPlayer` periodic time observer. `MediaPlayer` is available on all five platforms.
@MainActor
final class NowPlayingController {
    /// `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` are process-global, but the app
    /// has one controller per player store (video + audio). Tracking the active owner
    /// keeps a stopping controller from clearing transport state that another
    /// controller (e.g. video sitting in PiP while audio starts) has since claimed.
    private weak static var activeController: NowPlayingController?

    private weak var player: AVPlayer?
    private var timeObserver: Any?
    private var artworkTask: Task<Void, Never>?

    nonisolated static func mediaType(for item: MediaItem) -> MPNowPlayingInfoMediaType {
        item.isAudioPlayable ? .audio : .video
    }

    func start(
        player: AVPlayer,
        item: MediaItem,
        artworkURL: URL?,
        fallbackArtworkURLs: [URL] = [],
        artworkSession: URLSession = .shared,
        onNextTrack: (() -> Void)? = nil,
        onPreviousTrack: (() -> Void)? = nil
    ) {
        removeTimeObserver()
        Self.activeController = self
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
        info[MPNowPlayingInfoPropertyMediaType] = Self.mediaType(for: item).rawValue
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.timeControlStatus == .playing ? Double(player.rate) : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtwork(from: [artworkURL].compactMap { $0 } + fallbackArtworkURLs, session: artworkSession)

        configureRemoteCommands(for: player, onNextTrack: onNextTrack, onPreviousTrack: onPreviousTrack)

        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
            MainActor.assumeIsolated {
                self?.updateElapsed(time.seconds, rate: Double(player?.rate ?? 0))
            }
        }
    }

    func stop() {
        artworkTask?.cancel()
        artworkTask = nil
        removeTimeObserver()
        player = nil

        // Only the active owner may clear the global transport — another controller
        // may have taken over Now Playing since this one started.
        guard Self.activeController === self else { return }
        Self.activeController = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    private func removeTimeObserver() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    private func updateElapsed(_ seconds: Double, rate: Double) {
        guard seconds.isFinite, Self.activeController === self else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(from urls: [URL], session: URLSession) {
        guard !urls.isEmpty else { return }
        artworkTask = Task { [weak self] in
            for url in urls {
                guard !Task.isCancelled else { return }
                do {
                    let data: Data
                    if url.isFileURL {
                        data = try Data(contentsOf: url)
                    } else {
                        let result = try await session.data(from: url)
                        guard let response = result.1 as? HTTPURLResponse, (200 ..< 300).contains(response.statusCode), response.mimeType?.hasPrefix("image/") == true else { continue }
                        data = result.0
                    }
                    guard !Task.isCancelled else { return }
                    guard let artwork = NowPlayingArtworkFactory.artwork(from: data), let self, Self.activeController === self else { continue }
                    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    info[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                    return
                } catch {
                    if Task.isCancelled || GusError(from: error).isCancellation {
                        return
                    }
                }
            }
        }
    }

    private func configureRemoteCommands(
        for player: AVPlayer,
        onNextTrack: (() -> Void)?,
        onPreviousTrack: (() -> Void)?
    ) {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.removeTarget(nil)
        center.playCommand.addTarget { [weak player] _ in
            guard let player else { return .noActionableNowPlayingItem }
            player.play()
            return .success
        }

        center.pauseCommand.removeTarget(nil)
        center.pauseCommand.addTarget { [weak player] _ in
            guard let player else { return .noActionableNowPlayingItem }
            player.pause()
            return .success
        }

        center.togglePlayPauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.addTarget { [weak player] _ in
            guard let player else { return .noActionableNowPlayingItem }
            if player.rate == 0 {
                player.play()
            } else {
                player.pause()
            }
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.removeTarget(nil)
        center.skipForwardCommand.addTarget { [weak player] event in
            guard let player, let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            let target = player.currentTime() + CMTime(seconds: event.interval, preferredTimescale: 1)
            player.seek(to: target)
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.removeTarget(nil)
        center.skipBackwardCommand.addTarget { [weak player] event in
            guard let player, let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            let target = player.currentTime() - CMTime(seconds: event.interval, preferredTimescale: 1)
            player.seek(to: target)
            return .success
        }

        // Lock screen / Control Center scrubber.
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.addTarget { [weak player] event in
            guard let player, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            player.seek(
                to: CMTime(seconds: event.positionTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            return .success
        }

        center.nextTrackCommand.removeTarget(nil)
        center.nextTrackCommand.isEnabled = onNextTrack != nil
        if let onNextTrack {
            center.nextTrackCommand.addTarget { _ in
                Task { @MainActor in onNextTrack() }
                return .success
            }
        }

        center.previousTrackCommand.removeTarget(nil)
        center.previousTrackCommand.isEnabled = onPreviousTrack != nil
        if let onPreviousTrack {
            center.previousTrackCommand.addTarget { _ in
                Task { @MainActor in onPreviousTrack() }
                return .success
            }
        }
    }
}
