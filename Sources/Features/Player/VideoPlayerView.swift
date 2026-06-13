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
    @Environment(\.dismiss) private var dismiss
    #if os(visionOS)
        @Environment(CinemaModel.self) private var cinema
        @Environment(\.openImmersiveSpace) private var openImmersiveSpace
        @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    #endif
    let item: MediaItem

    @State private var store: PlaybackStore?
    @State private var sharePlay = SharePlayCoordinator.shared
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
                        PlayerSurface(player: player, store: store)
                            .ignoresSafeArea()
                    }
                #else
                    PlayerSurface(player: player, store: store)
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
        .task {
            if store == nil {
                let store = PlaybackStore(item: item, session: session, playbackRefresh: playbackRefresh, downloads: downloads)
                self.store = store
                await store.prepare()
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
        .onDisappear {
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
                item: item,
                serverID: session.server.id,
                userID: session.user.id
            )
        }
    }

    private func attachSharePlayPlayer() {
        guard let store else { return }
        sharePlay.attachPlayer(store.player, item: store.item)
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

            stereoRenderer?.invalidate()
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

    var body: some View {
        #if os(tvOS)
            TVPlayerSurface(player: player, store: store)
        #elseif os(visionOS)
            VisionPlayerSurface(player: player)
        #else
            PiPCapablePlayerSurface(player: player)
        #endif
    }
}
