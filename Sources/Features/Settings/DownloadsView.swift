import SwiftUI

struct DownloadsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    @AppStorage(OfflineDownloadStore.deleteFinishedDefaultsKey) private var deleteFinished = false
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var pendingDeletion: [OfflineDownloadRecord] = []
    @State private var replacementRecord: OfflineDownloadRecord?
    @State private var confirmingDeletion = false

    private var records: [OfflineDownloadRecord] {
        downloads.records.filter { $0.serverID == session.server.id && $0.userID == session.user.id }
    }

    var body: some View {
        List {
            ProgressTransferView()
            Section {
                LabeledContent("Storage Used", value: ByteCountFormatter.string(fromByteCount: downloads.totalByteCount(serverID: session.server.id, userID: session.user.id), countStyle: .file))
                LabeledContent("Soft Cap", value: ByteCountFormatter.string(fromByteCount: OfflineDownloadStore.softCapBytes, countStyle: .file))
                LabeledContent("Active Downloads", value: "\(records.filter { $0.status.isActive }.count)")
                LabeledContent("Paused Downloads", value: "\(records.filter { $0.status == .paused }.count)")
            } footer: {
                Text("Downloads use system background transfers. Avoid force-quitting Gus while downloading. Saved media stays on this device and is excluded from backup.")
            }
            Section {
                Toggle("Delete After Finishing", isOn: $deleteFinished)
                    .accessibilityIdentifier("Downloads.deleteFinished")
            } footer: {
                Text("Automatically remove finished downloads from this device without asking. Video and audio are removed after playback ends; books are removed when you close the reader at the end. Repeated audio is kept until playback stops. Books opened in other apps are not removed automatically.")
            }
            if records.isEmpty {
                ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle", description: Text("Downloaded items from this server and user will appear here."))
            } else {
                if selecting {
                    Section {
                        Button(selection.count == records.count ? "Deselect All" : "Select All") {
                            selection = selection.count == records.count ? [] : Set(records.map(\.id))
                        }
                        Button("Delete Selected (\(selection.count))", role: .destructive) {
                            requestDeletion(records.filter { selection.contains($0.id) })
                        }
                        .disabled(selection.isEmpty)
                        .accessibilityIdentifier("Downloads.deleteSelected")
                    }
                }
                recordSection("In Progress", records.filter { $0.status.isActive })
                recordSection("Paused", records.filter { $0.status == .paused })
                recordSection("Failed", records.filter {
                    if case .failed = $0.status {
                        return true
                    }; return false
                })
                recordSection("Downloaded Media", records.filter { $0.status.isComplete })
                Section {
                    Button("Delete All Downloads", role: .destructive) { requestDeletion(records) }
                        .accessibilityIdentifier("Downloads.deleteAll")
                }
            }
        }
        .navigationTitle("Downloads")
        .toolbar {
            ToolbarItem {
                Button(selecting ? "Done" : "Select") {
                    selecting.toggle()
                    selection.removeAll()
                }
                .disabled(!selecting && records.isEmpty)
                .accessibilityIdentifier("Downloads.select")
            }
        }
        .task { downloads.load(serverID: session.server.id, userID: session.user.id) }
        .onChange(of: records.map(\.id)) { _, ids in selection.formIntersection(ids) }
        .alert("Delete Downloads?", isPresented: $confirmingDeletion) {
            Button(pendingDeletion.count == 1 ? String(localized: "Delete Download") : String(localized: "Delete \(pendingDeletion.count) Downloads"), role: .destructive) {
                downloads.delete(pendingDeletion, serverID: session.server.id, userID: session.user.id)
                selection.subtract(pendingDeletion.map(\.id))
                pendingDeletion = []
            }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: {
            if pendingDeletion.count == 1, let record = pendingDeletion.first {
                Text("Remove \(record.item.displayTitle) from this device? The server copy will remain available.")
            } else {
                Text("Remove \(pendingDeletion.count) downloads from this device? Server copies will remain available. Active transfers will be canceled.")
            }
        }
        .sheet(item: $replacementRecord) { record in
            MediaReplacementPicker(item: record.item, candidates: []) { candidate in
                await downloads.replaceRemoteReference(record, with: candidate, session: session)
            }
        }
        .downloadErrorAlert(downloads)
    }

    private func requestDeletion(_ records: [OfflineDownloadRecord]) {
        pendingDeletion = records
        confirmingDeletion = !records.isEmpty
    }

    @ViewBuilder
    private func recordSection(_ title: LocalizedStringKey, _ records: [OfflineDownloadRecord]) -> some View {
        if !records.isEmpty {
            Section(title) {
                ForEach(records) { record in
                    HStack {
                        if selecting {
                            Button {
                                if !selection.insert(record.id).inserted {
                                    selection.remove(record.id)
                                }
                            } label: {
                                Image(systemName: selection.contains(record.id) ? "checkmark.circle.fill" : "circle")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Select \(record.item.displayTitle)")
                            .accessibilityValue(selection.contains(record.id) ? "Selected" : "Not Selected")
                        }
                        if record.remoteUnavailable == true {
                            VStack(alignment: .leading) {
                                Text("Unavailable on this server").font(.caption)
                                Button("Choose Replacement") { replacementRecord = record }.buttonStyle(.borderless)
                            }
                        }
                        switch record.status {
                        case .queued, .downloading:
                            DownloadProgressRow(record: record, activity: downloads.activities[record.id] ?? record.activity) {
                                Task { await downloads.pause(itemID: record.item.id ?? "") }
                            } delete: { requestDeletion([record]) }
                        case .paused:
                            DownloadPausedRow(record: record, activity: downloads.activities[record.id] ?? record.activity) {
                                Task { await downloads.resume(itemID: record.item.id ?? "", session: session) }
                            } delete: { requestDeletion([record]) }
                        case .failed:
                            DownloadFailedRow(record: record) { requestDeletion([record]) }
                        case .complete:
                            DownloadCompleteRow(record: record) { requestDeletion([record]) }
                        }
                    }
                }
            }
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
    @Environment(OfflineDownloadStore.self) private var downloads
    let record: OfflineDownloadRecord
    let delete: () -> Void

    var body: some View {
        HStack {
            OfflineArtwork(url: downloads.localArtworkURL(for: record.item, serverID: record.serverID, userID: record.userID), systemImage: "arrow.down.circle")
                .frame(width: 36, height: 48)
            VStack(alignment: .leading) {
                Text(record.item.displayTitle)
                Text(ByteCountFormatter.string(fromByteCount: record.byteCount, countStyle: .file))
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
