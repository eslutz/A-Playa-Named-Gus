import SwiftUI

struct DownloadsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    @State private var playerItem: ItemRef?

    var body: some View {
        List {
            Section {
                LabeledContent("Storage Used", value: ByteCountFormatter.string(fromByteCount: downloads.totalByteCount(serverID: session.server.id, userID: session.user.id), countStyle: .file))
                LabeledContent("Soft Cap", value: ByteCountFormatter.string(fromByteCount: OfflineDownloadStore.softCapBytes, countStyle: .file))
                LabeledContent("Active Downloads", value: "\(activeRecords.count + pausedRecords.count)")
            } footer: {
                Text("Downloads use background transfers from your Jellyfin server, are stored in Application Support, and are excluded from device backup.")
            }

            if downloads.records.isEmpty {
                Section {
                    ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle", description: Text("Downloaded items from this server and user will appear here."))
                }
            }

            if !activeRecords.isEmpty {
                Section("In Progress") {
                    ForEach(activeRecords) { record in
                        DownloadProgressRow(record: record) {
                            Task { await downloads.pause(itemID: record.item.id ?? "") }
                        } delete: {
                            downloads.delete(record, serverID: session.server.id, userID: session.user.id)
                        }
                    }
                }
            }

            if !pausedRecords.isEmpty {
                Section("Paused") {
                    ForEach(pausedRecords) { record in
                        DownloadPausedRow(record: record) {
                            Task { await downloads.resume(itemID: record.item.id ?? "", session: session) }
                        } delete: {
                            downloads.delete(record, serverID: session.server.id, userID: session.user.id)
                        }
                    }
                }
            }

            if !failedRecords.isEmpty {
                Section("Failed") {
                    ForEach(failedRecords) { record in
                        DownloadFailedRow(record: record) {
                            downloads.delete(record, serverID: session.server.id, userID: session.user.id)
                        }
                    }
                }
            }

            if !completeRecords.isEmpty {
                Section("Downloaded Media") {
                    ForEach(completeRecords) { record in
                        DownloadCompleteRow(record: record) {
                            playerItem = ItemRef(item: record.item)
                        } delete: {
                            downloads.delete(record, serverID: session.server.id, userID: session.user.id)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            downloads.delete(completeRecords[index], serverID: session.server.id, userID: session.user.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        .task {
            downloads.load(serverID: session.server.id, userID: session.user.id)
        }
        .playerPresentation(item: $playerItem)
        .downloadErrorAlert(downloads)
    }

    private var activeRecords: [OfflineDownloadRecord] {
        downloads.records.filter { record in
            switch record.status {
            case .queued, .downloading:
                return true
            case .paused, .complete, .failed:
                return false
            }
        }
    }

    private var pausedRecords: [OfflineDownloadRecord] {
        downloads.records.filter { $0.status == .paused }
    }

    private var completeRecords: [OfflineDownloadRecord] {
        downloads.records.filter { $0.status == .complete }
    }

    private var failedRecords: [OfflineDownloadRecord] {
        downloads.records.filter { record in
            if case .failed = record.status {
                return true
            }
            return false
        }
    }
}

private struct DownloadProgressRow: View {
    let record: OfflineDownloadRecord
    let pause: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(record.item.displayTitle)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: pause) {
                    Label("Pause", systemImage: "pause.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Pause \(record.item.displayTitle)")

                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete \(record.item.displayTitle)")
            }

            ProgressView(value: record.progress)
                .accessibilityLabel("Download progress for \(record.item.displayTitle)")
                .accessibilityValue(statusText)
        }
    }

    private var statusText: String {
        if record.requiresTranscodingForDownload, record.progress == 0 {
            return String(localized: "Transcoding for download...", comment: "Download status while server prepares a transcoded file")
        }
        if case .queued = record.status {
            return String(localized: "Queued", comment: "Download queued status label")
        }
        return record.progress.formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct DownloadPausedRow: View {
    let record: OfflineDownloadRecord
    let resume: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(record.item.displayTitle)
                Text("Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: resume) {
                Label("Resume", systemImage: "play.fill")
            }
            .accessibilityLabel("Resume \(record.item.displayTitle)")
            .buttonStyle(.borderless)

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(record.item.displayTitle)")
        }
    }
}

private struct DownloadCompleteRow: View {
    let record: OfflineDownloadRecord
    let play: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(record.item.displayTitle)
                Text(ByteCountFormatter.string(fromByteCount: record.byteCount, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: play) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Play \(record.item.displayTitle)")

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(record.item.displayTitle)")
        }
    }
}

private struct DownloadFailedRow: View {
    let record: OfflineDownloadRecord
    let delete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(record.item.displayTitle)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(record.item.displayTitle)")
        }
    }

    private var message: String {
        if case let .failed(message) = record.status, !message.isEmpty {
            return message
        }
        return String(localized: "Download Failed", comment: "Failed download status label")
    }
}
