import AVFoundation
import Foundation
import Observation
import OSLog

/// Pure queue-ordering logic for audio playback, separated from the player so the
/// shuffle/repeat/advance semantics stay unit-testable.
struct AudioQueue {
    enum RepeatMode: CaseIterable, Equatable {
        case off
        case one
        case all
    }

    private(set) var tracks: [MediaItem]
    /// Playback order, as indices into `tracks`.
    private(set) var order: [Int]
    /// Current position within `order`.
    private(set) var position: Int
    private(set) var isShuffled = false
    var repeatMode: RepeatMode = .off

    init(tracks: [MediaItem], startIndex: Int = 0) {
        self.tracks = tracks
        order = Array(tracks.indices)
        position = tracks.isEmpty ? 0 : min(max(0, startIndex), tracks.count - 1)
    }

    var currentTrack: MediaItem? {
        guard order.indices.contains(position) else { return nil }
        return tracks[order[position]]
    }

    var hasPrevious: Bool {
        position > 0
    }

    var hasNext: Bool {
        repeatMode == .all || position + 1 < order.count
    }

    /// Advances after a track finishes (`automatic`) or a user skip. Returns the next
    /// track, or `nil` when the queue is exhausted. Repeat-one only loops on automatic
    /// completion — a user skip always moves forward.
    mutating func advance(automatic: Bool) -> MediaItem? {
        if automatic, repeatMode == .one {
            return currentTrack
        }
        if position + 1 < order.count {
            position += 1
            return currentTrack
        }
        if repeatMode == .all, !order.isEmpty {
            position = 0
            return currentTrack
        }
        return nil
    }

    /// Steps back one track, staying on the first track at the queue head.
    mutating func goBack() -> MediaItem? {
        if position > 0 {
            position -= 1
        }
        return currentTrack
    }

    /// Jumps directly to a track by its identifier.
    mutating func jump(toTrackID id: String) -> MediaItem? {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == id }),
              let orderPosition = order.firstIndex(of: trackIndex)
        else { return nil }
        position = orderPosition
        return currentTrack
    }

    /// Shuffles the remaining order, keeping the current track first.
    mutating func shuffle(using generator: inout some RandomNumberGenerator) {
        guard let current = order.indices.contains(position) ? order[position] : nil else { return }
        var rest = order.filter { $0 != current }
        rest.shuffle(using: &generator)
        order = [current] + rest
        position = 0
        isShuffled = true
    }

    /// Restores natural track order, keeping the current track current.
    mutating func unshuffle() {
        let current = order.indices.contains(position) ? order[position] : nil
        order = Array(tracks.indices)
        position = current.flatMap { order.firstIndex(of: $0) } ?? 0
        isShuffled = false
    }
}

/// Owns the `AVPlayer` for songs and audiobooks: queue transport, shuffle/repeat,
/// playback speed, Now Playing integration, and per-track progress reporting.
///
/// The video path stays in `PlaybackStore`; audio is its own store because queue
/// semantics, rate control, and lighter reporting don't fit the video lifecycle.
@MainActor
@Observable
final class AudioPlayerStore {
    private(set) var state: LoadState = .idle
    private(set) var queue: AudioQueue
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    /// Playback speed; surfaced for audiobooks.
    var playbackRate: Double = 1.0 {
        didSet {
            if isPlaying {
                player?.rate = Float(playbackRate)
            }
        }
    }

    private let session: SessionStore
    private let downloads: OfflineDownloadStore?
    private let localOnly: Bool
    private let localProgress: OfflinePlaybackProgressStore
    private let progressWriterToken: UUID
    private var isLocalPlayback = false
    private var playingDownload: OfflineDownloadRecord?
    private var completedRepeats: [String: OfflineDownloadRecord] = [:]
    private let nowPlaying = NowPlayingController()
    private let logger = Logger(category: .playback)
    private let playerFactory: @MainActor () -> AVPlayer
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var preparationGeneration = 0
    private var reportContext: PlaybackReportContext?
    private var lastProgressReportTime: Double = 0

