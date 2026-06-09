import AVFoundation
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
    private(set) var nextUpItem: MediaItem?
    private(set) var isNextUpPromptVisible = false
    private(set) var stereoPresentation: Stereo3DPresentation = .native2D
    private(set) var stereoFallbackNotice: String?
    private(set) var viewingMode: Stereo3DViewingMode = .automatic

    private(set) var item: MediaItem
    private let session: SessionStore
    private let playbackRefresh: PlaybackRefreshStore
    private let downloads: OfflineDownloadStore?
    private let nowPlaying = NowPlayingController()
    private let logger = Logger(category: .playback)
    private var reportContext: PlaybackReportContext?
    private var progressObserver: Any?
    private var didReportStopped = false
    private var streamSelection = PlaybackStreamSelection.none

    init(item: MediaItem, session: SessionStore, playbackRefresh: PlaybackRefreshStore, downloads: OfflineDownloadStore? = nil) {
        self.item = item
        self.session = session
        self.playbackRefresh = playbackRefresh
        self.downloads = downloads
    }

    var audioOptions: [PlaybackStreamOption] {
        PlaybackStreamCatalog.audioOptions(for: item)
    }

    var subtitleOptions: [PlaybackStreamOption] {
        PlaybackStreamCatalog.subtitleOptions(for: item)
    }

    var chapterTargets: [PlaybackChapter] {
        PlaybackChapter.seekTargets(for: item)
    }

    var selectedAudioStreamIndex: Int? {
        streamSelection.audioStreamIndex
    }

    var selectedSubtitleStreamIndex: Int? {
        streamSelection.subtitleStreamIndex
    }

    var isSpatialPlaybackActive: Bool {
        stereoPresentation.showsSpatialBadge
    }

    var isFramePackedImmersivePlaybackActive: Bool {
        stereoPresentation.usesImmersiveFramePackedRenderer
    }

    func fallbackToWindowed2D(notice: String? = nil) {
        stereoPresentation = .native2D
        if let notice {
            stereoFallbackNotice = notice
        }
    }

    func prepare() async {
        guard player == nil else { return }
        didReportStopped = false
        await loadPlayback(startTimeTicks: PlaybackTime.resumePositionTicks(for: item), replacingCurrentItem: false)
    }

    func selectAudioStream(index: Int?) async {
        guard streamSelection.audioStreamIndex != index else { return }
        streamSelection.audioStreamIndex = index
        await rebuildCurrentItemPreservingPosition()
    }

    func selectSubtitleStream(index: Int?) async {
        guard streamSelection.subtitleStreamIndex != index else { return }
        streamSelection.subtitleStreamIndex = index
        await rebuildCurrentItemPreservingPosition()
    }

    func seek(to chapter: PlaybackChapter) async {
        guard let player else { return }
        await player.seek(
            to: CMTime(seconds: chapter.seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func selectViewingMode(_ mode: Stereo3DViewingMode) async {
        guard viewingMode != mode else { return }
        viewingMode = mode
        await rebuildCurrentItemPreservingPosition()
    }

    func playNextUp() async {
        guard let nextUpItem else { return }
        teardown(reportStopped: true)
        item = nextUpItem
        self.nextUpItem = nil
        isNextUpPromptVisible = false
        streamSelection = .none
        await prepare()
    }

    private func rebuildCurrentItemPreservingPosition() async {
        let ticks = currentPositionTicks()
        await loadPlayback(startTimeTicks: ticks, replacingCurrentItem: true)
    }

    private func loadPlayback(startTimeTicks: Int?, replacingCurrentItem: Bool) async {
        state = .loading
        stereoFallbackNotice = nil
        configureAudioSession()

        guard let itemID = item.id else {
            state = .failed(String(localized: "This item can't be played.", comment: "Playback error: item has no playable identifier"))
            return
        }

        do {
            let localURL = downloads?.localFileURL(for: item, serverID: session.server.id, userID: session.user.id)
            let resolution: PlaybackSourceResolution?
            let playbackURL: URL
            if let localURL {
                resolution = nil
                playbackURL = resolvePlaybackURL(local: localURL, remote: localURL)
                stereoPresentation = .native2D
            } else {
                let requestedPresentation = Media3DDetector.presentation(for: item, viewingMode: viewingMode)
                let remoteResolution = try await NetworkRetryPolicy.idempotent.run {
                    try await self.session.mediaProvider.resolvePlayback(
                        for: itemID,
                        maxStreamingBitrate: 120_000_000,
                        streamSelection: self.streamSelection,
                        startTimeTicks: startTimeTicks,
                        stereoLayout: requestedPresentation.resolutionStereoLayout
                    )
                }
                resolution = remoteResolution
                playbackURL = resolvePlaybackURL(local: nil, remote: remoteResolution.url)
                stereoPresentation = effectiveStereoPresentation(
                    requested: requestedPresentation,
                    resolution: remoteResolution
                )
                stereoFallbackNotice = fallbackNotice(
                    requested: requestedPresentation,
                    resolution: remoteResolution
                )
            }
            logger.info("Playing \(self.item.name ?? "item", privacy: .public) (local: \(localURL != nil, privacy: .public), transcoding: \(resolution?.isTranscoding == true, privacy: .public))")

            let playerItem = AVPlayerItem(url: playbackURL)
            let player: AVPlayer
            if let existing = self.player, replacingCurrentItem {
                existing.replaceCurrentItem(with: playerItem)
                player = existing
            } else {
                player = AVPlayer(playerItem: playerItem)
            }
            #if !os(visionOS)
                player.allowsExternalPlayback = true // AirPlay; not available on visionOS
            #endif
            player.automaticallyWaitsToMinimizeStalling = true
            self.player = player
            let context = PlaybackReportContext(
                itemID: itemID,
                mediaSourceID: resolution?.mediaSourceID,
                playSessionID: resolution?.playSessionID,
                playMethod: localURL != nil ? .directPlay : resolution?.playMethod ?? .directStream,
                streamSelection: streamSelection
            )
            reportContext = context

            if let resumeTicks = startTimeTicks {
                await player.seek(
                    to: CMTime(seconds: PlaybackTime.seconds(fromTicks: resumeTicks), preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
            }

            nowPlaying.start(player: player, item: item, artworkURL: session.mediaProvider.primaryImageURL(for: item, context: .nowPlayingArtwork))
            if progressObserver == nil {
                addProgressObserver(player: player)
            }
            state = .ready
            reportPlaybackStart(context: context, player: player)
            player.play()
            await loadNextUpIfNeeded()
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return } // dismissed before playback resolved
            logger.error("Playback prepare failed: \(gusError.localizedDescription, privacy: .public)")
            state = .failed(gusError.localizedDescription)
        }
    }

    func teardown() {
        teardown(reportStopped: true)
    }

    private func teardown(reportStopped: Bool) {
        let finalTicks = currentPositionTicks()
        let context = reportContext
        removeProgressObserver()
        player?.pause()
        nowPlaying.stop()
        player = nil
        reportContext = nil
        state = .idle
        stereoPresentation = .native2D
        stereoFallbackNotice = nil
        deactivateAudioSession()

        if reportStopped, let context, !didReportStopped {
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
                self.updateNextUpPrompt(time: time.seconds, player: player)
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
            try await self.session.mediaProvider.reportPlaybackStart(
                context: context,
                positionTicks: PlaybackTime.ticks(fromSeconds: player.currentTime().seconds),
                isPaused: false
            )
        }
    }

    private func reportPlaybackProgress(positionTicks: Int, isPaused: Bool) {
        guard let reportContext else { return }
        sendReport("progress") { [self] in
            try await self.session.mediaProvider.reportPlaybackProgress(
                context: reportContext,
                positionTicks: positionTicks,
                isPaused: isPaused
            )
        }
    }

    private func reportPlaybackStopped(context: PlaybackReportContext, positionTicks: Int) {
        sendReport("stopped") { [self] in
            try await self.session.mediaProvider.reportPlaybackStopped(context: context, positionTicks: positionTicks)
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

    private func effectiveStereoPresentation(
        requested: Stereo3DPresentation,
        resolution: PlaybackSourceResolution?
    ) -> Stereo3DPresentation {
        guard resolution?.stereoFallbackReason == nil else { return .native2D }
        if case .unsupported3D = requested {
            return .native2D
        }
        return requested
    }

    private func fallbackNotice(
        requested: Stereo3DPresentation,
        resolution: PlaybackSourceResolution?
    ) -> String? {
        if case .unsupported3D = requested {
            return String(
                localized: "3D not supported for this format - playing in 2D",
                comment: "Playback notice for unsupported stereoscopic video formats such as MVC"
            )
        }

        if resolution?.stereoFallbackReason != nil {
            return String(
                localized: "3D unavailable - playing in 2D",
                comment: "Playback notice when 3D direct play is unavailable and playback falls back to 2D"
            )
        }

        return nil
    }

    private func loadNextUpIfNeeded() async {
        guard nextUpItem == nil, item.type == .episode, let seriesID = item.seriesID else { return }
        do {
            let items = try await session.mediaProvider.nextUpItems(seriesID: seriesID, limit: 1)
            nextUpItem = items.first { $0.id != item.id }
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            logger.error("Next-up load failed: \(gusError.localizedDescription, privacy: .public)")
        }
    }

    private func updateNextUpPrompt(time: Double, player: AVPlayer) {
        guard nextUpItem != nil, !isNextUpPromptVisible, time.isFinite else { return }
        let duration = player.currentItem?.duration.seconds ?? PlaybackTime.seconds(fromTicks: item.runTimeTicks ?? 0)
        guard duration.isFinite, duration > 0 else { return }
        if duration - time <= 60 || time / duration >= 0.92 {
            isNextUpPromptVisible = true
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
