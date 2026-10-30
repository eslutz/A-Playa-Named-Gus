import SwiftUI

/// Separates artwork and transport at an active display fold while keeping each
/// region scrollable. Playback and scrubbing state remain owned by the caller.
struct AdaptiveAudioLayout<Artwork: View, Controls: View>: View {
    @ViewBuilder let artwork: Artwork
    @ViewBuilder let controls: Controls

    var body: some View {
        GeometryReader { geometry in
            #if os(iOS)
                if #available(iOS 27.1, *), !geometry.reservedRegions(kind: .division).isEmpty {
                    ArrangementView {
                        ScrollView { artwork.padding(24).frame(maxWidth: .infinity) }
                    } secondary: {
                        ScrollView { controls.padding(24).frame(maxWidth: .infinity) }
                    }
                    .arrangementViewStyle(.split)
                } else {
                    continuousLayout(geometry: geometry)
                }
            #else
                continuousLayout(geometry: geometry)
            #endif
        }
    }

    private func continuousLayout(geometry: GeometryProxy) -> some View {
        ScrollView {
            #if os(iOS)
                if geometry.size.width < 600, geometry.size.height > geometry.size.width {
                    VStack(spacing: 24) {
                        artwork.frame(width: min(geometry.size.width - 48, 320))
                        Spacer(minLength: 24)
                        controls
                    }
                    .frame(minHeight: max(0, geometry.size.height - 48))
                    .padding(24)
                } else {
                    adaptiveContent(geometry: geometry)
                }
            #else
                adaptiveContent(geometry: geometry)
            #endif
        }
    }

    private var artworkLimit: CGFloat {
        #if os(iOS)
            DeviceIdentity.usesIPadPresentation ? 300 : 240
        #elseif os(tvOS)
            480
        #else
            240
        #endif
    }

    private func adaptiveContent(geometry: GeometryProxy) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 24) {
                artwork.frame(width: min(geometry.size.height * 0.5, artworkLimit))
                controls.frame(minWidth: 280, maxWidth: 560)
            }
            VStack(spacing: 24) { artwork; controls }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: minimumContentHeight(geometry))
    }

    private func minimumContentHeight(_ geometry: GeometryProxy) -> CGFloat {
        #if os(iOS)
            DeviceIdentity.usesIPadPresentation ? max(0, geometry.size.height - 48) : 0
        #else
            0
        #endif
    }
}

extension View {
    @ViewBuilder func gusSessionPlayerHost(state: RootNavigationState, enabled: Bool = true) -> some View {
        #if os(macOS)
            self
        #else
            modifier(SessionPlayerHost(state: state, enabled: enabled))
        #endif
    }

    @ViewBuilder func gusAudioHost(coordinator: AudioPlaybackCoordinator, enabled: Bool = true) -> some View {
        #if os(macOS)
            sheet(isPresented: audioPresentation(coordinator, enabled: enabled)) {
                SessionAudioPlayer()
                    // GeometryReader has no intrinsic height for AppKit sheet sizing.
                    .frame(minWidth: 640, idealWidth: 720, minHeight: 420, idealHeight: 520)
            }
        #else
            fullScreenCover(isPresented: audioPresentation(coordinator, enabled: enabled)) { SessionAudioPlayer() }
        #endif
    }

    @ViewBuilder func gusNowPlaying(coordinator: AudioPlaybackCoordinator, usesTabAccessory: Bool = true, enabled: Bool = true) -> some View {
        #if os(iOS)
            modifier(IOSNowPlaying(coordinator: coordinator, usesTabAccessory: usesTabAccessory, enabled: enabled))
        #elseif os(tvOS) || os(macOS)
            // A split view's outer toolbar may not reach its active detail stack.
            // Keep the session return control outside that navigation ownership.
            safeAreaInset(edge: .bottom) {
                if enabled, !coordinator.isPresented, let store = coordinator.store {
                    NowPlayingReturnView(coordinator: coordinator, store: store)
                        .padding()
                        .background(.regularMaterial)
                }
            }
        #elseif os(visionOS)
            toolbar {
                if enabled, !coordinator.isPresented, let store = coordinator.store {
                    ToolbarItem(placement: .bottomOrnament) {
                        NowPlayingReturnView(coordinator: coordinator, store: store)
                            .frame(width: 420)
                    }
                }
            }
        #else
            toolbar {
                if enabled, !coordinator.isPresented, let store = coordinator.store {
                    ToolbarItem { NowPlayingReturnView(coordinator: coordinator, store: store) }
                }
            }
        #endif
    }
}

@MainActor private func audioPresentation(_ coordinator: AudioPlaybackCoordinator, enabled: Bool) -> Binding<Bool> {
    Binding(get: { enabled && coordinator.isPresented }, set: { isPresented in
        if isPresented {
            coordinator.isPresented = true
        } else {
            coordinator.close()
        }
    })
}

#if !os(macOS)
    private struct SessionPlayerHost: ViewModifier {
        @Bindable var state: RootNavigationState
        let enabled: Bool
        func body(content: Content) -> some View {
            content.fullScreenCover(item: Binding(get: { enabled ? state.playerItem : nil }, set: { state.playerItem = $0 })) { ref in
                PresentedPlayer(item: ref.item, localOnly: ref.localOnly == true, playlistID: ref.playlistID, playlistEntryID: ref.playlistEntryID, playlistFromBeginning: ref.playlistFromBeginning == true, playlistShuffled: ref.playlistShuffled == true, playbackStart: ref.playbackStart, close: { state.playerItem = nil })
            }
        }
    }
#endif