    convenience init(session: SessionStore, tracks: [MediaItem], startIndex: Int = 0, downloads: OfflineDownloadStore? = nil, localOnly: Bool = false, localProgress: OfflinePlaybackProgressStore? = nil) {
        self.init(session: session, tracks: tracks, startIndex: startIndex, downloads: downloads, localOnly: localOnly, localProgress: localProgress, playerFactory: { AVPlayer() })
    }

    init(session: SessionStore, tracks: [MediaItem], startIndex: Int = 0, downloads: OfflineDownloadStore? = nil, localOnly: Bool = false, localProgress: OfflinePlaybackProgressStore? = nil, playerFactory: @escaping @MainActor () -> AVPlayer) {
        self.session = session
        self.downloads = downloads
        self.localOnly = localOnly
        self.playerFactory = playerFactory
        let progress = localProgress ?? .shared
        self.localProgress = progress
        progressWriterToken = progress.writerToken(for: AccountScope(serverID: session.server.id, userID: session.user.id))
        queue = AudioQueue(tracks: tracks, startIndex: startIndex)
    }

    private var accountScope: AccountScope {
        AccountScope(serverID: session.server.id, userID: session.user.id)
    }

    nonisolated static func initialReportSeconds(for item: MediaItem, resume: Bool) -> Double {
        guard resume, let resumeTicks = PlaybackActionPosition.ticks(for: item, localTicks: nil) else { return 0 }
        return PlaybackTime.seconds(fromTicks: resumeTicks)
    }

    var currentTrack: MediaItem? {
        queue.currentTrack
    }

    var repeatMode: AudioQueue.RepeatMode {
        queue.repeatMode
    }

    var isShuffled: Bool {
        queue.isShuffled
    }

    func start(resume: Bool = true) async {
        await playCurrentTrack(resume: resume)
    }

