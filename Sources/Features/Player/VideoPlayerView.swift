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
    let item: BaseItemDto

    @State private var store: PlaybackStore?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let store, let player = store.player {
                PlayerSurface(player: player)
                    .ignoresSafeArea()
                    .safeAreaInset(edge: .bottom) {
                        PlaybackControlsOverlay(store: store)
                    }
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
        .task {
            if store == nil {
                let store = PlaybackStore(item: item, session: session, playbackRefresh: playbackRefresh, downloads: downloads)
                self.store = store
                await store.prepare()
            }
        }
        .onDisappear {
            store?.teardown()
        }
    }
}

private struct PlaybackControlsOverlay: View {
    let store: PlaybackStore

    var body: some View {
        HStack(spacing: 14) {
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
