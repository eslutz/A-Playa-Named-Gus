import SwiftUI

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
            sheet(isPresented: audioPresentation(coordinator, enabled: enabled)) { SessionAudioPlayer() }
        #else
            fullScreenCover(isPresented: audioPresentation(coordinator, enabled: enabled)) { SessionAudioPlayer() }
        #endif
    }

    @ViewBuilder func gusNowPlaying(coordinator: AudioPlaybackCoordinator, usesTabAccessory: Bool = true, enabled: Bool = true) -> some View {
        #if os(iOS)
            modifier(IOSNowPlaying(coordinator: coordinator, usesTabAccessory: usesTabAccessory, enabled: enabled))
        #elseif os(tvOS)
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
                PresentedPlayer(item: ref.item, localOnly: ref.localOnly == true, close: { state.playerItem = nil })
            }
        }
    }
#endif

private struct SessionAudioPlayer: View {
    @Environment(AudioPlaybackCoordinator.self) private var audio
    var body: some View {
        NavigationStack {
            Group {
                if let store = audio.store {
                    AudioPlayerView(store: store)
                } else {
                    ContentUnavailableView("Nothing Playing", systemImage: "music.note")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { audio.close() } }
                ToolbarItem { Button("Stop") { audio.stop() } }
            }
            .accessibilityAction(.escape) { audio.close() }
        }
        .background {
            #if os(tvOS)
                Color.black.ignoresSafeArea()
            #else
                Rectangle().fill(.background).ignoresSafeArea()
            #endif
        }
        #if os(tvOS)
        .onExitCommand { audio.close() }
        #endif
    }
}

private struct NowPlayingReturnView: View {
    let coordinator: AudioPlaybackCoordinator
    let store: AudioPlayerStore
    var body: some View {
        HStack {
            Button { coordinator.reopen() } label: {
                Label(store.currentTrack?.displayTitle ?? String(localized: "Now Playing"), systemImage: "music.note")
                    .lineLimit(1)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("NowPlaying.reopen")
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
                audio.play(tracks: [ref.item], localOnly: ref.localOnly == true, session: session, downloads: downloads)
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
            if #available(iOS 26.1, *) {
                // Size-class changes must not replace the content subtree: doing so
                // tears down its sheets and navigation while a player is presented.
                content
                    .tabViewBottomAccessory(isEnabled: isVisible && widthClass == .compact && usesTabAccessory) { returnControl }
                    .safeAreaInset(edge: .bottom) {
                        if isVisible, widthClass != .compact || !usesTabAccessory {
                            returnControl.background(.bar)
                        }
                    }
            } else {
                content.safeAreaInset(edge: .bottom) {
                    if isVisible {
                        returnControl.background(.bar)
                    }
                }
            }
        }

        @ViewBuilder private var returnControl: some View {
            if let store = coordinator.store {
                NowPlayingReturnView(coordinator: coordinator, store: store).padding(.horizontal)
            }
        }
    }
#endif
