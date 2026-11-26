import AVKit
import SwiftUI
#if os(macOS)
    import OSLog
#endif

#if os(tvOS)
    /// tvOS-native `AVPlayerViewController`, which provides the full focus-engine
    /// transport and embedded-track menus. Server-only audio/subtitle choices and
    /// chapters use the transport bar's custom menus when AVKit cannot expose them.
    struct TVPlayerSurface: UIViewControllerRepresentable {
        let player: AVPlayer
        let store: PlaybackStore
        let controlsEnabled: Bool
        let onSelectSource: (PlaybackStore.SourceOption) -> Void

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.showsPlaybackControls = controlsEnabled
            controller.view.isUserInteractionEnabled = controlsEnabled
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
            controller.showsPlaybackControls = controlsEnabled
            controller.view.isUserInteractionEnabled = controlsEnabled
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
            private let renderer = NativeRenderObserver()

            func playerViewController(_: AVPlayerViewController, didSelect mediaSelectionOption: AVMediaSelectionOption?, in mediaSelectionGroup: AVMediaSelectionGroup) {
                store?.recordNativeTrackSelection(option: mediaSelectionOption, group: mediaSelectionGroup)
            }

            private var task: Task<Void, Never>?
            private var item: AVPlayerItem?
            private var nativeAudio = false
            private var nativeSubtitles = false

            func update(controller: AVPlayerViewController, surface: TVPlayerSurface) {
                store = surface.store
                renderer.bind(controller: controller, player: surface.player, store: surface.store)
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
                renderer.cancel()
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
                    children: [UIAction(title: String(localized: "Automatic"), state: store.audioMenuSelection == .automatic ? .on : .off) { _ in
                        Task { await store.selectAudioStream(index: nil) }
                    }] + audioOptions.map { option in
                        UIAction(
                            title: option.title,
                            state: store.audioMenuSelection == .stream(option.id) ? .on : .off
                        ) { _ in
                            Task { await store.selectAudioStream(index: option.id) }
                        }
                    }
                ))
            }

            let subtitleOptions = store.subtitleOptions
            if !subtitleOptions.isEmpty, !nativeSubtitles {
                let automatic = UIAction(title: String(localized: "Automatic"), state: store.subtitleMenuSelection == .automatic ? .on : .off) { _ in
                    Task { await store.selectAutomaticSubtitles() }
                }
                let off = UIAction(
                    title: String(localized: "Off", comment: "Subtitles off"),
                    state: store.subtitleMenuSelection == .off ? .on : .off
                ) { _ in
                    Task { await store.selectSubtitleStream(index: nil) }
                }
                let options = subtitleOptions.map { option in
                    UIAction(
                        title: option.title,
                        state: store.subtitleMenuSelection == .stream(option.id) ? .on : .off
                    ) { _ in
                        Task { await store.selectSubtitleStream(index: option.id) }
                    }
                }
                menus.append(UIMenu(
                    title: String(localized: "Subtitles", comment: "Player subtitles menu"),
                    image: UIImage(systemName: "captions.bubble"),
                    options: .singleSelection,
                    children: [automatic, off] + options
                ))
            }

            // AVKit explicitly supports only flat UIMenus, not nested menus.
            if store.mediaSourceOptions.count > 1 {
                menus.insert(UIMenu(title: String(localized: "Version"), image: UIImage(systemName: "film.stack"), children: store.mediaSourceOptions.map { source in
                    UIAction(title: source.title, state: source.id == store.selectedMediaSourceID ? .on : .off) { _ in onSelectSource(source) }
                }), at: 0)
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
    /// Present the AVKit controller itself so the system owns fullscreen chrome and dismissal.
    struct IOSFullscreenPlayer: UIViewControllerRepresentable {
        let store: PlaybackStore?
        let player: AVPlayer?
        let isReady: Bool
        let needsRecovery: Bool
        let didFinish: Bool
        let notice: String?
        let dismissNotice: () -> Void
        let close: () -> Void
        let teardown: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeUIViewController(context: Context) -> PresentationAnchor {
            let anchor = PresentationAnchor()
            anchor.appearance = { [weak coordinator = context.coordinator] in coordinator?.scheduleUpdate() }
            context.coordinator.anchor = anchor
            return anchor
        }

        func updateUIViewController(_ anchor: PresentationAnchor, context: Context) {
            context.coordinator.surface = self
            context.coordinator.scheduleUpdate()
        }

        static func dismantleUIViewController(_ anchor: PresentationAnchor, coordinator: Coordinator) {
            coordinator.detach()
        }

        final class PresentationAnchor: UIViewController {
            var appearance: (() -> Void)?

            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                appearance?()
            }
        }

        final class Coordinator: NSObject, @MainActor AVPlayerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
            weak var anchor: PresentationAnchor?
            var surface: IOSFullscreenPlayer?

            private let renderObserver = NativeRenderObserver()
            private var controller: AVPlayerViewController?
            private var isPresenting = false
            private var isRecovering = false
            private var isInPictureInPicture = false
            private var displayedNotice: String?
            private var finished = false
            private var updateScheduled = false

            func scheduleUpdate() {
                guard !finished, !updateScheduled else { return }
                updateScheduled = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    updateScheduled = false
                    updatePresentation()
                }
            }

            private func updatePresentation() {
                guard !finished, let anchor, let surface, !isPresenting, !isRecovering else { return }
                if surface.didFinish {
                    finished = true
                    if let controller, controller.presentingViewController != nil {
                        controller.dismiss(animated: false, completion: surface.close)
                    } else {
                        surface.close()
                    }
                    return
                }
                if let controller {
                    if surface.needsRecovery, !isInPictureInPicture, controller.presentingViewController != nil {
                        isRecovering = true
                        controller.dismiss(animated: false) { [weak self] in
                            self?.finishRecovery()
                        }
                    } else if controller.presentingViewController == nil {
                        if !isInPictureInPicture {
                            finishFromNativeDismissal()
                        }
                    } else if let store = surface.store, let player = surface.player {
                        if controller.player !== player {
                            controller.player = player
                        }
                        renderObserver.bind(controller: controller, player: player, store: store)
                        presentNoticeIfNeeded(on: controller)
                    }
                    return
                }

                guard !surface.needsRecovery, surface.isReady, let store = surface.store,
                      let player = surface.player, anchor.viewIfLoaded?.window != nil,
                      let presenter = anchor.parent, presenter.presentedViewController == nil else { return }
                let playerController = AVPlayerViewController()
                // Keep the SwiftUI owner mounted while AVKit covers the screen.
                // It drives queued-item preparation and playback recovery.
                playerController.modalPresentationStyle = .overFullScreen
                playerController.modalPresentationCapturesStatusBarAppearance = true
                playerController.player = player
                playerController.allowsPictureInPicturePlayback = true
                playerController.canStartPictureInPictureAutomaticallyFromInline = true
                // NowPlayingController owns publishing across all Gus video entry points.
                playerController.updatesNowPlayingInfoCenter = false
                playerController.delegate = self
                controller = playerController
                renderObserver.bind(controller: playerController, player: player, store: store)
                present(playerController, from: presenter)
            }

            private func present(_ controller: AVPlayerViewController, from presenter: UIViewController, completion: (() -> Void)? = nil) {
                isPresenting = true
                controller.presentationController?.delegate = self
                presenter.present(controller, animated: false) { [weak self] in
                    self?.isPresenting = false
                    completion?()
                    self?.scheduleUpdate()
                }
            }

            private func finishRecovery() {
                controller?.delegate = nil
                controller?.player = nil
                controller = nil
                displayedNotice = nil
                renderObserver.cancel()
                isRecovering = false
                scheduleUpdate()
            }

            private func finishFromNativeDismissal() {
                guard !finished, !isRecovering, !isInPictureInPicture else { return }
                finished = true
                surface?.close()
            }

            private func presentNoticeIfNeeded(on controller: AVPlayerViewController) {
                guard let surface, let notice = surface.notice, notice != displayedNotice,
                      controller.viewIfLoaded?.window != nil, controller.presentedViewController == nil else { return }
                displayedNotice = notice
                let alert = UIAlertController(title: String(localized: "Playback Notice"), message: notice, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { [weak self] _ in
                    self?.displayedNotice = nil
                    surface.dismissNotice()
                })
                controller.present(alert, animated: true)
            }

            func detach() {
                finished = true
                let teardown = surface?.teardown
                surface = nil
                renderObserver.cancel()
                if let controller {
                    controller.delegate = nil
                    controller.player = nil
                    self.controller = nil
                    if controller.presentingViewController != nil, !controller.isBeingDismissed {
                        controller.dismiss(animated: false)
                    }
                }
                Task { @MainActor in teardown?() }
            }

            func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
                scheduleUpdate()
            }

            func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator) {
                coordinator.animate(alongsideTransition: nil) { [weak self] context in
                    if !context.isCancelled {
                        self?.scheduleUpdate()
                    }
                }
            }

            func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ playerViewController: AVPlayerViewController) -> Bool {
                false
            }

            func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
                isInPictureInPicture = true
            }

            func playerViewController(_ playerViewController: AVPlayerViewController, failedToStartPictureInPictureWithError error: any Error) {
                isInPictureInPicture = false
                scheduleUpdate()
            }

            func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
                isInPictureInPicture = false
                scheduleUpdate()
            }

            func playerViewController(_ playerViewController: AVPlayerViewController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
                guard !finished, surface?.needsRecovery == false else {
                    completionHandler(false)
                    return
                }
                if playerViewController.presentingViewController != nil {
                    completionHandler(true)
                } else if let anchor, anchor.viewIfLoaded?.window != nil,
                          let presenter = anchor.parent, presenter.presentedViewController == nil
                {
                    present(playerViewController, from: presenter) { completionHandler(true) }
                } else {
                    completionHandler(false)
                }
            }
        }
    }

