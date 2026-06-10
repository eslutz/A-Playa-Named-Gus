import SwiftUI

/// Now-playing surface for songs and audiobooks: artwork, scrubber, queue transport,
/// shuffle/repeat, and — for audiobooks — playback speed and chapter navigation.
struct AudioPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    let store: AudioPlayerStore

    @State private var scrubTime: Double = 0
    @State private var isScrubbing = false

    private var track: MediaItem? {
        store.currentTrack
    }

    var body: some View {
        VStack(spacing: 24) {
            artwork
            titleBlock
            progressBlock
            transportControls
            secondaryControls
        }
        .padding(32)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: store.currentTime) { _, time in
            guard !isScrubbing else { return }
            scrubTime = time
        }
    }

    private var artwork: some View {
        AsyncPoster(
            url: track.flatMap { session.mediaProvider.primaryImageURL(for: $0, context: .posterGrid) },
            placeholderSymbol: track?.type == .audioBook ? "book" : "music.note"
        )
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 320)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(track?.displayTitle ?? "")
                .font(.title2.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let artist = track?.albumArtist ?? track?.artists.first {
                Text(artist)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            if let album = track?.album {
                Text(album)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var progressBlock: some View {
        VStack(spacing: 4) {
            #if !os(tvOS)
                Slider(value: $scrubTime, in: 0 ... max(store.duration, 1)) { editing in
                    isScrubbing = editing
                    if !editing {
                        Task { await store.seek(to: scrubTime) }
                    }
                }
                .accessibilityLabel("Playback position")
            #endif

            HStack {
                Text(timeText(store.currentTime))
                Spacer()
                Text(timeText(store.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 36) {
            Button {
                store.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .symbolVariant(store.isShuffled ? .circle.fill : .none)
            }
            .accessibilityLabel(store.isShuffled ? "Shuffle On" : "Shuffle Off")

            Button {
                Task { await store.previous() }
            } label: {
                Image(systemName: "backward.fill")
            }
            .accessibilityLabel("Previous Track")

            Button {
                store.playPause()
            } label: {
                Image(systemName: store.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
            }
            .accessibilityLabel(store.isPlaying ? "Pause" : "Play")

            Button {
                Task { await store.next() }
            } label: {
                Image(systemName: "forward.fill")
            }
            .disabled(!store.queue.hasNext)
            .accessibilityLabel("Next Track")

            Button {
                store.cycleRepeatMode()
            } label: {
                Image(systemName: repeatSymbol)
            }
            .accessibilityLabel(repeatAccessibilityLabel)
        }
        .font(.title2)
        .buttonStyle(.plain)
    }

    private var secondaryControls: some View {
        HStack(spacing: 24) {
            if track?.type == .audioBook {
                speedMenu
                chaptersMenu
            }
            AirPlayRoutePicker()
        }
    }

    private var speedMenu: some View {
        Menu {
            ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                Button {
                    store.playbackRate = rate
                } label: {
                    Label(
                        rate.formatted(.number.precision(.fractionLength(0 ... 2))) + "×",
                        systemImage: store.playbackRate == rate ? "checkmark" : "gauge.with.needle"
                    )
                }
            }
        } label: {
            Label("Speed", systemImage: "gauge.with.needle")
        }
        .accessibilityLabel("Playback Speed")
    }

    @ViewBuilder
    private var chaptersMenu: some View {
        if let track, !track.chapters.isEmpty {
            Menu {
                ForEach(PlaybackChapter.seekTargets(for: track)) { chapter in
                    Button(chapter.title) {
                        Task { await store.seek(to: chapter.seconds) }
                    }
                }
            } label: {
                Label("Chapters", systemImage: "list.bullet")
            }
            .accessibilityLabel("Chapters")
        }
    }

    private var repeatSymbol: String {
        switch store.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat.circle.fill"
        case .one: return "repeat.1.circle.fill"
        }
    }

    private var repeatAccessibilityLabel: String {
        switch store.repeatMode {
        case .off: return String(localized: "Repeat Off", comment: "Repeat mode accessibility label")
        case .all: return String(localized: "Repeat All", comment: "Repeat mode accessibility label")
        case .one: return String(localized: "Repeat One", comment: "Repeat mode accessibility label")
        }
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Presents the audio player for a single song/audiobook item, creating its own store.
/// Used by `playerPresentation` when an audio item is opened from detail/search/rails.
struct AudioPlayerScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    let item: MediaItem

    @State private var store: AudioPlayerStore?

    var body: some View {
        Group {
            if let store {
                AudioPlayerView(store: store)
            } else {
                ProgressView()
            }
        }
        .task {
            if store == nil {
                let store = AudioPlayerStore(session: session, tracks: [item], downloads: downloads)
                self.store = store
                await store.start()
            }
        }
        .onDisappear {
            store?.teardown()
        }
    }
}
