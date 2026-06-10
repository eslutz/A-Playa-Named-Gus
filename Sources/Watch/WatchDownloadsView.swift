import SwiftUI

/// Offline audio on the watch: storage summary against the conservative watch budget,
/// playable rows, and clear delete controls.
struct WatchDownloadsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads

    @State private var playerItem: MediaItem?

    var body: some View {
        List {
            Section {
                LabeledContent(
                    "Used",
                    value: ByteCountFormatter.string(
                        fromByteCount: downloads.totalByteCount(serverID: session.server.id, userID: session.user.id),
                        countStyle: .file
                    )
                )
                LabeledContent(
                    "Limit",
                    value: ByteCountFormatter.string(fromByteCount: OfflineDownloadStore.softCapBytes, countStyle: .file)
                )
            }

            if downloads.records.isEmpty {
                ContentUnavailableView {
                    Label("No Downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Download music and audiobooks from Browse for offline listening.")
                }
            } else {
                Section("Audio") {
                    ForEach(downloads.records) { record in
                        Button {
                            if record.status.isComplete, record.item.isAudioPlayable {
                                playerItem = record.item
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.item.displayTitle)
                                    .lineLimit(2)
                                Text(statusText(for: record))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                downloads.delete(record, serverID: session.server.id, userID: session.user.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        .task {
            downloads.load(serverID: session.server.id, userID: session.user.id)
        }
        .sheet(item: $playerItem) { item in
            WatchAudioPlayerView(tracks: [item], startIndex: 0)
        }
    }

    private func statusText(for record: OfflineDownloadRecord) -> String {
        switch record.status {
        case .complete:
            return ByteCountFormatter.string(fromByteCount: record.byteCount, countStyle: .file)
        case .queued:
            return String(localized: "Queued", comment: "Download queued status label")
        case .downloading:
            return record.progress.formatted(.percent.precision(.fractionLength(0)))
        case .paused:
            return String(localized: "Paused", comment: "Download paused status label")
        case .failed:
            return String(localized: "Download Failed", comment: "Failed download status label")
        }
    }
}
