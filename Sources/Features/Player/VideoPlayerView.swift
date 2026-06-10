import AVKit
import SwiftUI

/// Pure-AVKit player surface.
///
/// `VideoPlayer` on iOS/macOS/visionOS; `AVPlayerViewController` (via a representable) on
/// tvOS, which has no SwiftUI `VideoPlayer`. The `PlaybackStore` owns the `AVPlayer` and
/// tears it down on dismiss.
struct VideoPlayerView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PlaybackRefreshStore.self) private var playbackRefresh
    @Environment(OfflineDownloadStore.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    #if os(visionOS)
        @Environment(CinemaModel.self) private var cinema
        @Environment(\.openImmersiveSpace) private var openImmersiveSpace
        @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    #endif
    let item: MediaItem

    @State private var store: PlaybackStore?
    #if os(visionOS)
        @State private var openedFramePackedCinema = false
        @State private var stereoRenderer: StereoFrameRenderer?
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let store, let player = store.player {
                #if os(visionOS)
                    if store.isFramePackedImmersivePlaybackActive {
                        Color.black
                            .ignoresSafeArea()
                    } else {
                        PlayerSurface(player: player)
                            .ignoresSafeArea()
                    }
                #else
                    PlayerSurface(player: player)
                        .ignoresSafeArea()
                #endif
            } else if case let .failed(message)? = store?.state {
                ContentUnavailableView {
                    Label("Can't Play This", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
                .foregroundStyle(.white)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        #if !os(tvOS)
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .padding()
            }
            .buttonStyle(.plain)
            .tint(.white)
            .padding(8)
            .accessibilityLabel("Close Player")
        }
        #endif
        #if !os(tvOS) && !os(visionOS)
        .overlay(alignment: .topTrailing) {
            if let store {
                PlaybackOptionsOverlay(store: store)
                    .padding()
            }
        }
        #endif
        #if os(visionOS)
        .overlay(alignment: .topTrailing) {
            if let store {
                VStack(alignment: .trailing, spacing: 8) {
                    if store.isSpatialPlaybackActive {
                        SpatialPlaybackBadge()
                    }

                    if let notice = store.stereoFallbackNotice {
                        StereoFallbackNotice(text: notice)
                    }
                }
            }
        }
        #endif
        .task {
            if store == nil {
                let store = PlaybackStore(item: item, session: session, playbackRefresh: playbackRefresh, downloads: downloads)
                self.store = store
                await store.prepare()
            }
        }
        #if os(visionOS)
        .task(id: store?.stereoPresentation) {
            guard let store else { return }
            await syncFramePackedCinemaIfNeeded(store)
        }
        #endif
        .onDisappear {
            #if os(visionOS)
                closeFramePackedCinemaIfNeeded()
            #endif
            store?.teardown()
        }
    }
}

#if os(visionOS)
    private extension VideoPlayerView {
        @MainActor
        func syncFramePackedCinemaIfNeeded(_ store: PlaybackStore) async {
            guard
                let layout = store.stereoPresentation.framePackedLayout,
                let player = store.player
            else {
                closeFramePackedCinemaIfNeeded()
                return
            }

            let renderer = StereoFrameRenderer(player: player, layout: layout)
            stereoRenderer = renderer
            cinema.present(player: player, title: item.displayTitle, stereoLayout: layout, stereoRenderer: renderer)

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

        @MainActor
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
                .background(.ultraThinMaterial, in: Capsule())
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
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
                .padding(.horizontal)
                .accessibilityLabel(text)
        }
    }
#endif

private struct PlaybackOptionsOverlay: View {
    let store: PlaybackStore

    var body: some View {
        HStack(spacing: 6) {
            AirPlayRoutePicker()

            PlaybackOptionsMenu(store: store)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.white)
    }
}

private struct PlaybackOptionsMenu: View {
    @Environment(SessionStore.self) private var session
    let store: PlaybackStore

    @State private var syncPlay: SyncPlayStore?