    func playPause() {
        if state == .loaded, player == nil {
            // Completion releases the player and reporting context. Prepare again
            // instead of trying to resume an ended item without its observers.
            let generation = preparationGeneration
            Task { [weak self] in
                guard let self, self.preparationGeneration == generation else { return }
                await self.playCurrentTrack(resume: false)
            }
            return
        }
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.rate = Float(playbackRate)
            isPlaying = true
        }
        reportProgress(force: true)
    }

    func next() async {
        reportStopped()
        guard queue.advance(automatic: false) != nil else {
            finishQueue()
            return
        }
        await playCurrentTrack(resume: false)
    }

    func previous() async {
        // Standard transport behavior: restart the track unless near its start.
        if currentTime > 3 {
            await seek(to: 0)
            return
        }
        reportStopped()
        _ = queue.goBack()
        await playCurrentTrack(resume: false)
    }

    func select(trackID: String) async {
        reportStopped()
        guard queue.jump(toTrackID: trackID) != nil else { return }
        await playCurrentTrack(resume: false)
    }

    func seek(to seconds: Double) async {
        guard let player else { return }
        await player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = seconds
        reportProgress(force: true)
    }

    func toggleShuffle() {
        if queue.isShuffled {
            queue.unshuffle()
        } else {
            var generator = SystemRandomNumberGenerator()
            queue.shuffle(using: &generator)
        }
    }

    func cycleRepeatMode() {
        switch queue.repeatMode {
        case .off: queue.repeatMode = .all
        case .all: queue.repeatMode = .one
        case .one: queue.repeatMode = .off
        }
    }

    func teardown() {
        preparationGeneration += 1
        reportStopped()
        removeObservers()
        player?.pause()
        nowPlaying.stop()
        player = nil
        cleanUpCompletedRepeats()
        isPlaying = false
        state = .idle
        deactivateAudioSession()
    }

    // MARK: - Track lifecycle

    private func playCurrentTrack(resume: Bool) async {
        guard var track = queue.currentTrack, var trackID = track.id else {
            state = .failed(String(localized: "This item can't be played.", comment: "Playback error: item has no playable identifier"))
            return
        }

        preparationGeneration += 1
        let generation = preparationGeneration
        player?.pause()
        isPlaying = false
        removeObservers()
        state = .loading
        let diagnostics = DiagnosticsHub.shared
        diagnostics.record(.playbackStartRequested)
        let startupInterval = diagnostics.beginInterval("PlaybackStartup")

        do {
            await PlaybackAudioSession.activate(video: false)
            try Task.checkCancellation()
            guard generation == preparationGeneration else { return }
            playingDownload = downloads?.record(for: track, serverID: session.server.id, userID: session.user.id)
            let localURL = downloads?.localFileURL(for: track, serverID: session.server.id, userID: session.user.id)
            guard ContentRatingGate.admitsStored(track) else {
                throw GusError.server(String(localized: "This item is restricted.", comment: "Restricted playback"))
            }
            if localURL == nil, localOnly || downloads?.record(for: track, serverID: session.server.id, userID: session.user.id)?.status.isComplete == true {
                throw GusError.server(String(localized: "The downloaded file is missing. Download it again to play it offline.", comment: "Missing offline file"))
            }
            isLocalPlayback = localURL != nil
            let playbackURL: URL
            if let localURL {
                if let downloaded = downloads?.record(for: track, serverID: session.server.id, userID: session.user.id) {
                    track = downloaded.item; trackID = downloaded.item.id ?? trackID
                }
                playbackURL = localURL
            } else {
                let current = try await session.references.currentItem(track)
                try Task.checkCancellation()
                guard generation == preparationGeneration, let currentID = current.id else { return }
                track = current
                trackID = currentID
                guard ContentRatingGate.admitsStored(track) else { throw GusError.notFound }
                let resolution = try await NetworkRetryPolicy.idempotent.run {
                    try await self.session.mediaProvider.resolveAudioPlayback(for: trackID)
                }
                playbackURL = resolution.url
            }

            try Task.checkCancellation()
            guard generation == preparationGeneration else { return }
            removeObservers()
            let playerItem = AVPlayerItem(url: playbackURL)
            let player = self.player ?? playerFactory()
            player.replaceCurrentItem(with: playerItem)
            #if os(iOS) || os(tvOS) || os(macOS)
                player.allowsExternalPlayback = true
            #endif
            self.player = player

            let context = PlaybackReportContext(
                itemID: trackID,
                mediaSourceID: nil,
                playSessionID: nil,
                playMethod: localURL != nil ? .directPlay : .directStream,
                streamSelection: .none
            )
            reportContext = context

            let localTicks = resume && isLocalPlayback ? localProgress.positionTicks(forItemID: trackID, scope: accountScope) : nil
            let initialSeconds = localTicks.map { ticks in
                PlaybackTime.seconds(fromTicks: track.runTimeTicks.map { $0 > 0 && ticks >= $0 ? 0 : ticks } ?? ticks)
            }
                ?? Self.initialReportSeconds(for: track, resume: resume)
            if initialSeconds > 0 {
                await player.seek(
                    to: CMTime(seconds: initialSeconds, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
            }
            try Task.checkCancellation()
            guard generation == preparationGeneration else { return }
            currentTime = initialSeconds
            lastProgressReportTime = initialSeconds

            duration = track.runTimeTicks.map(PlaybackTime.seconds(fromTicks:)) ?? 0
            nowPlaying.start(
                player: player,
                item: track,
                artworkURL: isLocalPlayback
                    ? downloads?.localArtworkURL(for: track, serverID: session.server.id, userID: session.user.id)
                    : session.mediaProvider.primaryImageURL(for: track, context: .nowPlayingArtwork),
                onNextTrack: { [weak self] in
                    Task { @MainActor in
                        await self?.next()
                    }
                },
                onPreviousTrack: { [weak self] in
                    Task { @MainActor in
                        await self?.previous()
                    }
                }
            )
            addObservers(player: player)
            state = .loaded
            diagnostics.endInterval("PlaybackStartup", startupInterval)
            diagnostics.record(.playbackStarted(usingTranscoding: false, usingLocalFile: localURL != nil))
            player.rate = Float(playbackRate)
            isPlaying = true
            reportStart()
        } catch {
            diagnostics.endInterval("PlaybackStartup", startupInterval)
            guard generation == preparationGeneration else { return }
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            diagnostics.record(.playbackFailed)
            logger.error("Audio playback prepare failed: \(gusError.localizedDescription, privacy: .private)")
            state = .failed(gusError.localizedDescription)
        }
    }

    private func trackDidFinish() async {
        reportStopped()
        if let playingDownload {
            if queue.repeatMode == .off {
                downloads?.deleteAfterCompletion(playingDownload)
            } else {
                // Keep local files available throughout Repeat One/All.
                completedRepeats[playingDownload.id] = playingDownload
            }
        }
        guard queue.advance(automatic: true) != nil else {
            finishQueue()
            return
        }
        await playCurrentTrack(resume: false)
    }

    private func cleanUpCompletedRepeats() {
        for record in completedRepeats.values {
            downloads?.deleteAfterCompletion(record)
        }
        completedRepeats.removeAll()
    }

    private func finishQueue() {
        preparationGeneration += 1
        removeObservers()
        player?.pause()
        nowPlaying.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        cleanUpCompletedRepeats()
    }

    // MARK: - Observers

    private func addObservers(player: AVPlayer) {
        let generation = preparationGeneration
        statusObserver = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? String(localized: "Can't Play This")
            let itemID = ObjectIdentifier(item)
            Task { @MainActor [weak self] in
                guard let self, self.preparationGeneration == generation,
                      self.player?.currentItem.map(ObjectIdentifier.init) == itemID else { return }
                self.player?.pause()
                self.isPlaying = false
                self.state = .failed(message)
            }
        }
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.preparationGeneration == generation else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                self.reportProgress(force: false)
            }
        }
        let observedItem = player.currentItem
        let observedItemID = observedItem.map(ObjectIdentifier.init)
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: observedItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let observedItemID, self.preparationGeneration == generation,
                      self.player?.currentItem.map(ObjectIdentifier.init) == observedItemID else { return }
                await self.trackDidFinish()
            }
        }
    }

    private func removeObservers() {
        statusObserver?.invalidate()
        statusObserver = nil
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    // MARK: - Progress reporting

    private func reportStart() {
        guard let context = reportContext else { return }
        let ticks = PlaybackTime.ticks(fromSeconds: currentTime)
        if isLocalPlayback {
            localProgress.checkpoint(itemID: context.itemID, positionTicks: ticks, scope: accountScope, writerToken: progressWriterToken, item: queue.currentTrack)
            return
        }
        Task {
            try? await session.mediaProvider.reportPlaybackStart(context: context, positionTicks: ticks, isPaused: false)
        }
    }

    private func reportProgress(force: Bool) {
        guard let context = reportContext else { return }
        guard force || currentTime - lastProgressReportTime >= 10 else { return }
        lastProgressReportTime = currentTime
        let ticks = PlaybackTime.ticks(fromSeconds: currentTime)
        let paused = !isPlaying
        if isLocalPlayback {
            localProgress.checkpoint(itemID: context.itemID, positionTicks: ticks, scope: accountScope, writerToken: progressWriterToken, item: queue.currentTrack)
            return
        }
        Task {
            try? await session.mediaProvider.reportPlaybackProgress(context: context, positionTicks: ticks, isPaused: paused)
        }
    }

    private func reportStopped() {
        guard let context = reportContext else { return }
        reportContext = nil
        lastProgressReportTime = 0
        let ticks = PlaybackTime.ticks(fromSeconds: currentTime)
        if isLocalPlayback {
            localProgress.checkpoint(itemID: context.itemID, positionTicks: ticks, scope: accountScope, writerToken: progressWriterToken, item: queue.currentTrack)
            return
        }
        Task {
            try? await session.mediaProvider.reportPlaybackStopped(context: context, positionTicks: ticks)
        }
    }

    // MARK: - Audio session

    private func deactivateAudioSession() {
        PlaybackAudioSession.deactivate()
    }
}
