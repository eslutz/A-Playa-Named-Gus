import AVKit
import SwiftUI

#if os(tvOS)
    /// tvOS-native `AVPlayerViewController`, which provides the full focus-engine
    /// transport and embedded-track menus. Server-only audio/subtitle choices and
    /// chapters use the transport bar's custom menus when AVKit cannot expose them.
    struct TVPlayerSurface: UIViewControllerRepresentable {
        let player: AVPlayer
        let store: PlaybackStore

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.delegate = context.coordinator
            controller.allowsPictureInPicturePlayback = false
            // tvOS AVKit always owns system video transport; its publishing toggle is unavailable.
            controller.appliesPreferredDisplayCriteriaAutomatically = true
            let info = UIHostingController(rootView: TVPlaybackInfo(store: store))
            info.title = String(localized: "Playback Details")
            info.preferredContentSize = CGSize(width: 1600, height: 500)
            controller.customInfoViewControllers = [info]
            context.coordinator.update(controller: controller, surface: self)
            return controller
        }

        func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
            if controller.player !== player {
                controller.player = player
            }
            context.coordinator.update(controller: controller, surface: self)
            if let info = controller.customInfoViewControllers.first as? UIHostingController<TVPlaybackInfo> {
                info.rootView = TVPlaybackInfo(store: store)
            }
        }

        static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
            coordinator.cancel()
            controller.player?.pause()
            controller.player = nil
            controller.delegate = nil
            controller.customInfoViewControllers = []
            controller.transportBarCustomMenuItems = []
        }

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        @MainActor final class Coordinator: NSObject, @MainActor AVPlayerViewControllerDelegate {
            private weak var store: PlaybackStore?

            func playerViewController(_ playerViewController: AVPlayerViewController, didSelect mediaSelectionOption: AVMediaSelectionOption?, in mediaSelectionGroup: AVMediaSelectionGroup) {
                store?.recordNativeTrackSelection(option: mediaSelectionOption, group: mediaSelectionGroup)
            }

            private var task: Task<Void, Never>?
            private var item: AVPlayerItem?
            private var nativeAudio = false
            private var nativeSubtitles = false

            func update(controller: AVPlayerViewController, surface: TVPlayerSurface) {
                store = surface.store
                guard item !== surface.player.currentItem else {
                    controller.transportBarCustomMenuItems = surface.transportMenuItems(nativeAudio: nativeAudio, nativeSubtitles: nativeSubtitles)
                    return
                }
                item = surface.player.currentItem
                nativeAudio = false
                nativeSubtitles = false
                controller.transportBarCustomMenuItems = surface.transportMenuItems(nativeAudio: false, nativeSubtitles: false)
                task?.cancel()
                task = Task { [weak self, weak controller] in
                    let audio = await surface.store.hasNativeTrackSelection(kind: .audio)
                    let subtitles = await surface.store.hasNativeTrackSelection(kind: .subtitle)
                    guard !Task.isCancelled, let self, let controller else { return }
                    nativeAudio = audio
                    nativeSubtitles = subtitles
                    controller.transportBarCustomMenuItems = surface.transportMenuItems(nativeAudio: audio, nativeSubtitles: subtitles)
                }
            }

            func cancel() {
                task?.cancel(); task = nil; item = nil
            }
        }

        private func transportMenuItems(nativeAudio: Bool, nativeSubtitles: Bool) -> [UIMenuElement] {
            let store = store
            var menus: [UIMenuElement] = []

            let audioOptions = store.audioOptions
            if audioOptions.count > 1, !nativeAudio {
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
            if !subtitleOptions.isEmpty, !nativeSubtitles {
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

            if !menus.isEmpty {
                menus = [UIMenu(title: String(localized: "Server Tracks"), image: UIImage(systemName: "slider.horizontal.3"), children: menus)]
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