private struct SessionAudioPlayer: View {
    @Environment(AudioPlaybackCoordinator.self) private var audio
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    var body: some View {
        #if os(tvOS)
            Group {
                if let store = audio.store {
                    AudioPlayerView(store: store)
                } else {
                    ContentUnavailableView("Nothing Playing", systemImage: "music.note")
                }
            }
            .ignoresSafeArea()
            .gusTVCanvas()
        #else
            NavigationStack {
                Group {
                    if let store = audio.store {
                        AudioPlayerView(store: store)
                    } else {
                        ContentUnavailableView("Nothing Playing", systemImage: "music.note")
                    }
                }
                .toolbar {
                    #if os(iOS)
                        ToolbarItem(placement: .cancellationAction) {
                            ImmersiveDismissButton { audio.close() }
                                .accessibilityIdentifier("AudioPlayer.close")
                        }
                        if widthClass == .compact {
                            ToolbarItem(placement: .principal) {
                                Text(audio.store?.currentTrack?.album ?? String(localized: "Now Playing"))
                                    .font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                            }
                        } else if DeviceIdentity.usesIPadPresentation {
                            ToolbarItem(placement: .principal) { Text("Now Playing").font(.headline) }
                        }
                    #else
                        ToolbarItem(placement: .cancellationAction) { Button("Done", systemImage: "xmark") { audio.close() } }
                        ToolbarItem { Button("Stop", systemImage: "stop.fill") { audio.stop() } }
                    #endif
                }
                .accessibilityAction(.escape) { audio.close() }
            }
            .background {
                Rectangle().fill(.background).ignoresSafeArea()
            }
            .gusTVCanvas()
            #if os(tvOS)
                .onExitCommand { audio.close() }
            #endif
        #endif
    }
}

private struct NowPlayingReturnView: View {
    @Environment(SessionStore.self) private var session
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    let coordinator: AudioPlaybackCoordinator
    let store: AudioPlayerStore
    var body: some View {
        HStack {
            Button { coordinator.reopen() } label: {
                returnLabel
            }
            .gusPhonePlainButtonStyle()
            .accessibilityIdentifier("NowPlaying.reopen")
            .gusTVFocus(id: "nowPlaying", section: "nowPlaying", ids: ["nowPlaying"], initial: true)
            .accessibilityHint("Opens Now Playing")
            Button { store.playPause() } label: {
                Label(store.isPlaying ? "Pause" : "Play", systemImage: store.isPlaying ? "pause.fill" : "play.fill")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityIdentifier("NowPlaying.playPause")
            .disabled(store.state != .loaded)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .tvFocusSection()
    }

    @ViewBuilder private var returnLabel: some View {
        #if os(iOS)
            if widthClass == .compact || DeviceIdentity.usesIPadPresentation {
                compactLabel
            } else {
                legacyLabel
            }
        #else
            legacyLabel
        #endif
    }

    private var legacyLabel: some View {
        Label(store.currentTrack?.displayTitle ?? String(localized: "Now Playing"), systemImage: "music.note")
            .lineLimit(1).frame(minHeight: 44)
    }

    private var compactLabel: some View {
        HStack(spacing: 12) {
            ArtworkTile(url: store.currentTrack.flatMap { session.mediaProvider.primaryImageURL(for: $0, context: .posterGrid) }, aspectRatio: 1, placeholderSymbol: "music.note")
                .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.currentTrack?.displayTitle ?? String(localized: "Now Playing")).font(.subheadline.weight(.medium))
                if let artist = store.currentTrack?.albumArtist ?? store.currentTrack?.artists.first {
                    Text(artist).font(.caption).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Feature bindings express an intent; the session host owns the actual presentation.
struct SessionPlayerRequest: ViewModifier {
    @Environment(RootNavigationState.self) private var navigation
    @Environment(AudioPlaybackCoordinator.self) private var audio
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    @Binding var item: ItemRef?

    func body(content: Content) -> some View {
        content.onChange(of: item, initial: true) { _, ref in
            guard let ref else { return }
            guard ref.serverID == nil || ref.serverID == session.server.id,
                  ref.userID == nil || ref.userID == session.user.id else { item = nil; return }
            if ref.item.isAudioPlayable, ContentRatingGate.admitsStored(ref.item) {
                audio.play(tracks: [ref.item], localOnly: ref.localOnly == true, playbackStart: ref.playbackStart, session: session, downloads: downloads)
            } else {
                audio.stop()
                navigation.playerItem = ref
            }
            item = nil
        }
    }
}

#if os(iOS)
    private struct IOSNowPlaying: ViewModifier {
        @Environment(\.horizontalSizeClass) private var widthClass
        let coordinator: AudioPlaybackCoordinator
        let usesTabAccessory: Bool
        let enabled: Bool
        private var isVisible: Bool {
            enabled && coordinator.store != nil && !coordinator.isPresented
        }

        func body(content: Content) -> some View {
            // Size-class changes must not replace the content subtree: doing so
            // tears down its sheets and navigation while a player is presented.
            tabAccessory(content: content)
                .safeAreaInset(edge: .bottom) {
                    if isVisible, !supportsTabAccessory || widthClass != .compact || !usesTabAccessory {
                        returnControl.background(.bar)
                    }
                }
        }

        private var supportsTabAccessory: Bool {
            if #available(iOS 26.1, *) {
                true
            } else {
                false
            }
        }

        @ViewBuilder private func tabAccessory(content: Content) -> some View {
            if #available(iOS 26.1, *) {
                content.tabViewBottomAccessory(isEnabled: isVisible && widthClass == .compact && usesTabAccessory) { returnControl }
            } else {
                // The conditional accessory API arrived in 26.1. Keep OS 26.0
                // on the existing return bar without branching on player state.
                content
            }
        }

        @ViewBuilder private var returnControl: some View {
            if let store = coordinator.store {
                NowPlayingReturnView(coordinator: coordinator, store: store).padding(.horizontal)
            }
        }
    }
#endif
