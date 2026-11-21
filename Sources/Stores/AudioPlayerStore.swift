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

    /// Ordered library pages append without changing the current track. Playlist
    /// occurrence queues are materialized separately and never pass through this deduper.
    mutating func appendLibraryTracks(_ incoming: [MediaItem]) {
        guard !isShuffled else { return }
        var identities = Set(tracks.compactMap(\.id))
        let additions = incoming.filter { item in
            guard let id = item.id, item.isAudioPlayable else { return false }
            return identities.insert(id).inserted
        }
        let first = tracks.count
        tracks.append(contentsOf: additions)
        order.append(contentsOf: first ..< tracks.count)
    }

    /// Restores natural track order, keeping the current track current.
    mutating func unshuffle() {
        let current = order.indices.contains(position) ? order[position] : nil
        order = Array(tracks.indices)
        position = current.flatMap { order.firstIndex(of: $0) } ?? 0
        isShuffled = false
    }
}

/// Continuation uses raw server offsets, independently of local content filtering.
struct AudioQueueContinuation: Sendable {
    var query: MediaItemQuery
    var nextStartIndex: Int
    var totalRecordCount: Int?
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
    private(set) var hasPreparedContent = false
    private(set) var queue: AudioQueue
    private var playbackIntent: PlaybackRequest?
    private(set) var queueContinuation: AudioQueueContinuation?
    private(set) var isLoadingQueue = false
    private(set) var queueErrorMessage: String?
    var trackSelectionNotice: String?
    private var queueLoadTask: Task<Void, Never>?
    private var queueGeneration = UUID()
    private var shuffleTask: Task<Void, Never>?
    private var shuffleGeneration = UUID()
    private(set) var isCollectingShuffle = false
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    /// Playback speed; surfaced for audiobooks.
    var playbackRate: Double = 1.0 {
        didSet {
            if isPlaybackRequested {
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
    private let activateAudioSession: @MainActor (Bool) async throws -> Void
    private var player: AVPlayer?
    private var preparedTrack: MediaItem?
    private var audioSelection = PlaybackStreamSelection.none
    var nativePlayer: AVPlayer? {
        player
    }

    private var timeControlObserver: NSKeyValueObservation?
    private var hasReportedStart = false
    private var retryPositionTicks: Int?
    private var retryItemID: String?
    private(set) var isPlaybackRequested = false
    private var playbackResource: PlaybackResource?
    private var usingTranscoding = false
    private var startupRequestedAt = ContinuousClock.now
    private var didObservePlaying = false
    private var firstPlayingInterval: OSSignpostIntervalState?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failedEndObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var mediaSelectionObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var preparationGeneration = 0
    private var reportContext: PlaybackReportContext?
    private var lastProgressReportTime: Double = 0

    convenience init(session: SessionStore, tracks: [MediaItem], startIndex: Int = 0, request: PlaybackRequest? = nil, continuation: AudioQueueContinuation? = nil, downloads: OfflineDownloadStore? = nil, localOnly: Bool = false, localProgress: OfflinePlaybackProgressStore? = nil, activateAudioSession: @escaping @MainActor (Bool) async throws -> Void = { try await PlaybackAudioSession.activate(video: $0) }) {
        self.init(session: session, tracks: tracks, startIndex: startIndex, request: request, continuation: continuation, downloads: downloads, localOnly: localOnly, localProgress: localProgress, activateAudioSession: activateAudioSession, playerFactory: { AVPlayer() })
    }

    init(session: SessionStore, tracks: [MediaItem], startIndex: Int = 0, request: PlaybackRequest? = nil, continuation: AudioQueueContinuation? = nil, downloads: OfflineDownloadStore? = nil, localOnly: Bool = false, localProgress: OfflinePlaybackProgressStore? = nil, activateAudioSession: @escaping @MainActor (Bool) async throws -> Void = { try await PlaybackAudioSession.activate(video: $0) }, playerFactory: @escaping @MainActor () -> AVPlayer) {
        self.session = session
        queueContinuation = continuation
        playbackIntent = request ?? (tracks.indices.contains(startIndex) ? PlaybackRequest(item: tracks[startIndex]) : nil)
        self.downloads = downloads
        self.localOnly = localOnly
        self.playerFactory = playerFactory
        self.activateAudioSession = activateAudioSession
        let progress = localProgress ?? .shared
        self.localProgress = progress
        progressWriterToken = progress.writerToken(for: AccountScope(serverID: session.server.id, userID: session.user.id))
        queue = AudioQueue(tracks: tracks, startIndex: startIndex)
        session.onInvalidation(of: self) { owner in owner.teardown() }
    }

    var request: PlaybackRequest? {
        guard let currentTrack else { return nil }
        var snapshot = playbackIntent?.item.id == currentTrack.id ? playbackIntent ?? PlaybackRequest(item: currentTrack) : PlaybackRequest(item: currentTrack)
        snapshot.item = currentTrack
        snapshot.streamSelection.mediaSourceID = reportContext?.mediaSourceID ?? snapshot.streamSelection.mediaSourceID
        if hasReportedStart {
            snapshot.startPositionTicks = PlaybackTime.ticks(fromSeconds: currentTime)
        }
        return snapshot
    }

    private var accountScope: AccountScope {
        AccountScope(serverID: session.server.id, userID: session.user.id)
    }

    nonisolated static func initialReportSeconds(for item: MediaItem, resume: Bool) -> Double {
        guard resume, let resumeTicks = PlaybackActionPosition.ticks(for: item, localTicks: nil) else { return 0 }
        return PlaybackTime.seconds(fromTicks: resumeTicks)
    }

    var currentTrack: MediaItem? {
        if let preparedTrack, preparedTrack.id == queue.currentTrack?.id {
            return preparedTrack
        }
        return queue.currentTrack
    }

    var repeatMode: AudioQueue.RepeatMode {
        queue.repeatMode
    }

    var isShuffled: Bool {
        queue.isShuffled
    }

    func start() async {
        await playCurrentTrack(resume: playbackIntent?.start != .fromBeginning)
    }

    func playPause() {
        if state == .loaded, player == nil {
            // Completion releases the player and reporting context. Prepare again
            // instead of trying to resume an ended item without its observers.
            let generation = preparationGeneration
            Task { [weak self] in
                guard let self, self.session.isActive, self.preparationGeneration == generation else { return }
                await self.playCurrentTrack(resume: false)
            }
            return
        }
        guard let player, state == .loaded else { return }
        if isPlaybackRequested {
            isPlaybackRequested = false
            player.pause()
        } else {
            isPlaybackRequested = true
            player.rate = Float(playbackRate)
        }
        reportProgress(force: true)
    }

    func next() async {
        if queue.position + 1 >= queue.order.count, queueContinuation != nil {
            await loadMoreQueue()
            guard queue.position + 1 < queue.order.count || queueContinuation == nil else { return }
        }
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
        guard seconds.isFinite, session.isActive, let player, let item = player.currentItem else { return }
        let generation = preparationGeneration
        let finished = await player.seek(
            to: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        guard finished, !Task.isCancelled, session.isActive, generation == preparationGeneration, self.player === player, player.currentItem === item else { return }
        let actual = player.currentTime().seconds
        guard actual.isFinite else { return }
        currentTime = actual
        reportProgress(force: true)
    }

    var hasNext: Bool {
        queue.hasNext || queueContinuation != nil
    }

    func loadMoreQueue() async {
        if let queueLoadTask {
            await queueLoadTask.value; return
        }
        guard queueContinuation != nil, session.isActive else { return }
        let generation = queueGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performQueueLoad()
        }
        queueLoadTask = task
        await task.value
        if generation == queueGeneration {
            queueLoadTask = nil
        }
    }

    private func performQueueLoad() async {
        guard var continuation = queueContinuation, !queue.isShuffled else { return }
        isLoadingQueue = true
        queueErrorMessage = nil
        defer { isLoadingQueue = false }
        let generation = queueGeneration
        do {
            // Retain the shared three-page budget for restricted-only results.
            for _ in 0 ..< 3 {
                var query = continuation.query
                query.startIndex = continuation.nextStartIndex
                let provider = session.mediaProvider
                let requestQuery = query
                let page = try await PlaybackDeadline.run(for: .seconds(30)) { try await provider.items(query: requestQuery) }
                guard !Task.isCancelled, session.isActive, generation == queueGeneration else { return }
                let total = try MediaPageLoader.validatedTotal(for: page, startIndex: query.startIndex, previousTotal: continuation.totalRecordCount)
                let eligible = ContentRatingGate.filter(page.items).filter(\.isAudioPlayable)
                queue.appendLibraryTracks(eligible)
                continuation.nextStartIndex += page.items.count
                continuation.totalRecordCount = total
                let more = total.map { continuation.nextStartIndex < $0 } ?? (page.items.count >= query.limit)
                queueContinuation = more ? continuation : nil
                if !eligible.isEmpty || !more {
                    return
                }
            }
        } catch {
            guard session.isActive, generation == queueGeneration, !Task.isCancelled else { return }
            let failure = GusError(from: error)
            guard !failure.isCancellation else { return }
            failure.handleIfUnauthorized(session: session)
            queueErrorMessage = failure.localizedDescription
        }
    }

    var audioOptions: [PlaybackStreamOption] {
        currentTrack.map(PlaybackStreamCatalog.audioOptions(for:)) ?? []
    }

    var selectedAudioStreamIndex: Int? {
        audioSelection.audioStreamIndex
    }

    var audioMenuSelection: PlaybackTrackMenuSelection? {
        guard let request else { return nil }
        let source = request.item.mediaSources.first(where: { $0.id == selectedMediaSourceID }) ?? request.item.mediaSources.first
        return PlaybackTrackMenuSelection.audio(for: request, source: source)
    }

    func selectAudioStream(index: Int?) async {
        guard session.isActive, let track = currentTrack else { return }
        var intent = request ?? PlaybackRequest(item: track)
        let requestedMenuSelection = index.map(PlaybackTrackMenuSelection.stream) ?? .automatic
        let source = track.mediaSources.first(where: { $0.id == selectedMediaSourceID }) ?? track.mediaSources.first
        let effectiveChanged = audioSelection.audioStreamIndex != index
        guard PlaybackTrackMenuSelection.audio(for: intent, source: source) != requestedMenuSelection || effectiveChanged else { return }
        intent.streamSelection.audioStreamIndex = index
        intent.audioTrack = source?.mediaStreams.first { $0.type == .audio && $0.index == index }
        intent.startPositionTicks = PlaybackTime.ticks(fromSeconds: currentTime)
        playbackIntent = intent
        guard effectiveChanged else { return }
        guard player != nil else { audioSelection.audioStreamIndex = index; return }
        if !usingTranscoding, let nativeItem = player?.currentItem,
           let group = try? await nativeItem.asset.loadMediaSelectionGroup(for: .audible)
        {
            guard session.isActive, player?.currentItem === nativeItem, !Task.isCancelled else { return }
            if let index {
                let candidates = group.options.enumerated().map { MediaSelectionCandidate(position: $0.offset, languageTag: $0.element.extendedLanguageTag) }
                if let position = PlaybackMediaSelectionMatcher.candidatePosition(forStreamIndex: index, kind: .audio, streams: track.mediaSources.first?.mediaStreams ?? [], candidates: candidates), group.options.indices.contains(position) {
                    nativeItem.select(group.options[position], in: group)
                    audioSelection.audioStreamIndex = index
                    reportContext?.streamSelection = audioSelection
                    return
                }
            } else {
                nativeItem.selectMediaOptionAutomatically(in: group)
                audioSelection.audioStreamIndex = nil
                reportContext?.streamSelection = audioSelection
                return
            }
        }
        guard !isLocalPlayback else { return }
        let startsPlaying = isPlaybackRequested
        await playCurrentTrack(resume: false, startsPlaying: startsPlaying)
    }

    var mediaSourceOptions: [MediaSource] {
        guard !isLocalPlayback else { return [] }
        return (currentTrack?.mediaSources ?? []).filter { $0.id != nil }
    }

    var selectedMediaSourceID: String? {
        reportContext?.mediaSourceID ?? playbackIntent?.streamSelection.mediaSourceID
    }

    func selectMediaSource(id: String, fromBeginning: Bool) async {
        guard session.isActive, let track = currentTrack, mediaSourceOptions.contains(where: { $0.id == id }), selectedMediaSourceID != id else { return }
        let startsPlaying = isPlaybackRequested
        let ticks = fromBeginning ? 0 : PlaybackTime.ticks(fromSeconds: currentTime)
        if !PlaybackActionPosition.canResume(at: ticks, durationTicks: mediaSourceOptions.first(where: { $0.id == id })?.runTimeTicks) {
            trackSelectionNotice = String(localized: "This timestamp is beyond this version. Choose Start Over.")
            return
        }
        let intent = (request ?? PlaybackRequest(item: track)).selectingMediaSource(id, startPositionTicks: ticks)
        reportStopped()
        playbackIntent = intent
        await playCurrentTrack(resume: false, startsPlaying: startsPlaying)
    }

    func toggleShuffle() {
        if queue.isShuffled {
            queue.unshuffle(); return
        }
        guard !isCollectingShuffle else { return }
        if queueContinuation == nil {
            shuffleCompleteQueue(); return
        }
        isCollectingShuffle = true
        let generation = UUID()
        shuffleGeneration = generation
        shuffleTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if shuffleGeneration == generation {
                    isCollectingShuffle = false; shuffleTask = nil
                }
            }
            while let before = queueContinuation?.nextStartIndex {
                await loadMoreQueue()
                guard !Task.isCancelled, session.isActive, shuffleGeneration == generation, queueErrorMessage == nil else { return }
                if queueContinuation?.nextStartIndex == before {
                    return
                }
            }
            guard !Task.isCancelled, shuffleGeneration == generation else { return }
            shuffleCompleteQueue()
        }
    }

    func collectForShuffle() async -> Bool {
        if !queue.isShuffled {
            toggleShuffle()
        }
        await shuffleTask?.value
        return queue.isShuffled && queueContinuation == nil
    }

    func cancelShuffleCollection() {
        shuffleGeneration = UUID()
        shuffleTask?.cancel()
        shuffleTask = nil
        queueLoadTask?.cancel()
        isCollectingShuffle = false
    }

    private func shuffleCompleteQueue() {
        guard queueContinuation == nil else { return }
        var generator = SystemRandomNumberGenerator()
        queue.shuffle(using: &generator)
    }

    func cycleRepeatMode() {
        switch queue.repeatMode {
        case .off: queue.repeatMode = .all
        case .all: queue.repeatMode = .one
        case .one: queue.repeatMode = .off
        }
    }

    func teardown() {
        cancelShuffleCollection()
        queueGeneration = UUID()
        queueLoadTask?.cancel()
        queueLoadTask = nil
        isLoadingQueue = false
        preparationGeneration += 1
        reportStopped()
        releaseNativePlayer()
        cleanUpCompletedRepeats()
        isPlaying = false
        isPlaybackRequested = false
        state = .idle
        hasPreparedContent = false
        deactivateAudioSession()
    }

    // MARK: - Track lifecycle

    private func playCurrentTrack(resume: Bool, startsPlaying: Bool = true) async {
        guard var track = queue.currentTrack, var trackID = track.id else {
            state = .failed(String(localized: "This item can't be played.", comment: "Playback error: item has no playable identifier"))
            return
        }

        guard session.isActive else { return }
        preparedTrack = nil
        preparationGeneration += 1
        let generation = preparationGeneration
        reportStopped()
        startupRequestedAt = .now
        didObservePlaying = false
        finishFirstPlayingInterval()
        firstPlayingInterval = DiagnosticsHub.shared.beginInterval("PlaybackFirstPlaying")
        player?.pause()
        isPlaying = false
        removeObservers()
        state = .loading
        let diagnostics = DiagnosticsHub.shared
        diagnostics.record(.playbackStartRequested)
        let startupInterval = diagnostics.beginInterval("PlaybackPreparation")
        defer { diagnostics.endInterval("PlaybackPreparation", startupInterval) }

        do {
            try await activateAudioSession(false)
            try Task.checkCancellation()
            guard session.isActive, generation == preparationGeneration else { return }
            let requestedSourceID = playbackIntent?.item.id == track.id ? playbackIntent?.streamSelection.mediaSourceID : nil
            playingDownload = downloads?.record(for: track, serverID: session.server.id, userID: session.user.id, mediaSourceID: requestedSourceID)
            let localURL = downloads?.localFileURL(for: track, serverID: session.server.id, userID: session.user.id, mediaSourceID: requestedSourceID)
            guard ContentRatingGate.admitsStored(track) else {
                throw GusError.server(String(localized: "This item is restricted.", comment: "Restricted playback"))
            }
            if localURL == nil, localOnly || downloads?.record(for: track, serverID: session.server.id, userID: session.user.id, mediaSourceID: requestedSourceID)?.status.isComplete == true {
                throw GusError.server(String(localized: "The downloaded file is missing. Download it again to play it offline.", comment: "Missing offline file"))
            }
            isLocalPlayback = localURL != nil
            let playbackURL: URL
            var audioResolution: PlaybackSourceResolution?
            if let localURL {
                if let downloaded = downloads?.record(for: track, serverID: session.server.id, userID: session.user.id, mediaSourceID: requestedSourceID) {
                    track = downloaded.playbackItem; trackID = downloaded.item.id ?? trackID
                    var intent = playbackIntent?.item.id == track.id ? playbackIntent ?? downloaded.playbackRequest : downloaded.playbackRequest
                    intent.item = track
                    intent.streamSelection.mediaSourceID = downloaded.mediaSourceID
                    playbackIntent = intent
                    audioSelection = downloaded.playbackSelection(for: intent)
                }
                playbackURL = localURL
                usingTranscoding = false
            } else {
                let requestedTrack = track
                let requestedIntent = playbackIntent?.item.id == track.id ? playbackIntent : PlaybackRequest(item: track)
                let activeSession = session
                let provider = session.mediaProvider
                let ownerIsCurrent: @MainActor @Sendable () -> Bool = { [weak self] in self?.preparationGeneration == generation && activeSession.isActive }
                let resolutionDeadline = ContinuousClock.now + .seconds(30)
                let result = try await PlaybackDeadline.run(for: .seconds(30), cancelOperation: false, onDiscard: { (result: ResolvedAudio) in
                    if let resource = result.resolution.resource {
                        await AudioPlayerStore.release(resource, provider: provider)
                    }
                }) {
                    try await PlaybackResolutionBudget.withValue(deadline: resolutionDeadline, ownerIsCurrent: ownerIsCurrent) {
                        let current = try await activeSession.references.currentItem(requestedTrack)
                        try PlaybackResolutionBudget.check()
                        guard ContinuousClock.now < resolutionDeadline else { throw PlaybackDeadline.Timeout() }
                        guard activeSession.isActive else { throw CancellationError() }
                        guard let currentID = current.id, ContentRatingGate.admitsStored(current) else { throw GusError.notFound }
                        let selectedSource = current.mediaSources.first(where: { $0.id == requestedIntent?.streamSelection.mediaSourceID }) ?? current.mediaSources.first
                        let selection = selectedSource.flatMap { requestedIntent?.selection(in: $0) } ?? .none
                        let resolution = try await provider.resolveAudioPlayback(for: currentID, streamSelection: selection)
                        return ResolvedAudio(item: current, resolution: resolution, selection: selection, unavailableTrack: requestedIntent?.audioTrack != nil && selection.audioStreamIndex == nil)
                    }
                }
                guard session.isActive, !Task.isCancelled, generation == preparationGeneration else {
                    if let resource = result.resolution.resource {
                        await Self.release(resource, provider: provider)
                    }
                    return
                }
                track = result.item
                track.runTimeTicks = MediaPlaybackIdentity.runTimeTicks(for: result.item, mediaSourceID: result.resolution.mediaSourceID ?? result.selection.mediaSourceID, resolvedSource: result.resolution.mediaSource)
                if let source = result.resolution.mediaSource {
                    track.mediaSources = [source] + track.mediaSources.filter { $0.id != source.id }
                }
                audioSelection = result.selection
                trackSelectionNotice = result.unavailableTrack ? String(localized: "A selected track is unavailable in this version. Using the player defaults.") : nil
                trackID = result.item.id ?? trackID
                audioResolution = result.resolution
                playbackResource = result.resolution.resource
                usingTranscoding = result.resolution.isTranscoding
                playbackURL = result.resolution.url
            }

            try Task.checkCancellation()
            guard session.isActive, generation == preparationGeneration else { return }
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
                mediaSourceID: isLocalPlayback ? playingDownload?.mediaSourceID : audioResolution?.mediaSourceID,
                playSessionID: audioResolution?.playSessionID,
                playMethod: localURL != nil ? .directPlay : (usingTranscoding ? .transcode : .directStream),
                streamSelection: audioSelection
            )
            reportContext = context
            reportContext?.liveStreamID = audioResolution?.resource?.liveStreamID

            let checkpointSourceID = playingDownload?.mediaSourceID ?? audioResolution?.mediaSourceID ?? requestedSourceID
            let localTicks = resume && (isLocalPlayback || requestedSourceID != nil) ? localProgress.positionTicks(forItemID: trackID, scope: accountScope, mediaSourceID: checkpointSourceID) : nil
            let retryTicks = retryItemID == queue.currentTrack?.id ? retryPositionTicks : nil
            let requestedTicks = playbackIntent?.item.id == queue.currentTrack?.id ? playbackIntent?.requestedStartTicks : nil
            let initialSeconds = (retryTicks ?? requestedTicks).map(PlaybackTime.seconds(fromTicks:)) ?? localTicks.map { ticks in
                PlaybackTime.seconds(fromTicks: track.runTimeTicks.map { $0 > 0 && ticks >= $0 ? 0 : ticks } ?? ticks)
            }
                ?? (isLocalPlayback || requestedSourceID != nil ? 0 : Self.initialReportSeconds(for: track, resume: resume))
            let sourceStreams = track.mediaSources.first?.mediaStreams ?? []
            let selectedAudio = audioSelection.audioStreamIndex
            try await NativePlaybackPreparation.prepare(
                player,
                item: playerItem,
                startTicks: initialSeconds > 0 ? PlaybackTime.ticks(fromSeconds: initialSeconds) : nil,
                finishing: {
                    if let audio = selectedAudio, let group = try? await playerItem.asset.loadMediaSelectionGroup(for: .audible) {
                        guard !Task.isCancelled, self.session.isActive, self.preparationGeneration == generation, player.currentItem === playerItem else { throw CancellationError() }
                        let candidates = group.options.enumerated().map { MediaSelectionCandidate(position: $0.offset, languageTag: $0.element.extendedLanguageTag) }
                        if let position = PlaybackMediaSelectionMatcher.candidatePosition(forStreamIndex: audio, kind: .audio, streams: sourceStreams, candidates: candidates), group.options.indices.contains(position) {
                            playerItem.select(group.options[position], in: group)
                        }
                    }
                },
                seek: { player, ticks in
                    let finished = await player.seek(to: CMTime(seconds: PlaybackTime.seconds(fromTicks: ticks), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    guard finished else { throw URLError(.cannotDecodeContentData) }
                }
            )
            try Task.checkCancellation()
            guard session.isActive, generation == preparationGeneration else { return }
            if isLocalPlayback, track.runTimeTicks == nil, playerItem.duration.seconds.isFinite, playerItem.duration.seconds > 0 {
                track.runTimeTicks = PlaybackTime.ticks(fromSeconds: playerItem.duration.seconds)
            }
            preparedTrack = track
            currentTime = initialSeconds
            lastProgressReportTime = initialSeconds

            duration = track.runTimeTicks.map(PlaybackTime.seconds(fromTicks:)) ?? 0
            nowPlaying.start(
                player: player,
                item: track,
                artworkURL: isLocalPlayback
                    ? downloads?.localArtworkURL(for: track, serverID: session.server.id, userID: session.user.id)
                    : session.mediaProvider.artworkURLs(for: track, request: .init(role: .square, maxWidth: 600)).first,
                fallbackArtworkURLs: isLocalPlayback ? [] : Array(session.mediaProvider.artworkURLs(for: track, request: .init(role: .square, maxWidth: 600)).dropFirst()),
                artworkSession: session.artworkTransport.session,
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
            hasPreparedContent = true
            #if !os(watchOS)
                if let request = self.request {
                    SharePlayCoordinator.shared.attachPlayer(player, request: request, session: session)
                }
            #endif
            diagnostics.record(.playbackPrepared(usingTranscoding: usingTranscoding, usingLocalFile: localURL != nil))
            retryPositionTicks = nil
            retryItemID = nil
            isPlaybackRequested = startsPlaying
            player.rate = startsPlaying ? Float(playbackRate) : 0
            if queue.order.count - queue.position <= 3, queueContinuation != nil {
                Task { [weak self] in await self?.loadMoreQueue() }
            }
        } catch {
            guard generation == preparationGeneration else { return }
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { teardown(); return }
            handleFailure(error)
        }
    }

    private func trackDidFinish() async {
        if duration.isFinite, duration > 0 {
            currentTime = duration
        }
        preparationGeneration += 1
        let generation = preparationGeneration
        reportStopped()
        if let playingDownload {
            if queue.repeatMode == .off {
                downloads?.deleteAfterCompletion(playingDownload)
            } else {
                completedRepeats[playingDownload.id] = playingDownload
            }
        }
        playingDownload = nil
        releaseNativePlayer()
        if queue.position + 1 >= queue.order.count, queueContinuation != nil {
            await loadMoreQueue()
            guard session.isActive, generation == preparationGeneration else { return }
            // Completion has already been finalized; retry/Next may resume pagination.
            if queue.position + 1 >= queue.order.count, queueContinuation != nil {
                return
            }
        }
        guard queue.advance(automatic: true) != nil else { finishQueue(); return }
        await playCurrentTrack(resume: false)
    }

    private func cleanUpCompletedRepeats() {
        for record in completedRepeats.values {
            downloads?.deleteAfterCompletion(record)
        }
        completedRepeats.removeAll()
    }

    private func releaseNativePlayer() {
        removeObservers()
        finishFirstPlayingInterval()
        #if !os(watchOS)
            if let player {
                SharePlayCoordinator.shared.detachPlayer(player)
            }
        #endif
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        nowPlaying.stop()
        player = nil
        isPlaying = false
        isPlaybackRequested = false
    }

    private func finishQueue() {
        preparationGeneration += 1
        releaseNativePlayer()
        currentTime = 0
        cleanUpCompletedRepeats()
    }

    // MARK: - Observers

    private func addObservers(player: AVPlayer) {
        let observedGeneration = preparationGeneration
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self, session.isActive, preparationGeneration == observedGeneration, self.player === player, state == .loaded else { return }
                isPlaying = status == .playing
                if status == .playing {
                    isPlaybackRequested = true
                } else if status == .paused {
                    isPlaybackRequested = false
                }
                if status == .playing, !didObservePlaying {
                    didObservePlaying = true
                    playbackIntent?.start = .automatic
                    playbackIntent?.startPositionTicks = nil
                    reportStart()
                    finishFirstPlayingInterval()
                    let elapsed = startupRequestedAt.duration(to: .now)
                    DiagnosticsHub.shared.record(.playbackFirstPlaying(elapsedMilliseconds: Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)))
                    DiagnosticsHub.shared.record(.playbackStarted(usingTranscoding: usingTranscoding, usingLocalFile: isLocalPlayback))
                }
                if status != .waitingToPlayAtSpecifiedRate {
                    reportProgress(force: true)
                }
                let reason: Int
                switch player.reasonForWaitingToPlay {
                case .toMinimizeStalls: reason = 1
                case .evaluatingBufferingRate: reason = 2
                case .noItemToPlay: reason = 3
                default: reason = 0
                }
                DiagnosticsHub.shared.record(.playbackTimeControl(status: status.rawValue, reason: reason, positionMilliseconds: PlaybackTime.ticks(fromSeconds: currentTime) / 10000, bufferEmpty: player.currentItem?.isPlaybackBufferEmpty ?? false, likelyToKeepUp: player.currentItem?.isPlaybackLikelyToKeepUp ?? false))
            }
        }
        let generation = preparationGeneration
        statusObserver = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? String(localized: "Can't Play This")
            let itemID = ObjectIdentifier(item)
            Task { @MainActor [weak self] in
                guard let self, self.preparationGeneration == generation,
                      self.player?.currentItem.map(ObjectIdentifier.init) == itemID else { return }
                self.handleFailure(GusError.server(message))
            }
        }
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.session.isActive, self.preparationGeneration == generation else { return }
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
        failedEndObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: observedItem, queue: .main) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            MainActor.assumeIsolated {
                guard let self, self.session.isActive, self.preparationGeneration == generation,
                      self.player?.currentItem.map(ObjectIdentifier.init) == observedItemID else { return }
                self.handleFailure(error ?? URLError(.cannotDecodeContentData))
            }
        }
        stalledObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.playbackStalledNotification, object: observedItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.session.isActive, self.preparationGeneration == generation,
                      self.player?.currentItem.map(ObjectIdentifier.init) == observedItemID else { return }
                DiagnosticsHub.shared.record(.playbackStalled(positionMilliseconds: PlaybackTime.ticks(fromSeconds: self.currentTime) / 10000))
            }
        }
        mediaSelectionObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.mediaSelectionDidChangeNotification, object: observedItem, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.usingTranscoding, let item = self.player?.currentItem,
                      self.session.isActive, self.preparationGeneration == generation,
                      ObjectIdentifier(item) == observedItemID,
                      let group = try? await item.asset.loadMediaSelectionGroup(for: .audible),
                      self.session.isActive, self.preparationGeneration == generation, self.player?.currentItem === item,
                      let option = item.currentMediaSelection.selectedMediaOption(in: group), let position = group.options.firstIndex(of: option) else { return }
                let streams = self.currentTrack?.mediaSources.first?.mediaStreams ?? []
                let candidates = group.options.enumerated().map { MediaSelectionCandidate(position: $0.offset, languageTag: $0.element.extendedLanguageTag) }
                guard let index = streams.filter({ $0.type == .audio }).compactMap(\.index).first(where: {
                    PlaybackMediaSelectionMatcher.candidatePosition(forStreamIndex: $0, kind: .audio, streams: streams, candidates: candidates) == position
                }) else { return }
                self.audioSelection.audioStreamIndex = index
                self.reportContext?.streamSelection = self.audioSelection
            }
        }
    }

    private func removeObservers() {
        timeControlObserver?.invalidate()
        timeControlObserver = nil
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
        for observer in [failedEndObserver, stalledObserver, mediaSelectionObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        failedEndObserver = nil
        stalledObserver = nil
        mediaSelectionObserver = nil
    }

    // MARK: - Progress reporting

    private struct ResolvedAudio: Sendable {
        let item: MediaItem
        let resolution: PlaybackSourceResolution
        let selection: PlaybackStreamSelection
        let unavailableTrack: Bool
    }

    private func reportStart() {
        guard var context = reportContext, !hasReportedStart else { return }
        context.canSeek = !(player?.currentItem?.seekableTimeRanges.isEmpty ?? true)
        reportContext = context
        hasReportedStart = true
        let ticks = PlaybackTime.ticks(fromSeconds: currentTime)
        localProgress.checkpoint(itemID: context.itemID, positionTicks: ticks, scope: accountScope, writerToken: progressWriterToken, item: currentTrack, mediaSourceID: context.mediaSourceID)
        if isLocalPlayback {
            return
        }
        let snapshot = context
        let provider = session.mediaProvider
        session.playbackReports.enqueue(.start, sessionID: context.reportID, onFailure: handleReportFailure) {
            try await provider.reportPlaybackStart(context: snapshot, positionTicks: ticks, isPaused: false)
        }
    }

    private func reportProgress(force: Bool) {
        guard session.isActive, hasReportedStart, let context = reportContext, force || currentTime - lastProgressReportTime >= 10 else { return }
        lastProgressReportTime = currentTime
        let ticks = PlaybackTime.ticks(fromSeconds: currentTime)
        let paused = !isPlaybackRequested
        localProgress.checkpoint(itemID: context.itemID, positionTicks: ticks, scope: accountScope, writerToken: progressWriterToken, item: currentTrack, mediaSourceID: context.mediaSourceID)
        if isLocalPlayback {
            return
        }
        let provider = session.mediaProvider
        session.playbackReports.enqueue(.progress, sessionID: context.reportID, onFailure: handleReportFailure) {
            try await provider.reportPlaybackProgress(context: context, positionTicks: ticks, isPaused: paused)
        }
    }

    private func reportStopped(failed: Bool = false) {
        let resource = playbackResource
        playbackResource = nil
        guard var context = reportContext, hasReportedStart else {
            reportContext = nil
            if let resource {
                let provider = session.mediaProvider; Task { await Self.release(resource, provider: provider) }
            }
            return
        }
        reportContext = nil
        hasReportedStart = false
        lastProgressReportTime = 0
        context.isFailed = failed
        let ticks = PlaybackTime.ticks(fromSeconds: currentTime)
        localProgress.checkpoint(itemID: context.itemID, positionTicks: ticks, scope: accountScope, writerToken: progressWriterToken, item: currentTrack, mediaSourceID: context.mediaSourceID)
        if isLocalPlayback {
            return
        }
        let snapshot = context
        let session = self.session
        let provider = session.mediaProvider
        session.playbackReports.enqueue(.stop, sessionID: context.reportID, onFailure: handleReportFailure, completion: { reportSucceeded in
            // Successful Stop owns the live-stream consumer release. Raw Close
            // is reserved for unstarted resources. A lost Stop response may have
            // already released this consumer, so cannot safely trigger raw Close.
            if let resource, resource.liveStreamID == nil {
                await Self.release(resource, provider: provider)
            } else if resource != nil, !reportSucceeded {
                DiagnosticsHub.shared.record(.playbackResourceCleanupUnconfirmed)
            }
        }) {
            try await provider.reportPlaybackStopped(context: snapshot, positionTicks: ticks)
            session.libraryIntelligence.invalidateTasteSignals()
        }
    }

    private func handleFailure(_ error: Error) {
        guard case .failed = state else {
            retryPositionTicks = hasReportedStart ? PlaybackTime.ticks(fromSeconds: currentTime) : retryPositionTicks
            retryItemID = queue.currentTrack?.id
            preparationGeneration += 1
            reportStopped(failed: true)
            releaseNativePlayer()
            DiagnosticsHub.shared.record(.playbackFailed)
            if let activationError = error as? PlaybackAudioSessionActivationError {
                DiagnosticsHub.shared.record(.playbackItemFailed(errorCode: activationError.underlyingError?.code ?? 0, errorDomain: activationError.diagnosticDomain))
            }
            state = .failed(GusError(from: error).localizedDescription)
            return
        }
    }

    private func handleReportFailure(_ error: Error) {
        let failure = GusError(from: error)
        guard !failure.isCancellation else { return }
        failure.handleIfUnauthorized(session: session)
        logger.error("Audio playback report failed: \(failure.localizedDescription, privacy: .private)")
    }

    private static func release(_ resource: PlaybackResource, provider: any MediaProviderSession) async {
        do {
            try await PlaybackDeadline.run(for: .seconds(5)) { try await provider.releasePlaybackResource(resource) }
            DiagnosticsHub.shared.record(.playbackResourceCleanup(succeeded: true))
        } catch { DiagnosticsHub.shared.record(.playbackResourceCleanup(succeeded: false)) }
    }

    private func finishFirstPlayingInterval() {
        if let firstPlayingInterval {
            DiagnosticsHub.shared.endInterval("PlaybackFirstPlaying", firstPlayingInterval)
        }
        firstPlayingInterval = nil
    }

    // MARK: - Audio session

    private func deactivateAudioSession() {
        PlaybackAudioSession.deactivate()
    }
}
