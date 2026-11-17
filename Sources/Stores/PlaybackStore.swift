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
    /// Preparation alone must never replace saved progress.
    private(set) var hasStartedPlayback = false
    private(set) var player: AVPlayer?
    private(set) var nextUpItem: MediaItem?
    private(set) var isNextUpPromptVisible = false
    private(set) var stereoPresentation: Stereo3DPresentation = .native2D
    private(set) var stereoFallbackNotice: String?
    var trackSelectionNotice: String?
    private(set) var viewingMode: Stereo3DViewingMode = .automatic
    /// Set when playback reaches its natural end with nothing left to auto-play;
    /// the player view observes it to dismiss itself.
    private(set) var didFinishPlayback = false
    private(set) var naturalCompletionRevision = 0
    var usesPlaylistOrder = false
    var positionTicks: Int {
        currentPositionTicks()
    }

    private(set) var item: MediaItem
    private var playbackIntent: PlaybackRequest
    private let session: SessionStore
    private let playbackRefresh: PlaybackRefreshStore
    private let downloads: OfflineDownloadStore?
    private let localOnly: Bool
    private let localProgress: OfflinePlaybackProgressStore
    private let progressWriterToken: UUID
    private let initialSeek: @MainActor (AVPlayer, Int) async throws -> Void
    private let activateAudioSession: @MainActor (Bool) async throws -> Void
    private var isLocalPlayback = false
    private var playingDownload: OfflineDownloadRecord?
    private let nowPlaying = NowPlayingController()
    private let logger = Logger(category: .playback)
    private var reportContext: PlaybackReportContext?
    private var progressObserver: Any?
    private var endObserver: (any NSObjectProtocol)?
    private var stalledObserver: (any NSObjectProtocol)?
    private var failedEndObserver: (any NSObjectProtocol)?
    private var mediaSelectionObserver: (any NSObjectProtocol)?
    private var pauseStateObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var nativeNavigationTask: Task<Void, Never>?
    private var playbackResource: PlaybackResource?
    private var playbackIsLive = false
    private var retryPositionTicks: Int?
    private var startupRequestedAt = ContinuousClock.now
    private var didObservePlaying = false
    private var didObserveFirstRender = false
    private var firstPlayingInterval: OSSignpostIntervalState?
    private var didReportPause = false
    private var didReportStopped = false
    private var isTranscodedPlayback = false
    private var streamSelection = PlaybackStreamSelection.none
    private var preparationGeneration = 0
    private var presentationIsActive = true

    init(request: PlaybackRequest, session: SessionStore, playbackRefresh: PlaybackRefreshStore, downloads: OfflineDownloadStore? = nil, localOnly: Bool = false, localProgress: OfflinePlaybackProgressStore? = nil, activateAudioSession: @escaping @MainActor (Bool) async throws -> Void = { try await PlaybackAudioSession.activate(video: $0) }, initialSeek: @escaping @MainActor (AVPlayer, Int) async throws -> Void = { player, ticks in
        let finished = await player.seek(to: CMTime(seconds: PlaybackTime.seconds(fromTicks: ticks), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        guard finished else { throw URLError(.cannotDecodeContentData) }
    }) {
        self.item = request.item
        playbackIntent = request
        streamSelection = request.streamSelection
        viewingMode = request.presentation
        self.initialSeek = initialSeek
        self.activateAudioSession = activateAudioSession
        self.session = session
        self.playbackRefresh = playbackRefresh
        self.downloads = downloads
        self.localOnly = localOnly
        let progress = localProgress ?? .shared
        self.localProgress = progress
        progressWriterToken = progress.writerToken(for: AccountScope(serverID: session.server.id, userID: session.user.id))
        session.onInvalidation(of: self) { owner in owner.teardown() }
    }

    var request: PlaybackRequest {
        var snapshot = playbackIntent
        snapshot.item = item
        snapshot.streamSelection.mediaSourceID = reportContext?.mediaSourceID ?? streamSelection.mediaSourceID
        if hasStartedPlayback {
            snapshot.startPositionTicks = currentPositionTicks()
        }
        return snapshot
    }

    private var accountScope: AccountScope {
        AccountScope(serverID: session.server.id, userID: session.user.id)
    }

    var audioOptions: [PlaybackStreamOption] {
        PlaybackStreamCatalog.audioOptions(for: item)
    }

    var subtitleOptions: [PlaybackStreamOption] {
        PlaybackStreamCatalog.subtitleOptions(for: item)
    }

    /// Selected source metadata does not establish actual display/audio output.
    var sourceVideoStream: MediaStreamInfo? {
        let source = item.mediaSources.first(where: { $0.id == reportContext?.mediaSourceID }) ?? item.mediaSources.first
        return source?.mediaStreams.first(where: { $0.type == .video })
    }

    /// Delivery is negotiated separately from the original source format.
    var playbackDeliveryTitle: String {
        if isLocalPlayback {
            return String(localized: "Downloaded")
        }
        switch reportContext?.playMethod {
        case .directPlay: return String(localized: "Direct Play")
        case .directStream: return String(localized: "Original file")
        case .transcode: return String(localized: "Server stream")
        case nil: return String(localized: "Preparing")
        }
    }

    var chapterTargets: [PlaybackChapter] {
        PlaybackChapter.seekTargets(for: item)
    }

    var selectedAudioStreamIndex: Int? {
        streamSelection.audioStreamIndex
    }

    var selectedSubtitleStreamIndex: Int? {
        streamSelection.subtitleStreamIndex.flatMap { $0 >= 0 ? $0 : nil }
    }

    private var menuMediaSource: MediaSource? {
        item.mediaSources.first(where: { $0.id == selectedMediaSourceID }) ?? item.mediaSources.first
    }

    var audioMenuSelection: PlaybackTrackMenuSelection? {
        PlaybackTrackMenuSelection.audio(for: playbackIntent, source: menuMediaSource)
    }

    var subtitleMenuSelection: PlaybackTrackMenuSelection? {
        PlaybackTrackMenuSelection.subtitle(for: playbackIntent, source: menuMediaSource)
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

    /// TV presentation activity is separate from the user’s paused playback intent.
    func setPresentationActive(_ active: Bool) {
        presentationIsActive = active
        if !active {
            player?.pause()
        }
        // Returning to the foreground does not override a user’s paused state.
    }

    func prepare(startTimeTicks: Int? = nil) async {
        guard session.isActive, player == nil else { return }
        didReportStopped = false
        didFinishPlayback = false
        let sourceID = streamSelection.mediaSourceID
        let hasLocalFile = downloads?.localFileURL(for: item, serverID: session.server.id, userID: session.user.id, mediaSourceID: sourceID) != nil
        let localRecord = hasLocalFile ? downloads?.record(for: item, serverID: session.server.id, userID: session.user.id, mediaSourceID: sourceID) : nil
        let checkpointSource = sourceID ?? localRecord?.mediaSourceID
        let localTicks = hasLocalFile || sourceID != nil ? item.id.flatMap { localProgress.positionTicks(forItemID: $0, scope: accountScope, mediaSourceID: checkpointSource) } : nil
        var positionItem = localRecord?.playbackItem ?? item
        if !hasLocalFile, let sourceID {
            positionItem.runTimeTicks = MediaPlaybackIdentity.runTimeTicks(for: item, mediaSourceID: sourceID)
        }
        let explicitTicks = startTimeTicks ?? playbackIntent.requestedStartTicks
        let initialTicks = retryPositionTicks ?? explicitTicks.map { max(0, $0) }
            ?? PlaybackActionPosition.ticks(for: positionItem, localTicks: localTicks ?? (hasLocalFile || sourceID != nil ? 0 : nil))
        await loadPlayback(startTimeTicks: initialTicks, replacingCurrentItem: false)
    }

    func selectAudioStream(index: Int?) async {
        guard session.isActive else { return }
        let requestedMenuSelection = index.map(PlaybackTrackMenuSelection.stream) ?? .automatic
        let effectiveChanged = streamSelection.audioStreamIndex != index
        guard audioMenuSelection != requestedMenuSelection || effectiveChanged else { return }
        var requested = streamSelection
        requested.audioStreamIndex = index
        rememberExplicitTracks(kind: .audio, selection: requested)
        guard effectiveChanged else { return }
        guard player != nil else { streamSelection = requested; return }
        if index == nil, !isTranscodedPlayback, let nativeItem = player?.currentItem,
           let group = try? await nativeItem.asset.loadMediaSelectionGroup(for: .audible), session.isActive, player?.currentItem === nativeItem
        {
            nativeItem.selectMediaOptionAutomatically(in: group)
            streamSelection.audioStreamIndex = nil
            refreshReportedStreamSelection()
            return
        }
        if let index, await applyInPlaceMediaSelection(kind: .audio, streamIndex: index) {
            streamSelection.audioStreamIndex = index
            refreshReportedStreamSelection()
            return
        }
        guard !isLocalPlayback else { return }
        streamSelection.audioStreamIndex = index
        await rebuildCurrentItemPreservingPosition()
    }

    func selectSubtitleStream(index: Int?) async {
        guard session.isActive else { return }
        let requestedMenuSelection = index.map(PlaybackTrackMenuSelection.stream) ?? .off
        let effectiveChanged = streamSelection.subtitleStreamIndex != (index ?? -1)
        guard subtitleMenuSelection != requestedMenuSelection || effectiveChanged else { return }
        var requested = streamSelection
        requested.subtitleStreamIndex = index ?? -1
        rememberExplicitTracks(kind: .subtitle, selection: requested)
        guard effectiveChanged else { return }
        guard player != nil else { streamSelection = requested; return }
        if await applyInPlaceMediaSelection(kind: .subtitle, streamIndex: index) {
            streamSelection.subtitleStreamIndex = index ?? -1
            refreshReportedStreamSelection()
            return
        }
        guard !isLocalPlayback else { return }
        streamSelection.subtitleStreamIndex = index ?? -1
        await rebuildCurrentItemPreservingPosition()
    }

    /// AVKit owns native track selection; retain the matching server index for
    /// progress reporting and the playback-details panel without restarting playback.
    func recordNativeTrackSelection(option: AVMediaSelectionOption?, group: AVMediaSelectionGroup, remember: Bool = true) {
        let kind: MediaStreamKind = group.options.first?.hasMediaCharacteristic(.audible) == true ? .audio : .subtitle
        if option == nil, kind == .subtitle {
            let changed = streamSelection.subtitleStreamIndex != -1 || subtitleMenuSelection != .off
            streamSelection.subtitleStreamIndex = -1
            refreshReportedStreamSelection()
            if remember, changed {
                rememberExplicitTracks(kind: kind)
            }
            return
        }
        guard let option, let position = group.options.firstIndex(of: option) else { return }
        let streams = item.mediaSources.first?.mediaStreams ?? []
        let candidates = group.options.enumerated().map { offset, choice in
            MediaSelectionCandidate(position: offset, languageTag: choice.extendedLanguageTag)
        }
        guard let index = streams.filter({ $0.type == kind }).compactMap(\.index).first(where: {
            PlaybackMediaSelectionMatcher.candidatePosition(forStreamIndex: $0, kind: kind, streams: streams, candidates: candidates) == position
        }) else { return }
        let previous = streamSelection
        let previousMenuSelection = kind == .audio ? audioMenuSelection : subtitleMenuSelection
        if kind == .audio {
            streamSelection.audioStreamIndex = index
        } else {
            streamSelection.subtitleStreamIndex = index
        }
        refreshReportedStreamSelection()
        if remember, previous != streamSelection || previousMenuSelection != .stream(index) {
            rememberExplicitTracks(kind: kind)
        }
    }

    private func refreshNativeTrackSelection(for playerItem: AVPlayerItem, generation: Int) async {
        guard !isTranscodedPlayback else { return }
        for characteristic in [AVMediaCharacteristic.audible, .legible] {
            guard let group = try? await playerItem.asset.loadMediaSelectionGroup(for: characteristic),
                  !Task.isCancelled, session.isActive, generation == preparationGeneration, player?.currentItem === playerItem else { continue }
            recordNativeTrackSelection(option: playerItem.currentMediaSelection.selectedMediaOption(in: group), group: group, remember: false)
        }
    }

    /// Hide redundant server menus only when every server choice maps to an
    /// embedded native option. Transcoded and external tracks keep server controls.
    func hasNativeTrackSelection(kind: MediaStreamKind) async -> Bool {
        guard session.isActive, !isTranscodedPlayback, let playerItem = player?.currentItem else { return false }
        let characteristic: AVMediaCharacteristic = kind == .audio ? .audible : .legible
        guard let group = try? await playerItem.asset.loadMediaSelectionGroup(for: characteristic),
              !Task.isCancelled, session.isActive, player?.currentItem === playerItem else { return false }
        let streams = item.mediaSources.first?.mediaStreams ?? []
        let indexes = streams.filter { $0.type == kind }.compactMap(\.index)
        guard !indexes.isEmpty else { return false }
        let candidates = group.options.enumerated().map { offset, option in
            MediaSelectionCandidate(position: offset, languageTag: option.extendedLanguageTag)
        }
        let positions = indexes.compactMap {
            PlaybackMediaSelectionMatcher.candidatePosition(forStreamIndex: $0, kind: kind, streams: streams, candidates: candidates)
        }
        return Set(positions).count == indexes.count && (kind != .subtitle || group.allowsEmptySelection)
    }

    /// Direct-played files expose their embedded tracks to AVKit, so switching can use
    /// `AVMediaSelection` in place — no multi-second stream rebuild. Transcoded streams
    /// carry only the negotiated tracks and must re-resolve against the server.
    private func applyInPlaceMediaSelection(kind: MediaStreamKind, streamIndex: Int?) async -> Bool {
        guard session.isActive, !isTranscodedPlayback, let playerItem = player?.currentItem else { return false }
        let characteristic: AVMediaCharacteristic = kind == .audio ? .audible : .legible
        guard let group = try? await playerItem.asset.loadMediaSelectionGroup(for: characteristic),
              !Task.isCancelled, session.isActive, player?.currentItem === playerItem else { return false }

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
        var refreshed = PlaybackReportContext(
            itemID: context.itemID,
            mediaSourceID: context.mediaSourceID,
            playSessionID: context.playSessionID,
            playMethod: context.playMethod,
            streamSelection: streamSelection
        )
        refreshed.reportID = context.reportID
        refreshed.liveStreamID = context.liveStreamID
        refreshed.canSeek = context.canSeek
        reportContext = refreshed
    }

    struct SourceOption: Identifiable {
        let id: String
        let title: String
        let runTimeTicks: Int?
    }

    var mediaSourceOptions: [SourceOption] {
        guard !isLocalPlayback, !playbackIsLive else { return [] }
        return item.mediaSources.enumerated().compactMap { offset, source in
            guard let id = source.id else { return nil }
            return SourceOption(id: id, title: source.name ?? String(localized: "Version \(offset + 1)"), runTimeTicks: source.runTimeTicks)
        }
    }

    var selectedMediaSourceID: String? {
        streamSelection.mediaSourceID ?? reportContext?.mediaSourceID
    }

    func selectMediaSource(id: String, fromBeginning: Bool) async {
        guard session.isActive, mediaSourceOptions.contains(where: { $0.id == id }), id != selectedMediaSourceID else { return }
        let ticks = fromBeginning ? 0 : currentPositionTicks()
        if !PlaybackActionPosition.canResume(at: ticks, durationTicks: mediaSourceOptions.first(where: { $0.id == id })?.runTimeTicks) {
            trackSelectionNotice = String(localized: "This timestamp is beyond this version. Choose Start Over.")
            return
        }
        let rate = player?.rate ?? 0
        let intent = request.selectingMediaSource(id, startPositionTicks: ticks)
        teardown(reportStopped: true)
        playbackIntent = intent
        streamSelection = intent.streamSelection
        await loadPlayback(startTimeTicks: ticks, replacingCurrentItem: false, resumeRate: rate)
    }

    private func rememberExplicitTracks(kind: MediaStreamKind, selection: PlaybackStreamSelection? = nil) {
        let selection = selection ?? streamSelection
        let source = menuMediaSource
        playbackIntent.streamSelection.mediaSourceID = selection.mediaSourceID
        if kind == .audio {
            playbackIntent.streamSelection.audioStreamIndex = selection.audioStreamIndex
            playbackIntent.audioTrack = source?.mediaStreams.first { $0.type == .audio && $0.index == selection.audioStreamIndex }
        }
        if kind == .subtitle {
            playbackIntent.streamSelection.subtitleStreamIndex = selection.subtitleStreamIndex
            playbackIntent.subtitleTrack = source?.mediaStreams.first { $0.type == .subtitle && $0.index == selection.subtitleStreamIndex }
            playbackIntent.subtitleIntent = selection.subtitleStreamIndex == nil ? .automatic : selection.subtitleStreamIndex == -1 ? .off : .explicit
        }
        guard let source else { return }
        PlaybackTrackMemory.shared.remember(
            item: item,
            source: source,
            selection: selection,
            scope: accountScope,
            audioExplicit: kind == .audio,
            subtitleExplicit: kind == .subtitle
        )
    }

    func selectAutomaticSubtitles() async {
        guard session.isActive else { return }
        let intentChanged = subtitleMenuSelection != .automatic
        streamSelection.subtitleStreamIndex = nil
        rememberExplicitTracks(kind: .subtitle)
        guard player != nil else { return }
        if !isTranscodedPlayback, let nativeItem = player?.currentItem,
           let group = try? await nativeItem.asset.loadMediaSelectionGroup(for: .legible), player?.currentItem === nativeItem
        {
            nativeItem.selectMediaOptionAutomatically(in: group)
            refreshReportedStreamSelection()
        } else if !isLocalPlayback, intentChanged {
            await rebuildCurrentItemPreservingPosition()
        }
    }

    func seek(to chapter: PlaybackChapter) async {
        guard session.isActive, let player, let item = player.currentItem else { return }
        let generation = preparationGeneration
        let finished = await player.seek(
            to: CMTime(seconds: chapter.seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        guard finished, !Task.isCancelled, session.isActive, generation == preparationGeneration, self.player === player, player.currentItem === item else { return }
        reportPlaybackProgress(positionTicks: currentPositionTicks(), isPaused: player.timeControlStatus != .playing)
    }

    func selectViewingMode(_ mode: Stereo3DViewingMode) async {
        guard session.isActive, !isLocalPlayback, viewingMode != mode else { return }
        viewingMode = mode
        playbackIntent.presentation = mode
        await rebuildCurrentItemPreservingPosition()
    }

    func playNextUp() async {
        guard let nextUpItem else { return }
        teardown(reportStopped: true)
        item = nextUpItem
        playbackIntent = PlaybackRequest(item: nextUpItem)
        self.nextUpItem = nil
        isNextUpPromptVisible = false
        streamSelection = .none
        await prepare()
    }

    /// Explicit playlist order bypasses the server's normal next-episode choice.
    func playPlaylistItem(_ next: MediaItem, startTimeTicks: Int?) async {
        teardown(reportStopped: true)
        item = next
        playbackIntent = PlaybackRequest(item: next, startPositionTicks: startTimeTicks)
        streamSelection = .none
        usesPlaylistOrder = true
        await prepare(startTimeTicks: startTimeTicks)
    }

    private func rebuildCurrentItemPreservingPosition() async {
        let ticks = currentPositionTicks()
        let rate = player?.rate ?? 0
        // Close the server-side play session for the outgoing stream before the rebuild
        // reports a fresh start, so stream switches don't leak stale sessions.
        if hasStartedPlayback, let context = reportContext {
            reportPlaybackStopped(context: context, positionTicks: ticks, resource: playbackResource)
        } else if let resource = playbackResource {
            let provider = session.mediaProvider
            Task { await Self.release(resource, provider: provider) }
        }
        playbackResource = nil
        nativeNavigationTask?.cancel()
        nativeNavigationTask = nil
        reportContext = nil
        await loadPlayback(startTimeTicks: ticks, replacingCurrentItem: true, resumeRate: rate)
    }

    private func loadPlayback(startTimeTicks: Int?, replacingCurrentItem: Bool, resumeRate: Float = 1) async {
        preparationGeneration += 1
        let generation = preparationGeneration
        guard session.isActive else { return }
        player?.pause()
        state = .loading
        startupRequestedAt = .now
        didObservePlaying = false
        didObserveFirstRender = false
        finishFirstPlayingInterval()
        firstPlayingInterval = DiagnosticsHub.shared.beginInterval("PlaybackFirstPlaying")
        hasStartedPlayback = false
        stereoFallbackNotice = nil
        let diagnostics = DiagnosticsHub.shared
        diagnostics.record(.playbackStartRequested)
        let startupInterval = diagnostics.beginInterval("PlaybackPreparation")
        defer { diagnostics.endInterval("PlaybackPreparation", startupInterval) }

        guard var itemID = item.id else {
            diagnostics.record(.playbackFailed)
            state = .failed(String(localized: "This item can't be played.", comment: "Playback error: item has no playable identifier"))
            return
        }

        var effectiveStartTicks = startTimeTicks
        do {
            try await activateAudioSession(true)
            try Task.checkCancellation()
            guard session.isActive, generation == preparationGeneration else { return }
            playingDownload = downloads?.record(for: item, serverID: session.server.id, userID: session.user.id, mediaSourceID: streamSelection.mediaSourceID)
            let localURL = downloads?.localFileURL(for: item, serverID: session.server.id, userID: session.user.id, mediaSourceID: streamSelection.mediaSourceID)
            guard ContentRatingGate.admitsStored(item) else {
                throw GusError.server(String(localized: "This item is restricted.", comment: "Restricted playback"))
            }
            if localURL == nil, localOnly || downloads?.record(for: item, serverID: session.server.id, userID: session.user.id, mediaSourceID: streamSelection.mediaSourceID)?.status.isComplete == true {
                throw GusError.server(String(localized: "The downloaded file is missing. Download it again to play it offline.", comment: "Missing offline file"))
            }
            isLocalPlayback = localURL != nil
            let resolution: PlaybackSourceResolution?
            let playbackURL: URL
            if let localURL {
                if let downloaded = playingDownload {
                    item = downloaded.playbackItem; itemID = downloaded.item.id ?? itemID
                    playbackIntent.item = item
                    playbackIntent.streamSelection.mediaSourceID = downloaded.mediaSourceID
                    let tracks = PlaybackTrackMemory.shared.resolve(
                        request: playbackIntent,
                        item: item,
                        source: item.mediaSources.first,
                        baseSelection: downloaded.playbackSelection(for: playbackIntent),
                        scope: accountScope
                    )
                    streamSelection = tracks.selection
                    trackSelectionNotice = tracks.hasUnavailableSelection ? String(localized: "A selected track is unavailable in this version. Using the player defaults.") : nil
                }
                resolution = nil
                playbackIsLive = false
                playbackURL = localURL
                stereoPresentation = .native2D
            } else {
                let requestedItem = item
                let requestedSelection = streamSelection
                let requestedIntent = playbackIntent
                let requestedMode = viewingMode
                let originalID = itemID
                let provider = session.mediaProvider
                let activeSession = session
                let ownerIsCurrent: @MainActor @Sendable () -> Bool = { [weak self] in self?.preparationGeneration == generation && activeSession.isActive }
                let requestedScope = accountScope
                let resolutionDeadline = ContinuousClock.now + .seconds(30)
                let resolved = try await PlaybackDeadline.run(for: .seconds(30), cancelOperation: false, onDiscard: { (result: ResolvedPlayback) in
                    if let resource = result.resolution.resource {
                        await PlaybackStore.release(resource, provider: provider)
                    }
                }) {
                    try await PlaybackResolutionBudget.withValue(deadline: resolutionDeadline, ownerIsCurrent: ownerIsCurrent) {
                        let current = try await activeSession.references.currentItem(requestedItem)
                        try PlaybackResolutionBudget.check()
                        guard ContinuousClock.now < resolutionDeadline else { throw PlaybackDeadline.Timeout() }
                        try Task.checkCancellation()
                        guard activeSession.isActive else { throw CancellationError() }
                        guard let currentID = current.id, ContentRatingGate.admitsStored(current) else { throw GusError.notFound }
                        let source = current.mediaSources.first(where: { $0.id == requestedSelection.mediaSourceID }) ?? current.mediaSources.first
                        let tracks = PlaybackTrackMemory.shared.resolve(
                            request: requestedIntent,
                            item: current,
                            source: source,
                            baseSelection: source.map { requestedIntent.selection(in: $0) } ?? requestedSelection,
                            scope: requestedScope
                        )
                        let selection = tracks.selection
                        let ticks = MediaPlaybackIdentity.resumeTicks(requested: startTimeTicks, originalID: originalID, current: current)
                        let requestedPresentation = Media3DDetector.presentation(for: current, mediaSourceID: selection.mediaSourceID, viewingMode: requestedMode)
                        let remote = try await provider.resolvePlayback(
                            for: currentID,
                            maxStreamingBitrate: requestedIntent.maxStreamingBitrate ?? PlaybackQuality.stored.maxStreamingBitrate,
                            streamSelection: selection,
                            startTimeTicks: ticks,
                            stereoLayout: requestedPresentation.resolutionStereoLayout
                        )
                        return ResolvedPlayback(item: current, resolution: remote, selection: selection, startTicks: ticks, unavailableTrack: tracks.hasUnavailableSelection)
                    }
                }
                guard generation == preparationGeneration, session.isActive, !Task.isCancelled else {
                    if let resource = resolved.resolution.resource {
                        await Self.release(resource, provider: provider)
                    }
                    return
                }
                let remoteResolution = resolved.resolution
                effectiveStartTicks = resolved.startTicks
                item = resolved.item
                itemID = resolved.item.id ?? itemID
                streamSelection = resolved.selection
                trackSelectionNotice = resolved.unavailableTrack ? String(localized: "A selected track is unavailable in this version. Using the player defaults.") : nil
                item.runTimeTicks = MediaPlaybackIdentity.runTimeTicks(for: resolved.item, mediaSourceID: remoteResolution.mediaSourceID ?? resolved.selection.mediaSourceID, resolvedSource: remoteResolution.mediaSource)
                if let source = remoteResolution.mediaSource {
                    item.mediaSources = [source] + item.mediaSources.filter { $0.id != source.id }
                    streamSelection.audioStreamIndex = streamSelection.audioStreamIndex ?? source.defaultAudioStreamIndex
                    streamSelection.subtitleStreamIndex = streamSelection.subtitleStreamIndex ?? source.defaultSubtitleStreamIndex
                }
                playbackResource = remoteResolution.resource
                playbackIsLive = remoteResolution.isLive || item.type == .liveChannel
                // Keep the canonical primary source when interpreting item-level
                // metadata; the presentation item above puts the chosen source first.
                let requestedPresentation = Media3DDetector.presentation(for: resolved.item, mediaSourceID: resolved.selection.mediaSourceID, resolvedSource: remoteResolution.mediaSource, viewingMode: viewingMode)
                resolution = remoteResolution
                playbackURL = remoteResolution.url
                stereoPresentation = effectiveStereoPresentation(requested: requestedPresentation, resolution: remoteResolution)
                stereoFallbackNotice = fallbackNotice(
                    requested: requestedPresentation,
                    resolution: remoteResolution
                )
            }
            try Task.checkCancellation()
            guard session.isActive, generation == preparationGeneration else { return }
            logger.info("Playing \(self.item.name ?? "item", privacy: .private) (local: \(localURL != nil, privacy: .public), transcoding: \(resolution?.isTranscoding == true, privacy: .public))")

            let playerItem = AVPlayerItem(url: playbackURL)
            #if os(iOS) || os(tvOS) || os(visionOS)
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
            #if os(iOS) || os(tvOS) || os(macOS)
                player.allowsExternalPlayback = true // AirPlay; not available on visionOS
            #endif
            player.automaticallyWaitsToMinimizeStalling = true
            self.player = player
            isTranscodedPlayback = localURL == nil && resolution?.isTranscoding == true
            installEndObserver(for: playerItem)
            installPauseObservation(on: player)
            let context = PlaybackReportContext(
                itemID: itemID,
                mediaSourceID: localURL != nil ? playingDownload?.mediaSourceID : resolution?.mediaSourceID,
                playSessionID: resolution?.playSessionID,
                playMethod: localURL != nil ? .directPlay : resolution?.playMethod ?? .directStream,
                streamSelection: streamSelection
            )
            reportContext = context
            reportContext?.liveStreamID = playbackResource?.liveStreamID
            reportContext?.canSeek = !playbackIsLive && (playerItem.duration.isNumeric || !playerItem.seekableTimeRanges.isEmpty)

            let requestedTracks = streamSelection
            try await NativePlaybackPreparation.prepare(
                player,
                item: playerItem,
                startTicks: playbackIsLive ? nil : effectiveStartTicks,
                finishing: {
                    if !self.isTranscodedPlayback {
                        if let audio = requestedTracks.audioStreamIndex {
                            _ = await self.applyInPlaceMediaSelection(kind: .audio, streamIndex: audio)
                        }
                        if let subtitle = requestedTracks.subtitleStreamIndex {
                            _ = await self.applyInPlaceMediaSelection(kind: .subtitle, streamIndex: subtitle >= 0 ? subtitle : nil)
                        }
                    }
                    await self.refreshNativeTrackSelection(for: playerItem, generation: generation)
                },
                seek: initialSeek
            )

            try Task.checkCancellation()
            guard session.isActive, generation == preparationGeneration else { return }
            // AVPlayer can fail while the initial seek suspends this preparation.
            // Preserve an observer's error and check the item itself in case its
            // status callback has not reached the main actor yet.
            if case .failed = state {
                return
            }
            if playerItem.status == .failed {
                handlePlayerFailure(playerItem.error)
                return
            }
            if isLocalPlayback, item.runTimeTicks == nil, playerItem.duration.seconds.isFinite, playerItem.duration.seconds > 0 {
                item.runTimeTicks = PlaybackTime.ticks(fromSeconds: playerItem.duration.seconds)
            }
            #if os(watchOS)
                nowPlaying.start(
                    player: player,
                    item: item,
                    artworkURL: isLocalPlayback
                        ? downloads?.localArtworkURL(for: item, serverID: session.server.id, userID: session.user.id)
                        : session.mediaProvider.artworkURLs(for: item, request: .init(role: .poster, maxWidth: 600)).first,
                    fallbackArtworkURLs: isLocalPlayback ? [] : Array(session.mediaProvider.artworkURLs(for: item, request: .init(role: .poster, maxWidth: 600)).dropFirst()),
                    artworkSession: session.artworkTransport.session
                )
            #else
                nowPlaying.startVideo(
                    player: player,
                    item: item,
                    artworkURL: isLocalPlayback
                        ? downloads?.localArtworkURL(for: item, serverID: session.server.id, userID: session.user.id)
                        : session.mediaProvider.artworkURLs(for: item, request: .init(role: .poster, maxWidth: 600)).first,
                    fallbackArtworkURLs: isLocalPlayback ? [] : Array(session.mediaProvider.artworkURLs(for: item, request: .init(role: .poster, maxWidth: 600)).dropFirst()),
                    artworkSession: session.artworkTransport.session
                )
            #endif
            if progressObserver == nil {
                addProgressObserver(player: player)
            }
            state = .ready
            #if !os(watchOS)
                nativeNavigationTask?.cancel()
                let navigationItem = item
                let navigationSession = session
                nativeNavigationTask = Task { await NativePlayerNavigation.install(on: playerItem, item: navigationItem, session: navigationSession) }
            #endif
            diagnostics.record(.playbackPrepared(
                usingTranscoding: resolution?.isTranscoding == true,
                usingLocalFile: localURL != nil
            ))
            retryPositionTicks = nil
            player.rate = presentationIsActive ? resumeRate : 0
            if usesPlaylistOrder {
                nextUpItem = nil
            } else if isLocalPlayback {
                nextUpItem = DownloadedLibrary.nextEpisode(after: item, records: downloads?.completedRecords(
                    serverID: session.server.id, userID: session.user.id
                ) ?? [])
            } else {
                await loadNextUpIfNeeded()
            }
        } catch {
            guard generation == preparationGeneration else { return }
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { teardown(reportStopped: true); return }
            diagnostics.record(.playbackFailed)
            logger.error("Playback prepare failed: \(gusError.localizedDescription, privacy: .private)")
            handlePlayerFailure(error)
        }
    }

    private struct ResolvedPlayback: Sendable {
        let item: MediaItem
        let resolution: PlaybackSourceResolution
        let selection: PlaybackStreamSelection
        let startTicks: Int?
        let unavailableTrack: Bool
    }

    func teardown() {
        teardown(reportStopped: true)
    }

    private func teardown(reportStopped: Bool) {
        // Automatic next-episode preparation is independent of the view's task.
        // Invalidate its pending results even when its caller was not canceled.
        preparationGeneration += 1
        let finalTicks = currentPositionTicks()
        let context = hasStartedPlayback ? reportContext : nil
        let resource = playbackResource
        playbackResource = nil
        nativeNavigationTask?.cancel()
        nativeNavigationTask = nil
        finishFirstPlayingInterval()
        hasStartedPlayback = false
        removeProgressObserver()
        removeEndObserver()
        pauseStateObservation?.invalidate()
        pauseStateObservation = nil
        didReportPause = false
        isTranscodedPlayback = false
        #if !os(watchOS)
            if let player {
                SharePlayCoordinator.shared.detachPlayer(player)
            }
        #endif
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        nowPlaying.stop()
        player = nil
        playingDownload = nil
        nextUpItem = nil
        isNextUpPromptVisible = false
        reportContext = nil
        state = .idle
        stereoPresentation = .native2D
        stereoFallbackNotice = nil
        deactivateAudioSession()

        if reportStopped, let context, !didReportStopped {
            NextUpActivityStore.shared.recordPlayback(item: item, scope: accountScope)
            didReportStopped = true
            reportPlaybackStopped(context: context, positionTicks: finalTicks, resource: resource)
        } else if let resource {
            let provider = session.mediaProvider
            Task { await Self.release(resource, provider: provider) }
        }
    }

    // MARK: - Natural end (auto-play next / dismiss)

    private func installEndObserver(for playerItem: AVPlayerItem) {
        removeEndObserver()
        let generation = preparationGeneration
        let itemIdentity = ObjectIdentifier(playerItem)
        // Startup failures do not necessarily post failedToPlayToEndTime. Observe
        // item status too, or an unsupported source leaves the loading player blank.
        itemStatusObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, let currentItem = self.player?.currentItem,
                      self.preparationGeneration == generation,
                      ObjectIdentifier(currentItem) == itemIdentity,
                      currentItem.status == .failed else { return }
                self.handlePlayerFailure(currentItem.error)
            }
        }
        mediaSelectionObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.mediaSelectionDidChangeNotification, object: playerItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, state == .ready else { return }
                await refreshNativeTrackSelection(for: playerItem, generation: generation)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let currentItem = self.player?.currentItem,
                      self.preparationGeneration == generation,
                      ObjectIdentifier(currentItem) == itemIdentity else { return }
                self.handlePlaybackEnded()
            }
        }
        stalledObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification, object: playerItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let currentItem = self.player?.currentItem,
                      self.preparationGeneration == generation,
                      ObjectIdentifier(currentItem) == itemIdentity else { return }
                DiagnosticsHub.shared.record(.playbackStalled(positionMilliseconds: self.currentPositionTicks() / 10000))
            }
        }
        failedEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            MainActor.assumeIsolated {
                guard let self, let currentItem = self.player?.currentItem,
                      self.preparationGeneration == generation,
                      ObjectIdentifier(currentItem) == itemIdentity else { return }
                self.handlePlayerFailure(error)
            }
        }
    }

    private func handlePlayerFailure(_ error: Error?) {
        DiagnosticsHub.shared.record(.playbackFailed)
        let failure = (error as? PlaybackAudioSessionActivationError)?.underlyingError ?? (error as NSError?)
        let domain: Int
        switch failure?.domain {
        case NSURLErrorDomain: domain = 1
        case AVFoundationErrorDomain: domain = 2
        case NSOSStatusErrorDomain: domain = 3
        default: domain = 0
        }
        DiagnosticsHub.shared.record(.playbackItemFailed(errorCode: failure?.code ?? 0, errorDomain: domain))
        let message = error.map { GusError(from: $0).localizedDescription }
            ?? String(localized: "Playback stopped unexpectedly.", comment: "Generic playback failure message")
        retryPositionTicks = hasStartedPlayback ? currentPositionTicks() : retryPositionTicks
        if var context = reportContext, hasStartedPlayback {
            context.isFailed = true
            reportContext = context
        }
        teardown(reportStopped: true)
        state = .failed(message)
    }

    private func removeEndObserver() {
        if let mediaSelectionObserver {
            NotificationCenter.default.removeObserver(mediaSelectionObserver)
        }
        mediaSelectionObserver = nil
        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
        }
        stalledObserver = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
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
        guard hasStartedPlayback, !playbackIsLive else { return }
        let completed = item
        let next = nextUpItem
        let playlist = usesPlaylistOrder
        downloads?.deleteAfterCompletion(playingDownload)
        playingDownload = nil
        teardown(reportStopped: true)
        NextUpActivityStore.shared.recordCompletion(item: completed, scope: accountScope)
        if playlist {
            naturalCompletionRevision += 1
        } else if PlaybackPreferences.autoPlaysNextEpisode, let next {
            let generation = preparationGeneration
            Task { [weak self] in
                guard let self, session.isActive, preparationGeneration == generation else { return }
                item = next
                playbackIntent = PlaybackRequest(item: next)
                streamSelection = .none
                await prepare()
            }
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
                guard let self, self.session.isActive, self.player === player, self.state == .ready else { return }
                if status == .playing, !self.didObservePlaying {
                    self.didObservePlaying = true
                    self.hasStartedPlayback = true
                    self.playbackIntent.start = .automatic
                    self.playbackIntent.startPositionTicks = nil
                    if let context = self.reportContext {
                        self.reportPlaybackStart(context: context, player: player)
                    }
                    NextUpActivityStore.shared.recordPlayback(item: self.item, scope: self.accountScope)
                    self.finishFirstPlayingInterval()
                    let elapsed = self.startupRequestedAt.duration(to: .now)
                    let milliseconds = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
                    DiagnosticsHub.shared.record(.playbackFirstPlaying(elapsedMilliseconds: milliseconds))
                    DiagnosticsHub.shared.record(.playbackStarted(usingTranscoding: self.isTranscodedPlayback, usingLocalFile: self.isLocalPlayback))
                }
                let reason: Int
                switch player.reasonForWaitingToPlay {
                case .toMinimizeStalls: reason = 1
                case .evaluatingBufferingRate: reason = 2
                case .noItemToPlay: reason = 3
                default: reason = 0
                }
                DiagnosticsHub.shared.record(.playbackTimeControl(
                    status: status.rawValue, reason: reason,
                    positionMilliseconds: self.currentPositionTicks() / 10000,
                    bufferEmpty: player.currentItem?.isPlaybackBufferEmpty ?? false,
                    likelyToKeepUp: player.currentItem?.isPlaybackLikelyToKeepUp ?? false
                ))
                switch status {
                case .paused where !self.didReportPause:
                    self.didReportPause = true
                    self.reportPlaybackProgress(positionTicks: self.currentPositionTicks(), isPaused: true)
                case .playing where self.didReportPause:
                    NextUpActivityStore.shared.recordPlayback(item: self.item, scope: self.accountScope)
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
                guard let self, let player, self.session.isActive, self.player === player, self.state == .ready else { return }
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
        let ticks = currentPositionTicks()
        localProgress.checkpoint(itemID: context.itemID, positionTicks: ticks, scope: accountScope, writerToken: progressWriterToken, item: item, mediaSourceID: context.mediaSourceID)
        if isLocalPlayback {
            return
        }
        let provider = session.mediaProvider
        let paused = player.rate == 0
        session.playbackReports.enqueue(.start, sessionID: context.reportID, onFailure: handleReportFailure) {
            try await provider.reportPlaybackStart(context: context, positionTicks: ticks, isPaused: paused)
        }
    }

    private func reportPlaybackProgress(positionTicks: Int, isPaused: Bool) {
        guard session.isActive, hasStartedPlayback, var context = reportContext else { return }
        context.canSeek = !playbackIsLive && !(player?.currentItem?.seekableTimeRanges.isEmpty ?? true)
        localProgress.checkpoint(itemID: context.itemID, positionTicks: positionTicks, scope: accountScope, writerToken: progressWriterToken, item: item, mediaSourceID: context.mediaSourceID)
        if isLocalPlayback {
            return
        }
        let snapshot = context
        let provider = session.mediaProvider
        session.playbackReports.enqueue(.progress, sessionID: context.reportID, onFailure: handleReportFailure) {
            try await provider.reportPlaybackProgress(context: snapshot, positionTicks: positionTicks, isPaused: isPaused)
        }
    }

    private func reportPlaybackStopped(context: PlaybackReportContext, positionTicks: Int, resource: PlaybackResource? = nil) {
        localProgress.checkpoint(itemID: context.itemID, positionTicks: positionTicks, scope: accountScope, writerToken: progressWriterToken, item: item, mediaSourceID: context.mediaSourceID)
        if isLocalPlayback {
            playbackRefresh.markPlaybackProgressChanged()
            return
        }
        let provider = session.mediaProvider
        let refresh = playbackRefresh
        session.playbackReports.enqueue(.stop, sessionID: context.reportID, onFailure: handleReportFailure, completion: { reportSucceeded in
            // Jellyfin Stop already releases the live-stream consumer belonging to
            // this session. A second raw Close can decrement another consumer.
            // A lost Stop response is ambiguous: it may have released the
            // consumer already. Do not repeat that non-idempotent write.
            if let resource, resource.liveStreamID == nil {
                await Self.release(resource, provider: provider)
            } else if resource != nil, !reportSucceeded {
                DiagnosticsHub.shared.record(.playbackResourceCleanupUnconfirmed)
            }
        }) {
            try await provider.reportPlaybackStopped(context: context, positionTicks: positionTicks)
            refresh.markPlaybackProgressChanged()
        }
    }

    private func handleReportFailure(_ error: Error) {
        let failure = GusError(from: error)
        guard !failure.isCancellation else { return }
        failure.handleIfUnauthorized(session: session)
        logger.error("Playback report failed: \(failure.localizedDescription, privacy: .private)")
    }

    private static func release(_ resource: PlaybackResource, provider: any MediaProviderSession) async {
        do {
            try await PlaybackDeadline.run(for: .seconds(5)) { try await provider.releasePlaybackResource(resource) }
            DiagnosticsHub.shared.record(.playbackResourceCleanup(succeeded: true))
        } catch { DiagnosticsHub.shared.record(.playbackResourceCleanup(succeeded: false)) }
    }

    func recordFirstRenderReadiness(for nativeItem: AVPlayerItem) {
        guard session.isActive, player?.currentItem === nativeItem, !didObserveFirstRender else { return }
        didObserveFirstRender = true
        let elapsed = startupRequestedAt.duration(to: .now)
        DiagnosticsHub.shared.record(.playbackFirstRender(elapsedMilliseconds: Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)))
    }

    private func finishFirstPlayingInterval() {
        if let firstPlayingInterval {
            DiagnosticsHub.shared.endInterval("PlaybackFirstPlaying", firstPlayingInterval)
        }
        firstPlayingInterval = nil
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
        let generation = preparationGeneration
        let itemID = item.id
        do {
            let items = try await session.mediaProvider.nextUpItems(seriesID: seriesID, limit: 1)
            guard !Task.isCancelled, generation == preparationGeneration,
                  item.id == itemID, player != nil else { return }
            nextUpItem = ContentRatingGate.filter(items).first { $0.id != item.id }
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            logger.error("Next-up load failed: \(gusError.localizedDescription, privacy: .private)")
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

    private func deactivateAudioSession() {
        PlaybackAudioSession.deactivate()
    }
}
