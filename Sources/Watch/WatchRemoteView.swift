import SwiftUI

/// The watch's highest-value job: a remote for the household's other Jellyfin clients.
/// Lists controllable sessions and opens transport controls; stays live through the
/// server WebSocket (with polling fallback) only while frontmost.
struct WatchRemoteView: View {
    @Environment(SessionStore.self) private var session
    @State private var store: RemoteSessionsStore?

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Remote")
        .task {
            if store == nil {
                store = RemoteSessionsStore(session: session)
            }
            await store?.refresh()
            store?.startLiveUpdates()
        }
        .onDisappear {
            store?.stopLiveUpdates()
        }
    }

    private func content(_ store: RemoteSessionsStore) -> some View {
        LoadingStateView(
            state: store.state,
            isEmpty: store.sessions.isEmpty,
            emptyTitle: String(localized: "No Active Players", comment: "Remote control empty-state title when no Jellyfin sessions are playing"),
            emptySymbol: "play.tv",
            retryAction: { Task { await store.refresh() } }
        ) {
            List(store.sessions) { remote in
                NavigationLink {
                    WatchRemoteDetailView(sessionID: remote.id, store: store)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(remote.deviceName)
                            .font(.headline)
                        if let nowPlaying = remote.nowPlaying {
                            Text(nowPlaying.displayTitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(remote.client)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

/// Transport controls for one remote session: play/pause, seek ±15 s, previous/next,
/// volume, mute, stop.
struct WatchRemoteDetailView: View {
    let sessionID: String
    let store: RemoteSessionsStore

    private var remote: RemoteSession? {
        store.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let remote {
                    VStack(spacing: 2) {
                        Text(remote.nowPlaying?.displayTitle ?? String(localized: "Nothing Playing", comment: "Remote session idle state"))
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        if let ticks = remote.positionTicks, let runtime = remote.nowPlaying?.runTimeTicks, runtime > 0 {
                            ProgressView(value: Double(ticks), total: Double(runtime))
                                .accessibilityLabel(String(localized: "Playback position", comment: "Accessibility label for the remote session progress bar"))
                                .accessibilityValue(
                                    PlaybackTime.accessibilityProgressValue(
                                        currentSeconds: PlaybackTime.seconds(fromTicks: ticks),
                                        durationSeconds: PlaybackTime.seconds(fromTicks: runtime)
                                    )
                                )
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await store.seek(sessionID: sessionID, bySeconds: -15) }
                        } label: {
                            Image(systemName: "gobackward.15")
                        }
                        .accessibilityLabel(String(localized: "Back 15 seconds", comment: "Accessibility label for the seek-back 15 seconds button"))

                        Button {
                            Task { await store.togglePlayPause(sessionID: sessionID) }
                        } label: {
                            Image(systemName: remote.isPaused ? "play.circle.fill" : "pause.circle.fill")
                                .font(.title2)
                        }
                        .accessibilityLabel(remote.isPaused ? String(localized: "Play", comment: "Accessibility label for the play button") : String(localized: "Pause", comment: "Accessibility label for the pause button"))

                        Button {
                            Task { await store.seek(sessionID: sessionID, bySeconds: 15) }
                        } label: {
                            Image(systemName: "goforward.15")
                        }
                        .accessibilityLabel(String(localized: "Forward 15 seconds", comment: "Accessibility label for the seek-forward 15 seconds button"))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        Button {
                            Task { await store.previousTrack(sessionID: sessionID) }
                        } label: {
                            Image(systemName: "backward.fill")
                        }
                        .accessibilityLabel(String(localized: "Previous Track", comment: "Accessibility label for the previous track button"))

                        Button {
                            Task { await store.toggleMute(sessionID: sessionID) }
                        } label: {
                            Image(systemName: remote.isMuted ? "speaker.slash.fill" : "speaker.fill")
                        }
                        .accessibilityLabel(remote.isMuted ? String(localized: "Unmute", comment: "Accessibility label for the unmute button") : String(localized: "Mute", comment: "Accessibility label for the mute button"))

                        Button {
                            Task { await store.nextTrack(sessionID: sessionID) }
                        } label: {
                            Image(systemName: "forward.fill")
                        }
                        .accessibilityLabel(String(localized: "Next Track", comment: "Accessibility label for the next track button"))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        Button {
                            Task { await store.volumeDown(sessionID: sessionID) }
                        } label: {
                            Image(systemName: "speaker.minus.fill")
                        }
                        .accessibilityLabel(String(localized: "Volume down", comment: "Accessibility label for the volume-down button"))

                        Button {
                            Task { await store.volumeUp(sessionID: sessionID) }
                        } label: {
                            Image(systemName: "speaker.plus.fill")
                        }
                        .accessibilityLabel(String(localized: "Volume up", comment: "Accessibility label for the volume-up button"))

                        Button(role: .destructive) {
                            Task { await store.stopPlayback(sessionID: sessionID) }
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .accessibilityLabel(String(localized: "Stop", comment: "Accessibility label for the stop playback button"))
                    }
                    .buttonStyle(.plain)
                } else {
                    ContentUnavailableView {
                        Label("Player Gone", systemImage: "play.slash")
                    } description: {
                        Text("This player is no longer active.")
                    }
                }
            }
        }
        .navigationTitle(remote?.deviceName ?? "Remote")
        .task {
            store.startLiveUpdates()
        }
        .onDisappear {
            store.stopLiveUpdates()
        }
    }
}