#elseif os(visionOS)
    /// visionOS-native `AVPlayerViewController` surface. AVKit owns the playback chrome,
    /// including expanded and immersive experience controls where the OS supports them.
    struct VisionPlayerSurface: UIViewControllerRepresentable {
        let player: AVPlayer
        let controlsEnabled: Bool

        func makeUIViewController(context _: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.showsPlaybackControls = controlsEnabled
            controller.view.isUserInteractionEnabled = controlsEnabled
            controller.allowsPictureInPicturePlayback = false
            controller.canStartPictureInPictureAutomaticallyFromInline = false
            controller.updatesNowPlayingInfoCenter = false
            controller.appliesPreferredDisplayCriteriaAutomatically = true

            controller.experienceController.allowedExperiences = .recommended(including: [.expanded, .immersive])
            controller.experienceController.configuration.expanded.automaticTransitionToImmersive = .default

            return controller
        }

        func updateUIViewController(_ controller: AVPlayerViewController, context _: Context) {
            controller.showsPlaybackControls = controlsEnabled
            controller.view.isUserInteractionEnabled = controlsEnabled
            if controller.player !== player {
                controller.player = player
            }
        }
    }

#elseif os(macOS)
    /// macOS `AVPlayerView` surface with Picture in Picture enabled.
    struct PiPCapablePlayerSurface: NSViewRepresentable {
        let player: AVPlayer
        let store: PlaybackStore
        let controlsEnabled: Bool

        func makeCoordinator() -> NativeRenderObserver {
            NativeRenderObserver()
        }

        func makeNSView(context: Context) -> AVPlayerView {
            let view = AVPlayerView()
            view.player = player
            view.allowsPictureInPicturePlayback = true
            view.controlsStyle = controlsEnabled ? .floating : .none
            context.coordinator.bind(view: view, player: player, store: store)
            return view
        }

        func updateNSView(_ view: AVPlayerView, context: Context) {
            view.controlsStyle = controlsEnabled ? .floating : .none
            // AVPlayerView keyboard shortcuts also work without visible chrome.
            // Resign only its own retained focus while preparation owns transport.
            if !controlsEnabled, let window = view.window,
               let responder = window.firstResponder as? NSView,
               responder === view || responder.isDescendant(of: view),
               !window.makeFirstResponder(nil)
            {
                Logger(category: .playback).debug("Native player declined keyboard-focus handoff during preparation")
            }
            if view.player !== player {
                view.player = player
            }
            context.coordinator.bind(view: view, player: player, store: store)
        }
    }
