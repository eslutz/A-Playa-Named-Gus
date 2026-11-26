import AVKit
import SwiftUI

/// Pure-AVKit player surface.
///
/// Native AVKit surfaces on every video platform. The `PlaybackStore` owns the `AVPlayer` and
/// tears it down on dismiss.
struct VideoPlayerView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PlaybackRefreshStore.self) private var playbackRefresh
    @Environment(OfflineDownloadStore.self) private var downloads
    @Environment(SavedMediaStore.self) private var playlists
    @Environment(ServerMediaListsStore.self) private var serverLists
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    #if os(visionOS)
        @Environment(CinemaModel.self) private var cinema
        @Environment(\.openImmersiveSpace) private var openImmersiveSpace
        @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    #endif
    let item: MediaItem
    var localOnly = false
    var playlistID: UUID? = nil
    var playlistEntryID: UUID? = nil
    var playlistFromBeginning = false
    var playlistShuffled = false
    var playbackRequest: PlaybackRequest? = nil

    @State private var store: PlaybackStore?
    @State private var playlist: VideoPlaylistPlaybackCoordinator?
    @State private var preparation: Task<Void, Never>?
    @State private var retryGeneration = 0
    @State private var didEndPlayback = false
    #if !os(iOS)
        @State private var pendingSource: PlaybackStore.SourceOption?
    #endif
    @State private var sharePlay = SharePlayCoordinator.shared
    #if os(visionOS)
        @State private var openedFramePackedCinema = false
        @State private var stereoRenderer: StereoFrameRenderer?
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Keep the native renderer attached through preparation → ready.
            // Readiness changes chrome/overlays, never the surface's identity.
            #if !os(iOS)
                if let store, let player = store.player {
                    #if os(visionOS)
                        if store.isFramePackedImmersivePlaybackActive {
                            Color.black
                                .ignoresSafeArea(edges: [.horizontal, .bottom])
                        } else {
                            PlayerSurface(player: player, store: store, onSelectSource: { pendingSource = $0 })
                                .ignoresSafeArea(edges: [.horizontal, .bottom])
                        }
                    #else
                        PlayerSurface(player: player, store: store, onSelectSource: { pendingSource = $0 })
                        #if os(tvOS)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityIdentifier("VideoPlayer.surface")
                        #endif
                            .ignoresSafeArea(edges: [.horizontal, .bottom])
                    #endif
                }

            #endif
            if let message = playlist?.errorMessage {
                ContentUnavailableView {
                    Label("Playlist Paused", systemImage: "exclamationmark.triangle")
                } description: { Text(message) } actions: {
                    playlistRecoveryActions
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            } else if case let .failed(message)? = store?.state {
                ContentUnavailableView {
                    Label("Can't Play This", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    if playlist != nil {
                        playlistRecoveryActions
                    } else {
                        Button("Try Again") {
                            preparation?.cancel()
                            if let store {
                                Task { await store.prepare() }
                            }
                        }
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            } else if store?.state != .ready {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
            }
        }
        #if os(tvOS)
        // Let the presentation set AVKit's viewport during both preparation
        // and playback.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        #endif
        #if os(iOS)
        .background {
            IOSFullscreenPlayer(
                store: store, player: store?.player, isReady: store?.state == .ready,
                needsRecovery: needsIOSRecovery, didFinish: store?.didFinishPlayback == true || playlist?.finished == true,
                notice: iosPlaybackNotice, dismissNotice: dismissIOSPlaybackNotice,
                close: closePlayback, teardown: endPlayback
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        #endif
        #if os(iOS) || os(tvOS) || os(visionOS)
        .overlay(alignment: .topLeading) {
            if store?.state != .ready || playlist?.errorMessage != nil {
                GusCloseButton { closePlayback() }
                    .padding()
                    .accessibilityIdentifier("VideoPlayer.close")
            }
        }
        #endif
        #if os(macOS) || os(visionOS)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let store, store.state == .ready, hasPlaybackOptions(store) {
                playbackOptions(store)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding()
                    .background(.bar)
            }
        }
        #endif
        #if !os(iOS)
        .confirmationDialog("Switch Version", isPresented: Binding(get: { pendingSource != nil }, set: {
            if !$0 {
                pendingSource = nil
            }
        }), titleVisibility: .visible) {
            if let source = pendingSource, let store {
                Button("Start Over") { pendingSource = nil; Task { await store.selectMediaSource(id: source.id, fromBeginning: true) } }
                Button("Resume at \(PlaybackTime.accessibilityDuration(seconds: PlaybackTime.seconds(fromTicks: store.positionTicks)))") { pendingSource = nil; Task { await store.selectMediaSource(id: source.id, fromBeginning: false) } }
                    .disabled(!PlaybackActionPosition.canResume(at: store.positionTicks, durationTicks: source.runTimeTicks))
                Button("Cancel", role: .cancel) { pendingSource = nil }
            }
        } message: {
            Text("Choose where playback should begin in this version. Versions may have different timelines.")
        }
        .safeAreaInset(edge: .top) {
            if let store, let notice = store.trackSelectionNotice {
                HStack {
                    Text(notice)
                    Button("OK") { store.trackSelectionNotice = nil }
                }.padding().background(.regularMaterial)
            }
            if playlistID != nil {
                SavedPlaylistErrorBanner()
            }
        }
        #endif
        .gusTVVideoLifecycle(store: store)
        .accessibilityAction(.escape) {
            closePlayback()
        }
        #if os(visionOS)
        .overlay(alignment: .topTrailing) {
            if let store, store.isSpatialPlaybackActive || store.stereoFallbackNotice != nil {
                VStack(alignment: .trailing, spacing: 8) {
                    if store.isSpatialPlaybackActive {
                        SpatialPlaybackBadge()
                    }

                    if let notice = store.stereoFallbackNotice {
                        StereoFallbackNotice(text: notice)
                    }
                }
                .padding()
            }
        }
        #endif
        .task(id: retryGeneration) {
            if store == nil {
                let store = PlaybackStore(request: playbackRequest ?? PlaybackRequest(item: item), session: session, playbackRefresh: playbackRefresh, downloads: downloads, localOnly: localOnly)
                store.gusSetTVPresentationActive(scenePhase == .active)
                self.store = store
                if let playlistID {
                    playlist = VideoPlaylistPlaybackCoordinator(playlistID: playlistID, entryID: playlistEntryID, fromBeginning: playlistFromBeginning, shuffled: playlistShuffled, playlists: playlists, session: session, downloads: downloads, serverLists: serverLists)
                }
                let task = Task {
                    if let playlist {
                        await playlist.start(store)
                    } else {
                        await store.prepare()
                    }
                }
                preparation = task
                await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
            }
        }
        .onChange(of: store?.hasStartedPlayback ?? false) { _, started in
            if started, let store {
                playlist?.checkpoint(store, activity: true)
            }
        }
        .task(id: store?.naturalCompletionRevision) {
            guard let store, store.naturalCompletionRevision > 0, let playlist else { return }
            await playlist.completed(store)
            #if !os(iOS)
                if playlist.finished {
                    dismiss()
                }
            #endif
        }
        .task(id: playlistID) {
            guard playlistID != nil else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                if let store, store.state == .ready {
                    playlist?.checkpoint(store)
                }
            }
        }
        .task(id: store?.player.map(ObjectIdentifier.init)) {
            attachSharePlayPlayer()
        }
        .task(id: store?.item.id) {
            attachSharePlayPlayer()
        }
        #if os(visionOS)
        .task(id: store?.stereoPresentation) {
            guard let store else { return }
            await syncFramePackedCinemaIfNeeded(store)
        }
        #endif
        #if !os(iOS)
        .onChange(of: store?.didFinishPlayback ?? false) { _, finished in
            if finished {
                dismiss()
            }
        }
        #endif
        .onChange(of: playlists.identityRevision) { _, _ in
            if playlistID != nil {
                preparation?.cancel()
                if let store {
                    playlist?.stop(store)
                }
                dismiss()
            }
        }
        #if !os(iOS)
        .onDisappear { endPlayback() }
        #endif
        .alert(
            "SharePlay Unavailable",
            isPresented: Binding(
                get: { sharePlay.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        sharePlay.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                sharePlay.errorMessage = nil
            }
        } message: {
            Text(sharePlay.errorMessage ?? "")
        }
        // Handoff: continue playback on another device. The continuing device resumes
        // from the server-side position kept fresh by progress reporting.
        .userActivity(GusUserActivity.playback, isActive: item.id != nil) { activity in
            GusUserActivity.configure(
                activity,
                item: store?.item ?? item,
                serverID: session.server.id,
                userID: session.user.id,
                includeOnscreenContext: session.systemSurfacePreferences.personalHistoryEnabled,
                playbackRequest: store?.request
            )
        }
    }

    private func endPlayback() {
        guard !didEndPlayback else { return }
        didEndPlayback = true
        preparation?.cancel()
        if let store {
            if let playlist {
                playlist.stop(store)
            } else {
                store.teardown()
            }
        }
        #if os(visionOS)
            closeFramePackedCinemaIfNeeded()
        #endif
    }

    private func closePlayback() {
        endPlayback()
        dismiss()
    }

    #if os(iOS)
        private var needsIOSRecovery: Bool {
            if case .failed = store?.state {
                return true
            }
            return playlist?.errorMessage != nil
        }

        private var iosPlaybackNotice: String? {
            store?.trackSelectionNotice ?? (playlistID == nil ? nil : playlists.errorMessage)
        }

        private func dismissIOSPlaybackNotice() {
            if store?.trackSelectionNotice != nil {
                store?.trackSelectionNotice = nil
            } else {
                playlists.clearError()
            }
        }
    #endif

    #if os(macOS) || os(visionOS)
        private func hasPlaybackOptions(_ store: PlaybackStore) -> Bool {
            store.mediaSourceOptions.count > 1 || store.audioOptions.count > 1 || !store.subtitleOptions.isEmpty
        }

        private func playbackOptions(_ store: PlaybackStore) -> some View {
            Menu("Playback Options", systemImage: "slider.horizontal.3") {
                if store.mediaSourceOptions.count > 1 {
                    Menu("Version") {
                        ForEach(store.mediaSourceOptions) { source in
                            Button(source.title) { pendingSource = source }
                                .disabled(source.id == store.selectedMediaSourceID)
                        }
                    }
                }
                if store.audioOptions.count > 1 {
                    Picker("Audio", selection: Binding(get: { store.audioMenuSelection }, set: { selection in
                        guard let selection else { return }
                        switch selection {
                        case .automatic: Task { await store.selectAudioStream(index: nil) }
                        case let .stream(index): Task { await store.selectAudioStream(index: index) }
                        case .off: break
                        }
                    })) {
                        if store.audioMenuSelection == nil {
                            Text("Unavailable").tag(nil as PlaybackTrackMenuSelection?).disabled(true)
                        }
                        Text("Automatic").tag(PlaybackTrackMenuSelection.automatic as PlaybackTrackMenuSelection?)
                        ForEach(store.audioOptions) { option in
                            Text(option.title).tag(PlaybackTrackMenuSelection.stream(option.id) as PlaybackTrackMenuSelection?)
                        }
                    }.pickerStyle(.menu)
                }
                if !store.subtitleOptions.isEmpty {
                    Picker("Subtitles", selection: Binding(get: { store.subtitleMenuSelection }, set: { selection in
                        guard let selection else { return }
                        switch selection {
                        case .automatic: Task { await store.selectAutomaticSubtitles() }
                        case .off: Task { await store.selectSubtitleStream(index: nil) }
                        case let .stream(index): Task { await store.selectSubtitleStream(index: index) }
                        }
                    })) {
                        if store.subtitleMenuSelection == nil {
                            Text("Unavailable").tag(nil as PlaybackTrackMenuSelection?).disabled(true)
                        }
                        Text("Automatic").tag(PlaybackTrackMenuSelection.automatic as PlaybackTrackMenuSelection?)
                        Text("Off").tag(PlaybackTrackMenuSelection.off as PlaybackTrackMenuSelection?)
                        ForEach(store.subtitleOptions) { option in
                            Text(option.title).tag(PlaybackTrackMenuSelection.stream(option.id) as PlaybackTrackMenuSelection?)
                        }
                    }.pickerStyle(.menu)
                }
            }.buttonStyle(.bordered)
                .accessibilityIdentifier("VideoPlayer.options")
        }

    #endif

    private func attachSharePlayPlayer() {
        guard let store else { return }
        sharePlay.attachPlayer(store.player, request: store.request, session: session)
    }

    @ViewBuilder private var playlistRecoveryActions: some View {
        Button("Retry") {
            if let store {
                Task { await playlist?.retry(store) }
            }
        }
        Button("Skip") {
            if let store {
                Task {
                    await playlist?.skip(store); if playlist?.finished == true {
                        dismiss()
                    }
                }
            }
        }
        Button("Stop") {
            if let store {
                playlist?.stop(store)
            }; dismiss()
        }
    }
}

#if os(visionOS)
    @MainActor
    private extension VideoPlayerView {
        func syncFramePackedCinemaIfNeeded(_ store: PlaybackStore) async {
            guard
                let layout = store.stereoPresentation.framePackedLayout,
                let player = store.player
            else {
                closeFramePackedCinemaIfNeeded()
                return
            }

            stereoRenderer?.invalidate()
            let renderer = StereoFrameRenderer(player: player, layout: layout)
            stereoRenderer = renderer
            cinema.present(player: player, title: store.item.displayTitle, stereoLayout: layout, stereoRenderer: renderer)

            guard !openedFramePackedCinema else { return }
            openedFramePackedCinema = true

            guard !cinema.isOpen else { return }

            switch await openImmersiveSpace(id: GusCinema.spaceID) {
            case .opened:
                cinema.setOpen(true)
            case .error, .userCancelled:
                cinema.clearPlaybackPresentation()
                cinema.setOpen(false)
                openedFramePackedCinema = false
                store.fallbackToWindowed2D()
            @unknown default:
                cinema.clearPlaybackPresentation()
                cinema.setOpen(false)
                openedFramePackedCinema = false
                store.fallbackToWindowed2D()
            }
        }

        func closeFramePackedCinemaIfNeeded() {
            guard openedFramePackedCinema else { return }
            openedFramePackedCinema = false
            stereoRenderer?.invalidate()
            stereoRenderer = nil
            cinema.clearPlaybackPresentation()
            Task {
                await dismissImmersiveSpace()
                await MainActor.run {
                    cinema.setOpen(false)
                    cinema.clearSelectedEnvironment()
                }
            }
        }
    }

    private struct SpatialPlaybackBadge: View {
        var body: some View {
            Label("Spatial", systemImage: "view.3d")
                .font(.callout.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .gusGlassCapsule()
                .foregroundStyle(.white)
                .padding()
                .accessibilityLabel("Spatial")
        }
    }

    private struct StereoFallbackNotice: View {
        let text: String

        var body: some View {
            Label(text, systemImage: "info.circle")
                .font(.callout.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .gusGlassCapsule()
                .foregroundStyle(.white)
                .padding(.horizontal)
                .accessibilityLabel(text)
        }
    }
#endif

// Platform-divergent player surface.
//
#if !os(iOS)
    /// Embedded AVKit surfaces for platforms with their own video presentation.
    private struct PlayerSurface: View {
        let player: AVPlayer
        let store: PlaybackStore
        let onSelectSource: (PlaybackStore.SourceOption) -> Void

        var body: some View {
            let controlsEnabled = store.state == .ready
            platformSurface(controlsEnabled: controlsEnabled)
                .disabled(!controlsEnabled)
                .allowsHitTesting(controlsEnabled)
                .accessibilityHidden(!controlsEnabled)
        }

        @ViewBuilder private func platformSurface(controlsEnabled: Bool) -> some View {
            #if os(tvOS)
                TVPlayerSurface(player: player, store: store, controlsEnabled: controlsEnabled, onSelectSource: onSelectSource)
            #elseif os(visionOS)
                VisionPlayerSurface(player: player, controlsEnabled: controlsEnabled)
            #else
                PiPCapablePlayerSurface(player: player, store: store, controlsEnabled: controlsEnabled)
            #endif
        }
    }
#endif
