import AVKit
import SwiftUI

#if os(tvOS)
    /// tvOS-native `AVPlayerViewController`, which provides the full focus-engine
    /// transport. Jellyfin stream selection (server-side audio/subtitle indexes) and
    /// chapters ride the transport bar's custom menus — AVKit's own media-selection
    /// menu only covers HLS alternates, which transcoded streams don't carry.
    struct TVPlayerSurface: UIViewControllerRepresentable {
        let player: AVPlayer
        let store: PlaybackStore

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.allowsPictureInPicturePlayback = false
            // tvOS AVKit always owns system video transport; its publishing toggle is unavailable.
            controller.appliesPreferredDisplayCriteriaAutomatically = true
            let info = UIHostingController(rootView: TVPlaybackInfo(store: store))
            info.title = String(localized: "Playback Info")
            controller.customInfoViewControllers = [info]
            controller.transportBarCustomMenuItems = transportMenuItems()
            return controller
        }

        func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
            if controller.player !== player {
                controller.player = player
            }
            controller.transportBarCustomMenuItems = transportMenuItems()
            if let info = controller.customInfoViewControllers.first as? UIHostingController<TVPlaybackInfo> {
                info.rootView = TVPlaybackInfo(store: store)
            }
        }

        static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
            controller.player?.pause()
            controller.player = nil
            controller.customInfoViewControllers = []
            controller.transportBarCustomMenuItems = []
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

            if store.nextUpItem != nil, !store.usesPlaylistOrder {
                menus.append(UIAction(title: String(localized: "Next Episode"), image: UIImage(systemName: "forward.end")) { _ in
                    Task { await store.playNextUp() }
                })
            }
            return menus
        }
    }

#elseif os(iOS)
    /// iOS/iPadOS `AVPlayerViewController` surface with Picture in Picture enabled,
    /// including automatic PiP on backgrounding (requires the `audio` background mode,
    /// declared in Info.plist).
    struct PiPCapablePlayerSurface: UIViewControllerRepresentable {
        let player: AVPlayer

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.allowsPictureInPicturePlayback = true
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            // NowPlayingController owns the lock-screen transport; leaving AVKit's
            // automatic publishing on would race two writers on the process-global
            // MPNowPlayingInfoCenter (flickering metadata/artwork).
            controller.updatesNowPlayingInfoCenter = false
            return controller
        }

        func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
            if controller.player !== player {
                controller.player = player
            }
        }
    }

#elseif os(visionOS)
    /// visionOS-native `AVPlayerViewController` surface. AVKit owns the playback chrome,
    /// including expanded and immersive experience controls where the OS supports them.
    struct VisionPlayerSurface: UIViewControllerRepresentable {
        let player: AVPlayer

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.showsPlaybackControls = true
            controller.allowsPictureInPicturePlayback = false
            controller.canStartPictureInPictureAutomaticallyFromInline = false
            controller.updatesNowPlayingInfoCenter = false
            controller.appliesPreferredDisplayCriteriaAutomatically = true

            controller.experienceController.allowedExperiences = .recommended(including: [.expanded, .immersive])
            controller.experienceController.configuration.expanded.automaticTransitionToImmersive = .default

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
    struct PiPCapablePlayerSurface: NSViewRepresentable {
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

/// tvOS exposes no AVKit publishing toggle. Avoid a second app-owned video writer;
/// other platforms keep the existing single NowPlayingController owner.
extension NowPlayingController {
    func startVideo(player: AVPlayer, item: MediaItem, artworkURL: URL?) {
        #if !os(tvOS)
            start(player: player, item: item, artworkURL: artworkURL)
        #endif
    }
}
