import SwiftUI

#if os(tvOS)
    import AVKit

    /// AVKit owns transport, seeking and output routing; the store retains queue/reporting ownership.
    struct TVAudioPlayerSurface: UIViewControllerRepresentable {
        let player: AVPlayer
        let store: AudioPlayerStore
        let onClose: () -> Void
        let onStop: () -> Void
        let artworkURL: URL?

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.delegate = context.coordinator
            controller.transportBarCustomMenuItems = [
                UIAction(title: String(localized: "Previous Track"), image: UIImage(systemName: "backward.end.fill")) { _ in Task { await store.previous() } },
                UIAction(title: String(localized: "Next Track"), image: UIImage(systemName: "forward.end.fill")) { _ in Task { await store.next() } },
                UIAction(title: String(localized: "Queue"), image: UIImage(systemName: "list.bullet")) { [weak controller] _ in
                    let host = UIHostingController(rootView: NavigationStack { TVAudioQueue(store: store) })
                    host.modalPresentationStyle = .fullScreen
                    controller?.present(host, animated: true)
                },
                UIAction(title: String(localized: "Stop"), image: UIImage(systemName: "stop.fill")) { _ in onStop() },
            ]
            controller.allowsPictureInPicturePlayback = false
            let artwork = UIHostingController(rootView: artwork)
            controller.addChild(artwork)
            if let overlay = controller.contentOverlayView {
                artwork.view.backgroundColor = .clear
                artwork.view.translatesAutoresizingMaskIntoConstraints = false
                overlay.addSubview(artwork.view)
                NSLayoutConstraint.activate([
                    artwork.view.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
                    artwork.view.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
                    artwork.view.topAnchor.constraint(equalTo: overlay.topAnchor),
                    artwork.view.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
                ])
            }
            artwork.didMove(toParent: controller)
            let queue = UIHostingController(rootView: TVAudioQueue(store: store))
            queue.title = String(localized: "Queue")
            controller.customInfoViewControllers = [queue]
            updateMetadata()
            return controller
        }

        func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
            if controller.player !== player {
                controller.player = player
            }
            if let host = controller.children.first(where: { $0 is UIHostingController<AnyView> }) as? UIHostingController<AnyView> {
                host.rootView = artwork
            }
            updateMetadata()
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(onClose: onClose)
        }

        @MainActor final class Coordinator: NSObject, @MainActor AVPlayerViewControllerDelegate {
            let onClose: () -> Void
            init(onClose: @escaping () -> Void) {
                self.onClose = onClose
            }

            func playerViewControllerShouldDismiss(_ playerViewController: AVPlayerViewController) -> Bool {
                onClose()
                return false
            }
        }

        private var artwork: AnyView {
            AnyView(VStack(spacing: 24) {
                ArtworkTile(url: artworkURL, aspectRatio: 1, placeholderSymbol: "music.note")
                    .frame(width: 440, height: 440).clipShape(RoundedRectangle(cornerRadius: 20))
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 120)
                .background(.black).foregroundStyle(.white).accessibilityHidden(true))
        }

        private func updateMetadata() {
            let title = AVMutableMetadataItem()
            title.identifier = .commonIdentifierTitle
            title.value = (store.currentTrack?.displayTitle ?? "") as NSString
            title.extendedLanguageTag = "und"
            let artist = AVMutableMetadataItem()
            artist.identifier = .commonIdentifierArtist
            artist.value = (store.currentTrack?.albumArtist ?? store.currentTrack?.artists.first ?? "") as NSString
            artist.extendedLanguageTag = "und"
            player.currentItem?.externalMetadata = [title, artist]
        }
    }

    private struct TVAudioQueue: View {
        @Environment(\.dismiss) private var dismiss
        let store: AudioPlayerStore
        var body: some View {
            List {
                Section {
                    HStack(spacing: 32) {
                        Button("Previous", systemImage: "backward.end.fill") { Task { await store.previous() } }
                        Button("Next", systemImage: "forward.end.fill") { Task { await store.next() } }
                        Button(store.isShuffled ? "Shuffle On" : "Shuffle Off", systemImage: "shuffle") { store.toggleShuffle() }
                        Button(store.repeatMode == .off ? "Repeat Off" : store.repeatMode == .one ? "Repeat One" : "Repeat All", systemImage: "repeat") { store.cycleRepeatMode() }
                    }
                }
                if store.currentTrack?.type == .audioBook {
                    Picker("Playback Speed", selection: Binding(get: { store.playbackRate }, set: { store.playbackRate = $0 })) {
                        ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { Text("\($0, specifier: "%.2g")×").tag($0) }
                    }
                }
                if let track = store.currentTrack, !track.chapters.isEmpty {
                    Section("Chapters") {
                        ForEach(PlaybackChapter.seekTargets(for: track)) { chapter in
                            Button(chapter.title) { Task { await store.seek(to: chapter.seconds) } }
                        }
                    }
                }
                ForEach(store.queue.order, id: \.self) { index in
                    let track = store.queue.tracks[index]
                    Button(track.displayTitle) {
                        if let id = track.id {
                            Task { await store.select(trackID: id) }
                        }
                    }
                }
            }
            .navigationTitle("Queue")
            .toolbar { ToolbarItem(placement: .cancellationAction) { GusCloseButton { dismiss() } } }
            .gusTVNativeControls()
        }
    }
#endif
