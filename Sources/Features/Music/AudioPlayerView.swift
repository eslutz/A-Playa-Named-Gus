import SwiftUI

/// Now-playing surface for songs and audiobooks: artwork, scrubber, queue transport,
/// shuffle/repeat, and — for audiobooks — playback speed and chapter navigation.
struct AudioPlayerView: View {
    @Environment(AudioPlaybackCoordinator.self) private var audio
    @Environment(SessionStore.self) private var session
    let store: AudioPlayerStore

    @ScaledMetric(relativeTo: .title) private var playPauseIconSize: CGFloat = 56

    @State private var scrubTime: Double = 0
    @State private var isScrubbing = false

    private var track: MediaItem? {
        store.currentTrack
    }

    var body: some View {
        LoadingStateView(state: store.state, retryAction: { audio.retry() }) {
            AdaptiveAudioLayout { artwork } controls: { controls }
        }
        .onChange(of: store.currentTime, initial: true) { _, time in
            guard !isScrubbing else { return }
            scrubTime = time
        }
    }

    private var controls: some View {
        VStack(spacing: 20) { titleBlock; progressBlock; transportControls; secondaryControls }
    }

    private var artwork: some View {
        ArtworkTile(
            url: track.flatMap { session.mediaProvider.primaryImageURL(for: $0, context: .posterGrid) },
            aspectRatio: 1,
            placeholderSymbol: track?.type == .audioBook ? "book" : "music.note"
        )
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
                .accessibilityValue(Text(
                    "\(timeText(scrubTime)) of \(timeText(store.duration))",
                    comment: "VoiceOver value for the playback scrubber, e.g. 1:30 of 4:05"
                ))
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { shuffleButton; previousButton; playPauseButton; nextButton; repeatButton }
            VStack(spacing: 12) {
                HStack(spacing: 12) { previousButton; playPauseButton; nextButton }
                HStack(spacing: 24) { shuffleButton; repeatButton }
            }
        }
        .font(.title2)
        .buttonStyle(AudioTransportStyle())
    }

    private var shuffleButton: some View {
        Button {
            store.toggleShuffle()
        } label: {
            Image(systemName: "shuffle")
                .symbolVariant(store.isShuffled ? .circle.fill : .none)
        }
        .accessibilityLabel(
            store.isShuffled
                ? String(localized: "Shuffle On", comment: "Accessibility label for the shuffle button when active")
                : String(localized: "Shuffle Off", comment: "Accessibility label for the shuffle button when inactive")
        )
    }

    private var previousButton: some View {
        Button {
            Task { await store.previous() }
        } label: {
            Image(systemName: "backward.fill")
        }
        .accessibilityLabel(String(localized: "Previous Track", comment: "Accessibility label for the previous track button"))
    }

    private var playPauseButton: some View {
        Button {
            store.playPause()
        } label: {
            Image(systemName: store.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: playPauseIconSize))
        }
        .accessibilityLabel(
            store.isPlaying
                ? String(localized: "Pause", comment: "Accessibility label for the pause button")
                : String(localized: "Play", comment: "Accessibility label for the play button")
        )
    }

    private var nextButton: some View {
        Button {
            Task { await store.next() }
        } label: {
            Image(systemName: "forward.fill")
        }
        .disabled(!store.queue.hasNext)
        .accessibilityLabel(String(localized: "Next Track", comment: "Accessibility label for the next track button"))
    }

    private var repeatButton: some View {
        Button {
            store.cycleRepeatMode()
        } label: {
            Image(systemName: repeatSymbol)
        }
        .accessibilityLabel(repeatAccessibilityLabel)
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

/// Entry fallback for audio reached through an existing presentation.
struct AudioPlayerScreen: View {
    @Environment(AudioPlaybackCoordinator.self) private var audio
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    let item: MediaItem
    var localOnly = false
    var body: some View {
        Group {
            if let store = audio.store {
                AudioPlayerView(store: store)
            } else {
                ProgressView()
            }
        }
        .task {
            if audio.store == nil {
                audio.play(tracks: [item], localOnly: localOnly, session: session, downloads: downloads)
            }
        }
    }
}

private struct AudioTransportStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
