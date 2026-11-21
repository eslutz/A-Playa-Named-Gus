import SwiftUI

/// Offline audio on the watch: storage usage,
/// playable rows, and clear delete controls.
struct WatchDownloadsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads

    @State private var playerRecord: OfflineDownloadRecord?

    var body: some View {
        List {
            Section {
                LabeledContent(
                    "Used",
                    value: downloads.loadErrorMessage == nil ? ByteCountFormatter.string(
                        fromByteCount: downloads.totalByteCount(serverID: session.server.id, userID: session.user.id),
                        countStyle: .file
                    ) : String(localized: "Unavailable")
                )
            }

            if let failure = downloads.loadErrorMessage {
                Text(failure).foregroundStyle(.secondary)
                Button("Try Again") { downloads.load(serverID: session.server.id, userID: session.user.id) }
            }
            if downloads.records.isEmpty, downloads.loadErrorMessage == nil {
                ContentUnavailableView {
                    Label("No Downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Download music and audiobooks from Browse for offline listening.")
                }
            } else if !downloads.records.isEmpty {
                Section("Audio") {
                    ForEach(downloads.records) { record in
                        Button {
                            switch record.status {
                            case .paused, .failed:
                                Task { await downloads.resume(record, session: session) }
                            case .complete where record.item.isAudioPlayable:
                                playerRecord = record
                            default:
                                break
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.item.displayTitle)
                                    .lineLimit(2)
                                Text(statusText(for: record))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                if case .failed = record.status {
                                    Text("Try Again").font(.footnote)
                                } else if record.status == .paused {
                                    Text("Resume").font(.footnote)
                                }
                            }
                        }
                        .accessibilityLabel(record.playbackItem.mediaAccessibility.label)
                        .accessibilityValue([record.playbackItem.mediaAccessibility.value, statusText(for: record)].filter { !$0.isEmpty }.joined(separator: ", "))
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
        .refreshable { downloads.load(serverID: session.server.id, userID: session.user.id) }
        .alert("Download", isPresented: .init(
            get: { downloads.errorMessage != nil },
            set: {
                if !$0 {
                    downloads.clearError()
                }
            }
        )) {
            Button("OK", role: .cancel) { downloads.clearError() }
        } message: {
            Text(downloads.errorMessage ?? "")
        }
        .defersIntelligencePrompt(while: playerRecord != nil || downloads.errorMessage != nil)
        .sheet(item: $playerRecord) { record in
            WatchAudioPlayerView(tracks: [record.playbackItem], startIndex: 0, request: record.playbackRequest, localOnly: true)
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
        case let .failed(message):
            return message.isEmpty ? String(localized: "Download Failed", comment: "Failed download status label") : message
        }
    }
}
