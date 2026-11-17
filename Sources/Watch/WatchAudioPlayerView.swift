import SwiftUI

/// Compact on-watch audio player over the shared `AudioPlayerStore` queue engine.
/// Long-form audio routes through the system route picker (AirPods/speaker) and feeds
/// the watch's Now Playing surface via `NowPlayingController`.
struct WatchAudioPlayerView: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    let tracks: [MediaItem]
    let startIndex: Int
    var request: PlaybackRequest? = nil
    var continuation: AudioQueueContinuation? = nil
    var localOnly = false

    @State private var store: AudioPlayerStore?
    @State private var pendingSourceID: String?
    @State private var confirmingVersion = false

    var body: some View {
        ScrollView {
            if let store {
                if let notice = store.trackSelectionNotice {
                    VStack(spacing: 4) {
                        Text(notice).font(.footnote).foregroundStyle(.secondary)
                        Button("OK") { store.trackSelectionNotice = nil }
                    }
                }
                LoadingStateView(state: store.state, retryAction: { Task { await store.start() } }, preservesContent: store.hasPreparedContent) {
                    VStack {
                        playerControls(store).disabled(store.state != .loaded)
                        if store.isLoadingQueue {
                            ProgressView().accessibilityLabel("Loading Queue")
                        }
                        if let message = store.queueErrorMessage {
                            Text(message).foregroundStyle(.secondary)
                            Button("Try Again") { Task { await store.loadMoreQueue() } }
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
                let store = AudioPlayerStore(session: session, tracks: tracks, startIndex: startIndex, request: request, continuation: continuation, downloads: downloads, localOnly: localOnly)
                self.store = store
                await store.start()
            }
        }
        .onDisappear {
            store?.teardown()
        }
        .confirmationDialog("Change Version?", isPresented: $confirmingVersion) {
            Button("Start Over") { changeVersion(fromBeginning: true) }
            Button("Resume at Timestamp") { changeVersion(fromBeginning: false) }
                .disabled(!canResumePendingSource)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Different versions may have different timelines.")
        }
    }

    private func playerControls(_ store: AudioPlayerStore) -> some View {
        VStack(spacing: 8) {
            Text(store.currentTrack?.displayTitle ?? "")
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if store.mediaSourceOptions.count > 1 {
                Picker("Version", selection: Binding(get: { store.selectedMediaSourceID ?? "" }, set: { id in
                    guard id != store.selectedMediaSourceID else { return }
                    pendingSourceID = id
                    if store.currentTime > 0 {
                        confirmingVersion = true
                    } else {
                        changeVersion(fromBeginning: true)
                    }
                })) {
                    ForEach(Array(store.mediaSourceOptions.enumerated()), id: \.offset) { index, source in
                        if let id = source.id {
                            Text(source.name ?? String(localized: "Version \(index + 1)")).tag(id)
                        }
                    }
                }
            }

            if store.audioOptions.count > 1 {
                Picker("Audio", selection: Binding(get: { store.audioMenuSelection }, set: { selection in
                    guard let selection else { return }
                    switch selection {
                    case .automatic: Task { await store.selectAudioStream(index: nil) }
                    case let .stream(index): Task { await store.selectAudioStream(index: index) }
                    case .off: break
                    }
                })) {
                    if store.audioMenuSelection == nil {
                        Text("Unavailable").tag(nil as PlaybackTrackMenuSelection?).disabled(true)
                    }
                    Text("Automatic").tag(PlaybackTrackMenuSelection.automatic as PlaybackTrackMenuSelection?)
                    ForEach(store.audioOptions) { option in
                        Text(option.title).tag(PlaybackTrackMenuSelection.stream(option.id) as PlaybackTrackMenuSelection?)
                    }
                }
            }

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
                    Image(systemName: store.isPlaybackRequested ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                }
                .accessibilityLabel(store.isPlaybackRequested ? String(localized: "Pause", comment: "Accessibility label for the pause button") : String(localized: "Play", comment: "Accessibility label for the play button"))

                Button {
                    Task { await store.next() }
                } label: {
                    Image(systemName: "forward.fill")
                }
                .disabled(!store.hasNext)
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
        }
    }

    private func speedBinding(_ store: AudioPlayerStore) -> Binding<Double> {
        Binding {
            store.playbackRate
        } set: { rate in
            store.playbackRate = rate
        }
    }

    private func changeVersion(fromBeginning: Bool) {
        guard let id = pendingSourceID, let store else { return }
        Task { await store.selectMediaSource(id: id, fromBeginning: fromBeginning) }
    }

    private var canResumePendingSource: Bool {
        guard let store, let source = store.mediaSourceOptions.first(where: { $0.id == pendingSourceID }) else { return false }
        return PlaybackActionPosition.canResume(at: PlaybackTime.ticks(fromSeconds: store.currentTime), durationTicks: source.runTimeTicks)
    }
}
