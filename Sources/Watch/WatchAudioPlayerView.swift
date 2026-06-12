import SwiftUI

/// Compact on-watch audio player over the shared `AudioPlayerStore` queue engine.
/// Long-form audio routes through the system route picker (AirPods/speaker) and feeds
/// the watch's Now Playing surface via `NowPlayingController`.
struct WatchAudioPlayerView: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    let tracks: [MediaItem]
    let startIndex: Int

    @State private var store: AudioPlayerStore?

    var body: some View {
        VStack(spacing: 8) {
            if let store {
                Text(store.currentTrack?.displayTitle ?? "")
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if store.duration > 0 {
                    ProgressView(value: min(store.currentTime, store.duration), total: store.duration)
                        .accessibilityLabel(String(localized: "Playback position", comment: "Accessibility label for the audio playback progress bar"))
                        .accessibilityValue(
                            PlaybackTime.accessibilityProgressValue(
                                currentSeconds: min(store.currentTime, store.duration),
                                durationSeconds: store.duration
                            )
                        )
                }

                HStack(spacing: 14) {
                    Button {
                        Task { await store.previous() }
                    } label: {
                        Image(systemName: "backward.fill")
                    }
                    .accessibilityLabel(String(localized: "Previous Track", comment: "Accessibility label for the previous track button"))

                    Button {
                        store.playPause()
                    } label: {
                        Image(systemName: store.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title)
                    }
                    .accessibilityLabel(store.isPlaying ? String(localized: "Pause", comment: "Accessibility label for the pause button") : String(localized: "Play", comment: "Accessibility label for the play button"))

                    Button {
                        Task { await store.next() }
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    .disabled(!store.queue.hasNext)
                    .accessibilityLabel(String(localized: "Next Track", comment: "Accessibility label for the next track button"))
                }
                .buttonStyle(.plain)

                if store.currentTrack?.type == .audioBook {
                    Picker("Speed", selection: speedBinding(store)) {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                            Text("\(rate.formatted(.number.precision(.fractionLength(0 ... 2))))×").tag(rate)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .padding(.horizontal, 4)
        .task {
            if store == nil {
                let store = AudioPlayerStore(session: session, tracks: tracks, startIndex: startIndex, downloads: downloads)
                self.store = store
                await store.start()
            }
        }
        .onDisappear {
            store?.teardown()
        }
    }

    private func speedBinding(_ store: AudioPlayerStore) -> Binding<Double> {
        Binding {
            store.playbackRate
        } set: { rate in
            store.playbackRate = rate
        }
    }
}
