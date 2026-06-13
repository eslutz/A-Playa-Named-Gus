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

            if #available(visionOS 26.0, *) {
                controller.experienceController.allowedExperiences = .recommended(including: [.expanded, .immersive])
                controller.experienceController.configuration.expanded.automaticTransitionToImmersive = .default
            } else {
                controller.experienceController.allowedExperiences = .recommended(including: [.expanded])
            }

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
