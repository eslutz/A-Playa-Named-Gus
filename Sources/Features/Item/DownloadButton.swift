import SwiftUI

/// Download state button for an item: queued, in-progress, paused, complete, and retry states.
/// Pass `iconOnly: true` when embedding as a hero accessory; otherwise shows a full label.
struct DownloadButton: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads

    let item: MediaItem
    var iconOnly = false

    var body: some View {
        if let record = downloads.record(for: item, serverID: session.server.id, userID: session.user.id) {
            switch record.status {
            case .complete where downloads.localFileURL(for: item, serverID: session.server.id, userID: session.user.id) != nil:
                statusLabel("Downloaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Downloaded")
                    .accessibilityValue(record.downloadedAt.formatted(date: .abbreviated, time: .shortened))
            case .queued:
                statusLabel("Queued", systemImage: "clock", indeterminate: true)
                    .foregroundStyle(.secondary)
                    .overlay {
                        if iconOnly {
                            DownloadProgressRing(activity: downloads.activities[record.id] ?? record.activity)
                        }
                    }
            case .downloading:
                let activity = downloads.activities[record.id] ?? record.activity
                statusLabel(activityLabel(for: record), systemImage: "arrow.down.circle", indeterminate: activity?.phase != .downloading || activity?.progress == nil)
                    .foregroundStyle(.secondary)
                    .overlay {
                        if iconOnly {
                            DownloadProgressRing(activity: downloads.activities[record.id] ?? record.activity)
                        }
                    }
                    .accessibilityValue(progressValue(for: record))
            case .paused:
                Button {
                    Task { await downloads.resume(itemID: item.id ?? "", session: session) }
                } label: {
                    downloadLabel("Resume", systemImage: "play.fill")
                }
                .gusGlassButtonStyle()
                .controlSize(iconOnly ? .regular : .large)
                .frame(minWidth: 44, minHeight: 44)
                .visionHoverEffect(Capsule())
            case .failed, .complete:
                downloadAction(itemID: item.id)
            }
        } else if session.mediaProvider.capabilities.supportsDownloads,
                  OfflineDownloadEligibility.canDownload(item),
                  let itemID = item.id
        {
            downloadAction(itemID: itemID)
        }
    }

    private func progressValue(for record: OfflineDownloadRecord) -> String {
        guard let progress = (downloads.activities[record.id] ?? record.activity)?.progress else { return String(localized: "In progress") }
        return progress.formatted(.percent.precision(.fractionLength(0)))
    }

    private func activityLabel(for record: OfflineDownloadRecord) -> LocalizedStringKey {
        switch (downloads.activities[record.id] ?? record.activity)?.phase {
        case .resolving: return "Finding download source"
        case .queued: return "Queued"
        case .waitingForServer: return "Waiting for server"
        case .waitingForConnectivity: return "Waiting for connection"
        case .saving: return "Saving download"
        default: return "Downloading"
        }
    }

    private func downloadAction(itemID: String?) -> some View {
        Button {
            Task { await downloads.download(item, session: session) }
        } label: {
            if let itemID, downloads.activeItemIDs.contains(itemID) {
                downloadLabel("Downloading", systemImage: "arrow.down.circle")
            } else {
                downloadLabel("Download", systemImage: "arrow.down.circle")
            }
        }
        .disabled(itemID.map { downloads.activeItemIDs.contains($0) } ?? true)
        .gusGlassButtonStyle()
        .controlSize(iconOnly ? .regular : .large)
        .frame(minWidth: 44, minHeight: 44)
        .visionHoverEffect(Capsule())
    }

    @ViewBuilder
    private func statusLabel(_ title: LocalizedStringKey, systemImage: String, indeterminate: Bool = false) -> some View {
        if iconOnly {
            Button {} label: {
                if indeterminate {
                    ProgressView().controlSize(.regular)
                        .frame(maxWidth: .infinity, minHeight: DetailActionMetrics.minimumLabelHeight)
                } else {
                    downloadLabel(title, systemImage: systemImage)
                }
            }
            .accessibilityLabel(Text(title))
            .gusGlassButtonStyle()
            .controlSize(.regular)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(true)
        } else {
            downloadLabel(title, systemImage: systemImage)
        }
    }

    /// Compact icon form when used as a hero accessory; full label elsewhere. The title
    /// stays attached for VoiceOver either way.
    @ViewBuilder
    private func downloadLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        if iconOnly {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(maxWidth: .infinity, minHeight: DetailActionMetrics.minimumLabelHeight)
        } else {
            Label(title, systemImage: systemImage)
        }
    }
}

/// A system progress indicator for unknown work, and a byte-backed ring for transfer.
private struct DownloadProgressRing: View {
    let activity: DownloadActivity?
    var body: some View {
        Group {
            if let activity, activity.phase == .downloading, let progress = activity.progress {
                Circle().stroke(.quaternary, lineWidth: 3)
                    .overlay {
                        Circle().trim(from: 0, to: progress)
                            .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
            } else {
                Circle().stroke(.quaternary, lineWidth: 3)
            }
        }
        .padding(2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
