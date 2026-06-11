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
        #if !os(tvOS)
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .padding(12)
            }
            .buttonStyle(.plain)
            .gusGlassSurface(in: Circle())
            .tint(.white)
            .foregroundStyle(.white)
            .padding()
            .accessibilityLabel("Close Player")
        }
        #endif
        #if !os(tvOS)
        .overlay(alignment: .topTrailing) {
            if let store {
                VStack(alignment: .trailing, spacing: 8) {
                    PlaybackOptionsOverlay(store: store)
                    #if os(visionOS)
                        if store.isSpatialPlaybackActive {
                            SpatialPlaybackBadge()
                        }

                        if let notice = store.stereoFallbackNotice {
                            StereoFallbackNotice(text: notice)
                        }
                    #endif
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

private struct PlaybackOptionsOverlay: View {
    let store: PlaybackStore

    var body: some View {
        HStack(spacing: 6) {
            AirPlayRoutePicker()

            PlaybackOptionsMenu(store: store)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .gusGlassCapsule()
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

            #if os(visionOS)
                ViewingModeMenu(store: store)
            #endif

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
                let syncPlayStore = SyncPlayStore(session: session)
                syncPlay = syncPlayStore
                await syncPlayStore.loadGroups()
            }
            syncPlay?.attachPlayer(store.player)
        }
        // PlaybackStore rebuilds its AVPlayer across Play Next; re-attach so SyncPlay
        // commands and observers always target the live player.
        .task(id: store.player == nil) {
            syncPlay?.attachPlayer(store.player)
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
    let store: PlaybackStore

    var body: some View {
        #if os(tvOS)
            TVPlayerSurface(player: player, store: store)
        #elseif os(visionOS)
            VideoPlayer(player: player)
        #else
            PiPCapablePlayerSurface(player: player)
        #endif
    }
}

#if os(tvOS)
    /// tvOS-native `AVPlayerViewController`, which provides the full focus-engine
    /// transport. Jellyfin stream selection (server-side audio/subtitle indexes) and
    /// chapters ride the transport bar's custom menus — AVKit's own media-selection
    /// menu only covers HLS alternates, which transcoded streams don't carry.
    private struct TVPlayerSurface: UIViewControllerRepresentable {
        let player: AVPlayer
        let store: PlaybackStore

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.allowsPictureInPicturePlayback = false
            controller.transportBarCustomMenuItems = transportMenuItems()
            return controller
        }

        func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
            if controller.player !== player {
                controller.player = player
            }
            controller.transportBarCustomMenuItems = transportMenuItems()
        }

        private func transportMenuItems() -> [UIMenuElement] {
            let store = store
            var menus: [UIMenuElement] = []

            let audioOptions = store.audioOptions
            if !audioOptions.isEmpty {
                menus.append(UIMenu(
                    title: String(localized: "Audio", comment: "Player audio track menu"),
                    image: UIImage(systemName: "waveform"),
                    options: .singleSelection,
                    children: audioOptions.map { option in
                        UIAction(
                            title: option.title,
                            state: store.selectedAudioStreamIndex == option.id ? .on : .off
                        ) { _ in
                            Task { await store.selectAudioStream(index: option.id) }
                        }
                    }
                ))
            }

            let subtitleOptions = store.subtitleOptions
            if !subtitleOptions.isEmpty {
                let off = UIAction(
                    title: String(localized: "Off", comment: "Subtitles off"),
                    state: store.selectedSubtitleStreamIndex == nil ? .on : .off
                ) { _ in
                    Task { await store.selectSubtitleStream(index: nil) }
                }
                let options = subtitleOptions.map { option in
                    UIAction(
                        title: option.title,
                        state: store.selectedSubtitleStreamIndex == option.id ? .on : .off
                    ) { _ in
                        Task { await store.selectSubtitleStream(index: option.id) }
                    }
                }
                menus.append(UIMenu(
                    title: String(localized: "Subtitles", comment: "Player subtitles menu"),
                    image: UIImage(systemName: "captions.bubble"),
                    options: .singleSelection,
                    children: [off] + options
                ))
            }

            let chapters = store.chapterTargets
            if !chapters.isEmpty {
                menus.append(UIMenu(
                    title: String(localized: "Chapters", comment: "Player chapters menu"),
                    image: UIImage(systemName: "list.bullet"),
                    children: chapters.map { chapter in
                        UIAction(title: chapter.title) { _ in
                            Task { await store.seek(to: chapter) }
                        }
                    }
                ))
            }

            return menus
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
