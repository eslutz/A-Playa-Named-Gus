import AVFoundation
import JellyfinAPI
import Observation
import OSLog

/// Owns the `AVPlayer` for a playback session and tears it down on dismiss.
///
/// Pure AVKit: resolves a URL via `StreamURLBuilder` (server transcode), drives an
/// `AVPlayer`, configures the audio session for background audio (iOS/tvOS/visionOS),
/// and feeds the system Now Playing transport via `NowPlayingController`.
@MainActor
@Observable
final class PlaybackStore {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var player: AVPlayer?

    let item: BaseItemDto
    private let session: SessionStore
    private let playbackRefresh: PlaybackRefreshStore
    private let nowPlaying = NowPlayingController()
    private let logger = Logger(category: .playback)
    private var reportContext: PlaybackReportContext?
    private var progressObserver: Any?
    private var didReportStopped = false

    init(item: BaseItemDto, session: SessionStore, playbackRefresh: PlaybackRefreshStore) {
        self.item = item
        self.session = session
        self.playbackRefresh = playbackRefresh
    }

    func prepare() async {
        guard player == nil else { return }
        state = .loading
        configureAudioSession()

        guard let itemID = item.id else {
            state = .failed(String(localized: "This item can't be played.", comment: "Playback error: item has no playable identifier"))
            return
        }

        do {
            let resolution = try await session.streamBuilder.resolvePlayback(for: itemID)
            logger.info("Playing \(self.item.name ?? "item", privacy: .public) (transcoding: \(resolution.isTranscoding, privacy: .public))")

            let player = AVPlayer(url: resolution.url)
            #if !os(visionOS)
                player.allowsExternalPlayback = true // AirPlay; not available on visionOS
            #endif
            player.automaticallyWaitsToMinimizeStalling = true
            self.player = player
            let context = PlaybackReportContext(
                itemID: itemID,
                mediaSourceID: resolution.mediaSourceID,
                playSessionID: resolution.playSessionID,
                playMethod: resolution.isTranscoding ? .transcode : .directStream
            )
            reportContext = context

            if let resumeTicks = PlaybackTime.resumePositionTicks(for: item) {
                await player.seek(
                    to: CMTime(seconds: PlaybackTime.seconds(fromTicks: resumeTicks), preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
            }

            nowPlaying.start(player: player, item: item)
            addProgressObserver(player: player)
            state = .ready
            reportPlaybackStart(context: context, player: player)
            player.play()
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return } // dismissed before playback resolved
            logger.error("Playback prepare failed: \(gusError.localizedDescription, privacy: .public)")
            state = .failed(gusError.localizedDescription)
        }
    }

    func teardown() {
        let finalTicks = currentPositionTicks()
        let context = reportContext
        removeProgressObserver()
        player?.pause()
        nowPlaying.stop()
        player = nil
        reportContext = nil
        state = .idle
        deactivateAudioSession()

        if let context, !didReportStopped {
            didReportStopped = true
            reportPlaybackStopped(context: context, positionTicks: finalTicks)
        }
    }

    private func addProgressObserver(player: AVPlayer) {
        let interval = CMTime(seconds: 10, preferredTimescale: 1)
        progressObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
            MainActor.assumeIsolated {
                guard let self, let player else { return }
                self.reportPlaybackProgress(
                    positionTicks: PlaybackTime.ticks(fromSeconds: time.seconds),
                    isPaused: player.rate == 0
                )
            }
        }
    }

    private func removeProgressObserver() {
        if let progressObserver {
            player?.removeTimeObserver(progressObserver)
        }
        progressObserver = nil
    }

    private func currentPositionTicks() -> Int {
        guard let player else { return 0 }
        return PlaybackTime.ticks(fromSeconds: player.currentTime().seconds)
    }

    private func reportPlaybackStart(context: PlaybackReportContext, player: AVPlayer) {
        sendReport("start") { [self] in
            try await self.session.client.send(
                Paths.reportPlaybackStart(
                    context.stateInfo(
                        positionTicks: PlaybackTime.ticks(fromSeconds: player.currentTime().seconds),
                        isPaused: false
                    )
                )
            )
        }
    }

    private func reportPlaybackProgress(positionTicks: Int, isPaused: Bool) {
        guard let reportContext else { return }
        sendReport("progress") { [self] in
            try await self.session.client.send(
                Paths.reportPlaybackProgress(
                    reportContext.stateInfo(positionTicks: positionTicks, isPaused: isPaused)
                )
            )
        }
    }

    private func reportPlaybackStopped(context: PlaybackReportContext, positionTicks: Int) {
        sendReport("stopped") { [self] in
            try await self.session.client.send(Paths.reportPlaybackStopped(context.stopInfo(positionTicks: positionTicks)))
            await MainActor.run {
                self.playbackRefresh.markPlaybackProgressChanged()
            }
        }
    }

    private func sendReport(_ kind: String, operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                let gusError = GusError(from: error)
                guard !gusError.isCancellation else { return }
                logger.error("Playback \(kind, privacy: .public) report failed: \(gusError.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Audio session (no-op on macOS, which has no AVAudioSession)

    private func configureAudioSession() {
        #if os(iOS) || os(tvOS) || os(visionOS)
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback)
            try? session.setActive(true)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS) || os(tvOS) || os(visionOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
