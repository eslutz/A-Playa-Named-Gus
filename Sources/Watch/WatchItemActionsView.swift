import SwiftUI

/// Actions for one item on the watch. Audio plays on the watch (and can download for
/// offline); video offers the constrained on-watch player plus remote playback; books
/// point back to iPhone/iPad per the brief's audio-first scope.
struct WatchItemActionsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    let item: MediaItem

    @State private var isAudioPlayerPresented = false
    @State private var isVideoPlayerPresented = false
    @State private var isTargetPickerPresented = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    WatchPoster(item: item)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayTitle)
                            .font(.headline)
                            .lineLimit(3)
                        if let runtime = item.runtimeText {
                            Text(runtime)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                if item.isAudioPlayable {
                    Button {
                        isAudioPlayerPresented = true
                    } label: {
                        Label("Play on Watch", systemImage: "applewatch")
                    }
                    downloadRow
                } else if item.type == .book {
                    Text("Read this book in A Playa Named Gus on iPhone or iPad.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        isTargetPickerPresented = true
                    } label: {
                        Label("Play On…", systemImage: "play.tv")
                    }
                    Button {
                        isVideoPlayerPresented = true
                    } label: {
                        Label("Play on Watch", systemImage: "applewatch")
                    }
                }
            }
        }
        .navigationTitle(item.displayTitle)
        .sheet(isPresented: $isAudioPlayerPresented) {
            WatchAudioPlayerView(tracks: [item], startIndex: 0)
        }
        .sheet(isPresented: $isVideoPlayerPresented) {
            WatchVideoPlayerView(item: item)
        }
        .sheet(isPresented: $isTargetPickerPresented) {
            WatchPlayTargetPicker(item: item, startPositionTicks: PlaybackTime.resumePositionTicks(for: item))
        }
        .task {
            downloads.load(serverID: session.server.id, userID: session.user.id)
        }
    }

    /// Offline audio per the brief: audio-only, conservative budget, clear states.
    @ViewBuilder
    private var downloadRow: some View {
        if let record = downloads.record(for: item, serverID: session.server.id, userID: session.user.id) {
            switch record.status {
            case .complete:
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            case .queued, .downloading:
                Label("Downloading", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            case .paused, .failed:
                retryDownloadButton
            }
        } else if OfflineDownloadEligibility.canDownload(item) {
            retryDownloadButton
        }
    }

    private var retryDownloadButton: some View {
        Button {
            Task { await downloads.download(item, session: session) }
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }
    }
}
