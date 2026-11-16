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
    @State private var pendingSource: PlaybackStore.SourceOption?
    @State private var sharePlay = SharePlayCoordinator.shared
    #if os(visionOS)
        @State private var openedFramePackedCinema = false
        @State private var stereoRenderer: StereoFrameRenderer?
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let store, store.state == .ready, let player = store.player {
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
                        .ignoresSafeArea(edges: [.horizontal, .bottom])
                #endif
            } else if let message = playlist?.errorMessage {
                ContentUnavailableView {
                    Label("Playlist Paused", systemImage: "exclamationmark.triangle")
                } description: { Text(message) } actions: {
                    playlistRecoveryActions
                }
                .foregroundStyle(.white)
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
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .overlay(alignment: .topLeading) {
            #if !os(iOS)
                if store?.state != .ready {
                    Button("Close", systemImage: "xmark") { closePlayback() }
                        .frame(minWidth: 44, minHeight: 44)
                        .padding()
                        .foregroundStyle(.white)
                }
            #endif
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            #if os(iOS)
                HStack {
                    GusCloseButton { closePlayback() }
                        .buttonStyle(.bordered)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("VideoPlayer.close")
                    Spacer(minLength: 12)
                    if let store, store.state == .ready, hasPlaybackOptions(store) {
                        playbackOptions(store)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            #elseif !os(tvOS)
                if let store, store.state == .ready, hasPlaybackOptions(store) {
                    playbackOptions(store)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding()
                        .background(.bar)
                }
            #endif
        }
        .confirmationDialog("Switch Version", isPresented: Binding(get: { pendingSource != nil }, set: {
            if !$0 {
                pendingSource = nil
            }
        }), titleVisibility: .visible) {
            if let source = pendingSource, let store {
                Button("Start Over") { pendingSource = nil; Task { await store.selectMediaSource(id: source.id, fromBeginning: true) } }
                Button("Resume at \(PlaybackTime.accessibilityDuration(seconds: PlaybackTime.seconds(fromTicks: store.positionTicks)))") { pendingSource = nil; Task { await store.selectMediaSource(id: source.id, fromBeginning: false) } }
                    .disabled(source.runTimeTicks.map { $0 > 0 && store.positionTicks >= $0 } ?? false)
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
            if playlist.finished {
                dismiss()
            }
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
        // Natural end with nothing left to auto-play: close the player instead of
        // leaving a spinner over black.
        .onChange(of: store?.didFinishPlayback ?? false) { _, finished in
            if finished {
                dismiss()
            }
        }
        .onChange(of: playlists.identityRevision) { _, _ in
            if playlistID != nil {
                preparation?.cancel()
                if let store {
                    playlist?.stop(store)
                }
                dismiss()
            }
        }
        .onDisappear {
            preparation?.cancel()
            if let store {
                playlist?.stop(store)
            }
            #if os(visionOS)
                closeFramePackedCinemaIfNeeded()
            #endif
            store?.teardown()
        }
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
                playbackRequest: store?.request
            )
        }
    }

    private func closePlayback() {
        preparation?.cancel()
        if let store {
            playlist?.stop(store)
        }
        store?.teardown()
        dismiss()
    }

    #if !os(tvOS)
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

/// Platform-divergent player surface.
///
/// SwiftUI `VideoPlayer` exposes no Picture in Picture, so iOS/iPadOS and macOS use the
/// AVKit controller/view surfaces, which provide the PiP button and (on iOS) automatic
/// PiP when the app is backgrounded. visionOS uses `AVPlayerViewController` so Apple owns
/// the native expanded and immersive playback controls.
/// The concrete surface types (`TVPlayerSurface`, `VisionPlayerSurface`, `PiPCapablePlayerSurface`) live in
/// `Sources/Platform/PlayerSurface.swift`.
private struct PlayerSurface: View {
    let player: AVPlayer
    let store: PlaybackStore
    let onSelectSource: (PlaybackStore.SourceOption) -> Void

    var body: some View {
        #if os(tvOS)
            TVPlayerSurface(player: player, store: store, onSelectSource: onSelectSource)
        #elseif os(visionOS)
            VisionPlayerSurface(player: player)
        #else
            PiPCapablePlayerSurface(player: player, store: store)
        #endif
    }
}
