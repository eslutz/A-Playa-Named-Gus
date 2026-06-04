import AVKit
import JellyfinAPI
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
    let item: BaseItemDto

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
                            .safeAreaInset(edge: .bottom) {
                                PlaybackControlsOverlay(store: store)
                            }
                    } else {
                        PlayerSurface(player: player)
                            .ignoresSafeArea()
                            .safeAreaInset(edge: .bottom) {
                                PlaybackControlsOverlay(store: store)
                            }
                    }
                #else
                    PlayerSurface(player: player)
                        .ignoresSafeArea()
                        .safeAreaInset(edge: .bottom) {
                            PlaybackControlsOverlay(store: store)
                        }
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

private struct PlaybackControlsOverlay: View {
    let store: PlaybackStore

    var body: some View {
        HStack(spacing: 14) {
            #if os(visionOS)
                ViewingModeMenu(store: store)
            #endif

            if !store.audioOptions.isEmpty {
                Menu {
                    ForEach(store.audioOptions) { option in
                        Button {
                            Task { await store.selectAudioStream(index: option.id) }
                        } label: {
                            Label(option.title, systemImage: store.selectedAudioStreamIndex == option.id ? "checkmark" : "waveform")
                        }
                    }
                } label: {
                    Label("Audio", systemImage: "waveform")
                }
            }

            if !store.subtitleOptions.isEmpty {
                Menu {
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
                } label: {
                    Label("Subtitles", systemImage: "captions.bubble")
                }
            }

            if !store.chapterTargets.isEmpty {
                Menu {
                    ForEach(store.chapterTargets) { chapter in
                        Button(chapter.title) {
                            Task { await store.seek(to: chapter) }
                        }
                    }
                } label: {
                    Label("Chapters", systemImage: "list.bullet.rectangle")
                }
            }

            AirPlayRoutePicker()

            if let next = store.nextUpItem, store.isNextUpPromptVisible {
                Button {
                    Task { await store.playNextUp() }
                } label: {
                    Label("Play Next: \(next.displayTitle)", systemImage: "forward.end.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
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
private struct PlayerSurface: View {
    let player: AVPlayer

    var body: some View {
        #if os(tvOS)
            TVPlayerSurface(player: player)
        #else
            VideoPlayer(player: player)
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
#endif