    var body: some View {
        Menu {
            if !store.audioOptions.isEmpty {
                Section("Audio") {
                    ForEach(store.audioOptions) { option in
                        Button {
                            Task { await store.selectAudioStream(index: option.id) }
                        } label: {
                            Label(option.title, systemImage: store.selectedAudioStreamIndex == option.id ? "checkmark" : "waveform")
                        }
                    }
                }
            }

            if !store.subtitleOptions.isEmpty {
                Section("Subtitles") {
                    Button {
                        Task { await store.selectSubtitleStream(index: nil) }
                    } label: {
                        Label("Off", systemImage: store.selectedSubtitleStreamIndex == nil ? "checkmark" : "captions.bubble")
                    }
                    ForEach(store.subtitleOptions) { option in
                        Button {
                            Task { await store.selectSubtitleStream(index: option.id) }
                        } label: {
                            Label(option.title, systemImage: store.selectedSubtitleStreamIndex == option.id ? "checkmark" : "captions.bubble")
                        }
                    }
                }
            }

            if !store.chapterTargets.isEmpty {
                Section("Chapters") {
                    ForEach(store.chapterTargets) { chapter in
                        Button(chapter.title) {
                            Task { await store.seek(to: chapter) }
                        }
                    }
                }
            }

            if let next = store.nextUpItem, store.isNextUpPromptVisible {
                Section {
                    Button {
                        Task { await store.playNextUp() }
                    } label: {
                        Label("Play Next: \(next.displayTitle)", systemImage: "forward.end.fill")
                    }
                }
            }

            if let syncPlay, syncPlay.isSupported {
                syncPlaySection(syncPlay)
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Playback Options")
        .task {
            if syncPlay == nil {
                let store = SyncPlayStore(session: session, player: store.player)
                syncPlay = store
                await store.loadGroups()
            }
        }
        .onDisappear {
            syncPlay?.stop()
        }
    }

    private func syncPlaySection(_ syncPlay: SyncPlayStore) -> some View {
        Section("SyncPlay") {
            if syncPlay.isInGroup {
                Button(role: .destructive) {
                    Task { await syncPlay.leave() }
                } label: {
                    Label("Leave Watch Party", systemImage: "person.2.slash")
                }
            } else {
                ForEach(syncPlay.groups) { group in
                    Button {
                        Task { await syncPlay.join(groupID: group.id) }
                    } label: {
                        Label("Join \(group.name) (\(group.participants.count))", systemImage: "person.2")
                    }
                }
                Button {
                    Task { await syncPlay.createGroup(named: String(localized: "Gus Watch Party", comment: "Default SyncPlay group name")) }
                } label: {
                    Label("Start Watch Party", systemImage: "person.2.badge.plus")
                }
            }
        }
    }
}

#if os(visionOS)
    private struct ViewingModeMenu: View {
        let store: PlaybackStore

        var body: some View {
            Menu {
                viewingModeButton(.automatic, title: "Auto", systemImage: "wand.and.stars")
                viewingModeButton(.twoD, title: "2D", systemImage: "rectangle")
                viewingModeButton(.spatial, title: "Spatial", systemImage: "view.3d")
            } label: {
                Label("Viewing Mode", systemImage: "view.3d")
            }
        }

        private func viewingModeButton(_ mode: Stereo3DViewingMode, title: LocalizedStringKey, systemImage: String) -> some View {
            Button {
                Task { await store.selectViewingMode(mode) }
            } label: {
                Label(title, systemImage: store.viewingMode == mode ? "checkmark" : systemImage)
            }
        }
    }
#endif

/// Platform-divergent player surface.
///
/// SwiftUI `VideoPlayer` exposes no Picture in Picture, so iOS/iPadOS and macOS use the
/// AVKit controller/view surfaces, which provide the PiP button and (on iOS) automatic
/// PiP when the app is backgrounded. visionOS keeps `VideoPlayer` (no PiP there).
private struct PlayerSurface: View {
    let player: AVPlayer

    var body: some View {
        #if os(tvOS)
            TVPlayerSurface(player: player)
        #elseif os(visionOS)
            VideoPlayer(player: player)
        #else
            PiPCapablePlayerSurface(player: player)
        #endif
    }
}

#if os(tvOS)
    /// tvOS-native `AVPlayerViewController`, which provides the full focus-engine transport.
    private struct TVPlayerSurface: UIViewControllerRepresentable {
        let player: AVPlayer

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.allowsPictureInPicturePlayback = false
            return controller
        }

        func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
            if controller.player !== player {
                controller.player = player
            }
        }
    }

#elseif os(iOS)
    /// iOS/iPadOS `AVPlayerViewController` surface with Picture in Picture enabled,
    /// including automatic PiP on backgrounding (requires the `audio` background mode,
    /// declared in Info.plist).
    private struct PiPCapablePlayerSurface: UIViewControllerRepresentable {
        let player: AVPlayer

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.allowsPictureInPicturePlayback = true
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            return controller
        }

        func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
            if controller.player !== player {
                controller.player = player
            }
        }
    }

#elseif os(macOS)
    /// macOS `AVPlayerView` surface with Picture in Picture enabled.
    private struct PiPCapablePlayerSurface: NSViewRepresentable {
        let player: AVPlayer

        func makeNSView(context: Context) -> AVPlayerView {
            let view = AVPlayerView()
            view.player = player
            view.allowsPictureInPicturePlayback = true
            view.controlsStyle = .floating
            return view
        }

        func updateNSView(_ view: AVPlayerView, context: Context) {
            if view.player !== player {
                view.player = player
            }
        }
    }
#endif