#endif

/// tvOS exposes no AVKit publishing toggle. Avoid a second app-owned video writer;
/// other platforms keep the existing single NowPlayingController owner.
extension NowPlayingController {
    func startVideo(player: AVPlayer, item: MediaItem, artworkURL: URL?, fallbackArtworkURLs: [URL] = [], artworkSession: URLSession = .shared) {
        #if !os(tvOS)
            start(player: player, item: item, artworkURL: artworkURL, fallbackArtworkURLs: fallbackArtworkURLs, artworkSession: artworkSession)
        #endif
    }
}

#if os(iOS) || os(tvOS) || os(macOS)
    /// Observe the actual native surface; a second layer would measure the wrong renderer.
    @MainActor
    final class NativeRenderObserver {
        private var observation: NSKeyValueObservation?
        private weak var item: AVPlayerItem?
        #if os(macOS)
            func bind(view: AVPlayerView, player: AVPlayer, store: PlaybackStore) {
                guard item !== player.currentItem, let current = player.currentItem else { return }
                item = current
                observation = view.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak store, weak current] view, _ in
                    Task { @MainActor in
                        guard view.isReadyForDisplay, let current else { return }
                        store?.recordFirstRenderReadiness(for: current)
                    }
                }
            }
        #else
            func bind(controller: AVPlayerViewController, player: AVPlayer, store: PlaybackStore) {
                guard item !== player.currentItem, let current = player.currentItem else { return }
                item = current
                observation = controller.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak store, weak current] controller, _ in
                    Task { @MainActor in
                        guard controller.isReadyForDisplay, let current else { return }
                        store?.recordFirstRenderReadiness(for: current)
                    }
                }
            }
        #endif
        func cancel() {
            observation?.invalidate(); observation = nil; item = nil
        }
    }
#endif
