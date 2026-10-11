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
                LabeledContent("Active Downloads", value: "\(activeRecords.count)")
                LabeledContent("Paused Downloads", value: "\(pausedRecords.count)")
            } footer: {
                Text("Downloads use system background transfers. Avoid force-quitting Gus while downloading. Saved media stays on this device and is excluded from backup.")
            }

            if downloads.records.isEmpty {
                Section {
                    ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle", description: Text("Downloaded items from this server and user will appear here."))
                }
            }

            if !activeRecords.isEmpty {
                Section("In Progress") {
                    ForEach(activeRecords) { record in
                        DownloadProgressRow(record: record, activity: downloads.activities[record.id] ?? record.activity) {
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
                        DownloadPausedRow(record: record, activity: downloads.activities[record.id] ?? record.activity) {
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
                            playerItem = ItemRef(item: record.item, localOnly: true, serverID: record.serverID, userID: record.userID)
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
    let activity: DownloadActivity?
    let pause: () -> Void
    let delete: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(record.item.displayTitle)
                        Text(statusText(at: context.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: pause) {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(activity?.phase == .saving)
                    .accessibilityLabel("Pause \(record.item.displayTitle)")
                    Button(role: .destructive, action: delete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete \(record.item.displayTitle)")
                }

                if let progress = displayedProgress {
                    ProgressView(value: progress)
                        .accessibilityLabel("Download progress for \(record.item.displayTitle)")
                        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
                } else {
                    ProgressView()
                        .accessibilityLabel("Download progress for \(record.item.displayTitle)")
                        .accessibilityValue(statusText(at: context.date))
                }

                if let activity {
                    Text(DownloadActivityDisplay.bytes(activity))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let rate = activity.bytesPerSecond(at: context.date) {
                        Text(DownloadActivityDisplay.rate(rate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let preparationETA = activity.preparationETA, activity.phase == .waitingForServer {
                        Text("Approximately \(DownloadActivityDisplay.duration(preparationETA)) of server preparation remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let remaining = activity.estimatedTimeRemaining(at: context.date) {
                        Text("Approximately \(DownloadActivityDisplay.duration(remaining)) remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Time remaining unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var displayedProgress: Double? {
        if let activity {
            if let preparation = activity.preparationProgress,
               activity.phase == .waitingForServer
            {
                return min(max(preparation, 0), 1)
            }
            return activity.phase == .downloading ? activity.progress : nil
        }
        return record.progress > 0 ? record.progress : nil
    }

    private func statusText(at date: Date) -> String {
        guard let activity else {
            return record.status == .queued ? String(localized: "Queued") : String(localized: "Downloading")
        }
        switch activity.phase {
        case .resolving:
            return String(localized: "Finding download source")
        case .queued:
            return String(localized: "Queued")
        case .waitingForServer:
            let elapsed = DownloadActivityDisplay.duration(date.timeIntervalSince(activity.updatedAt))
            if let preparation = activity.preparationProgress {
                let percent = preparation.formatted(.percent.precision(.fractionLength(0)))
                return String(localized: "Server preparation: \(percent)")
            }
            return String(localized: "Waiting for server · \(elapsed)")
        case .downloading:
            if activity.isStalled(at: date) {
                return String(localized: "Waiting for more data")
            }
            if let progress = activity.progress {
                let percent = progress.formatted(.percent.precision(.fractionLength(0)))
                return String(localized: "Downloading · \(percent)")
            }
            return String(localized: "Downloading · Total size unknown")
        case .waitingForConnectivity:
            let elapsed = DownloadActivityDisplay.duration(date.timeIntervalSince(activity.updatedAt))
            return String(localized: "Waiting for connection · \(elapsed)")
        case .paused:
            return String(localized: "Paused")
        case .saving:
            return String(localized: "Saving download")
        case .complete:
            return String(localized: "Downloaded")
        case .failed:
            return String(localized: "Download Failed")
        }
    }
}

private enum DownloadActivityDisplay {
    static func bytes(_ activity: DownloadActivity) -> String {
        let received = ByteCountFormatter.string(fromByteCount: activity.receivedBytes, countStyle: .file)
        if let expected = activity.expectedBytes {
            let total = ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)
            return String(localized: "\(received) of \(total)")
        }
        return String(localized: "\(received) received · Total size unknown")
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let amount = ByteCountFormatter.string(fromByteCount: Int64(min(bytesPerSecond, Double(Int64.max - 1024))), countStyle: .file)
        return String(localized: "\(amount)/s")
    }

    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }
}

private struct DownloadPausedRow: View {
    let record: OfflineDownloadRecord
    let activity: DownloadActivity?
    let resume: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(record.item.displayTitle)
                Text("Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let activity {
                    Text(DownloadActivityDisplay.bytes(activity))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
