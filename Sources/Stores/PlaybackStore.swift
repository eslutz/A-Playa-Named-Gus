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
    /// Set when playback reaches its natural end with nothing left to auto-play;
    /// the player view observes it to dismiss itself.
    private(set) var didFinishPlayback = false

    private(set) var item: MediaItem
    private let session: SessionStore
    private let playbackRefresh: PlaybackRefreshStore
    private let downloads: OfflineDownloadStore?
    private let nowPlaying = NowPlayingController()
    private let logger = Logger(category: .playback)
    private var reportContext: PlaybackReportContext?
    private var progressObserver: Any?
    private var endObserver: (any NSObjectProtocol)?
    private var failedEndObserver: (any NSObjectProtocol)?
    private var pauseStateObservation: NSKeyValueObservation?
    private var lastReportTask: Task<Void, Never>?
    private var didReportPause = false
    private var didReportStopped = false
    private var isTranscodedPlayback = false
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
        didFinishPlayback = false
        await loadPlayback(startTimeTicks: PlaybackTime.resumePositionTicks(for: item), replacingCurrentItem: false)
    }

    func selectAudioStream(index: Int?) async {
        guard streamSelection.audioStreamIndex != index else { return }
        if let index, await applyInPlaceMediaSelection(kind: .audio, streamIndex: index) {
            streamSelection.audioStreamIndex = index
            refreshReportedStreamSelection()
            return
        }
        streamSelection.audioStreamIndex = index
        await rebuildCurrentItemPreservingPosition()
    }

    func selectSubtitleStream(index: Int?) async {
        guard streamSelection.subtitleStreamIndex != index else { return }
        if await applyInPlaceMediaSelection(kind: .subtitle, streamIndex: index) {
            streamSelection.subtitleStreamIndex = index
            refreshReportedStreamSelection()
            return
        }
        streamSelection.subtitleStreamIndex = index
        await rebuildCurrentItemPreservingPosition()
    }

    /// Direct-played files expose their embedded tracks to AVKit, so switching can use
    /// `AVMediaSelection` in place — no multi-second stream rebuild. Transcoded streams
    /// carry only the negotiated tracks and must re-resolve against the server.
    private func applyInPlaceMediaSelection(kind: MediaStreamKind, streamIndex: Int?) async -> Bool {
        guard !isTranscodedPlayback, let playerItem = player?.currentItem else { return false }
        let characteristic: AVMediaCharacteristic = kind == .audio ? .audible : .legible
        guard let group = try? await playerItem.asset.loadMediaSelectionGroup(for: characteristic) else { return false }

        guard let streamIndex else {
            guard group.allowsEmptySelection else { return false }
            playerItem.select(nil, in: group)
            return true
        }

        let candidates = group.options.enumerated().map { offset, option in
            MediaSelectionCandidate(position: offset, languageTag: option.extendedLanguageTag)
        }
        guard let position = PlaybackMediaSelectionMatcher.candidatePosition(
            forStreamIndex: streamIndex,
            kind: kind,
            streams: item.mediaSources.first?.mediaStreams ?? [],
            candidates: candidates
        ), group.options.indices.contains(position) else { return false }

        playerItem.select(group.options[position], in: group)
        return true
    }

    /// Progress reports carry the stream selection; keep the context honest after an
    /// in-place switch that didn't restart the play session.
    private func refreshReportedStreamSelection() {
        guard let context = reportContext else { return }
        reportContext = PlaybackReportContext(
            itemID: context.itemID,
            mediaSourceID: context.mediaSourceID,
            playSessionID: context.playSessionID,
            playMethod: context.playMethod,
            streamSelection: streamSelection
        )
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
        // Close the server-side play session for the outgoing stream before the rebuild
        // reports a fresh start, so stream switches don't leak stale sessions.
        if let context = reportContext {
            reportContext = nil
            reportPlaybackStopped(context: context, positionTicks: ticks)
        }
        await loadPlayback(startTimeTicks: ticks, replacingCurrentItem: true)
    }

    private func loadPlayback(startTimeTicks: Int?, replacingCurrentItem: Bool) async {
        state = .loading
        stereoFallbackNotice = nil
        configureAudioSession()
        let diagnostics = DiagnosticsHub.shared
        diagnostics.record(.playbackStartRequested)
        let startupInterval = diagnostics.beginInterval("PlaybackStartup")

        guard let itemID = item.id else {
            diagnostics.endInterval("PlaybackStartup", startupInterval)
            diagnostics.record(.playbackFailed)
            state = .failed(String(localized: "This item can't be played.", comment: "Playback error: item has no playable identifier"))
            return
        }

        do {
            let localURL = downloads?.localFileURL(for: item, serverID: session.server.id, userID: session.user.id)
            let resolution: PlaybackSourceResolution?
            let playbackURL: URL
            if let localURL {
                resolution = nil
                playbackURL = localURL
                stereoPresentation = .native2D
            } else {
                let requestedPresentation = Media3DDetector.presentation(for: item, viewingMode: viewingMode)
                let maxStreamingBitrate = PlaybackQuality.stored.maxStreamingBitrate
                let remoteResolution = try await NetworkRetryPolicy.idempotent.run {
                    try await self.session.mediaProvider.resolvePlayback(
                        for: itemID,
                        maxStreamingBitrate: maxStreamingBitrate,
                        streamSelection: self.streamSelection,
                        startTimeTicks: startTimeTicks,
                        stereoLayout: requestedPresentation.resolutionStereoLayout
                    )
                }
                resolution = remoteResolution
                playbackURL = remoteResolution.url
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
            #if !os(macOS)
                // System title/info chrome; AVPlayerItem has no externalMetadata on
                // macOS (AVPlayerView's floating controls don't present it).
                playerItem.externalMetadata = item.externalPlayerMetadata
            #endif
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
            isTranscodedPlayback = localURL == nil && resolution?.isTranscoding == true
            installEndObserver(for: playerItem)
            installPauseObservation(on: player)
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
            diagnostics.endInterval("PlaybackStartup", startupInterval)
            diagnostics.record(.playbackStarted(
                usingTranscoding: resolution?.isTranscoding == true,
                usingLocalFile: localURL != nil
            ))
            reportPlaybackStart(context: context, player: player)
            player.play()
            await loadNextUpIfNeeded()
        } catch {
            diagnostics.endInterval("PlaybackStartup", startupInterval)
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return } // dismissed before playback resolved
            diagnostics.record(.playbackFailed)
            logger.error("Playback prepare failed: \(gusError.localizedDescription, privacy: .public)")
            state = .failed(gusError.localizedDescription)
        }
    }

    func teardown() {
        teardown(reportStopped: true)
    }

    private func teardown(reportStopped: Bool) {
        lastReportTask?.cancel()
        let finalTicks = currentPositionTicks()
        let context = reportContext
        removeProgressObserver()
        removeEndObserver()
        pauseStateObservation?.invalidate()
        pauseStateObservation = nil
        didReportPause = false
        isTranscodedPlayback = false
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

    // MARK: - Natural end (auto-play next / dismiss)

    private func installEndObserver(for playerItem: AVPlayerItem) {
        removeEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handlePlaybackEnded()
            }
        }
        failedEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                let message = error.map { GusError(from: $0).localizedDescription }
                    ?? String(localized: "Playback stopped unexpectedly.", comment: "Generic playback failure message")
                self?.state = .failed(message)
            }
        }
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        if let failedEndObserver {
            NotificationCenter.default.removeObserver(failedEndObserver)
        }
        failedEndObserver = nil
    }

    private func handlePlaybackEnded() {
        if PlaybackPreferences.autoPlaysNextEpisode, nextUpItem != nil {
            Task { await playNextUp() }
        } else {
            didFinishPlayback = true
        }
    }

    // MARK: - Immediate pause/resume reporting

    /// The 10-second progress tick is too slow for pause state — the server dashboard
    /// (and anything watching the session) would show "playing" for up to 10 s after a
    /// pause. Report transitions as they happen.
    private func installPauseObservation(on player: AVPlayer) {
        didReportPause = false
        pauseStateObservation?.invalidate()
        pauseStateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                guard let self, self.player === player, self.state == .ready else { return }
                switch status {
                case .paused where !self.didReportPause:
                    self.didReportPause = true
                    self.reportPlaybackProgress(positionTicks: self.currentPositionTicks(), isPaused: true)
                case .playing where self.didReportPause:
                    self.didReportPause = false
                    self.reportPlaybackProgress(positionTicks: self.currentPositionTicks(), isPaused: false)
                default:
                    break
                }
            }
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
        lastReportTask?.cancel()
        lastReportTask = Task {
            do {
                try await operation()
            } catch {
                let gusError = GusError(from: error)
                guard !gusError.isCancellation else { return }
                gusError.handleIfUnauthorized(session: session)
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
