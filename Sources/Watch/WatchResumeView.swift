import SwiftUI

/// Quick resume: the top Continue Watching items; tapping one sends it to a chosen
/// remote client (the watch never plays the video itself here — that's the constrained
/// on-watch path in Browse).
struct WatchResumeView: View {
    @Environment(SessionStore.self) private var session

    @State private var items: [MediaItem] = []
    @State private var state: LoadState = .idle
    @State private var targetPickerItem: MediaItem?

    var body: some View {
        LoadingStateView(
            state: state,
            isEmpty: items.isEmpty,
            emptyTitle: "Nothing In Progress",
            emptySymbol: "clock",
            retryAction: { Task { await load() } }
        ) {
            List(items, id: \.id) { item in
                Button {
                    targetPickerItem = item
                } label: {
                    HStack(spacing: 8) {
                        WatchPoster(item: item)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayTitle)
                                .font(.headline)
                                .lineLimit(2)
                            if let progress = item.playbackProgress {
                                ProgressView(value: progress)
                                    .accessibilityLabel(String(localized: "Playback progress for \(item.displayTitle)", comment: "Accessibility label for the resume progress bar; parameter is the item title"))
                                    .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Resume")
        .task {
            await load()
        }
        .sheet(item: $targetPickerItem) { item in
            WatchPlayTargetPicker(item: item, startPositionTicks: PlaybackTime.resumePositionTicks(for: item))
        }
    }

    private func load() async {
        guard state != .loading else { return }
        state = .loading
        do {
            items = try await ContentRatingGate.filter(session.mediaProvider.resumeItems(limit: 3))
            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            state = .failed(gusError.localizedDescription)
        }
    }
}

/// Picks which remote client should play an item, then sends `Sessions/{id}/Playing`.
struct WatchPlayTargetPicker: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    var startPositionTicks: Int?

    @State private var store: RemoteSessionsStore?

    var body: some View {
        NavigationStack {
            Group {
                if let store {
                    LoadingStateView(
                        state: store.state,
                        isEmpty: store.sessions.isEmpty,
                        emptyTitle: "No Players Available",
                        emptySymbol: "play.tv",
                        retryAction: { Task { await store.refresh() } }
                    ) {
                        List(store.sessions) { remote in
                            Button {
                                play(on: remote.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(remote.deviceName)
                                        .font(.headline)
                                    Text(remote.client)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Play On")
        }
        .task {
            if store == nil {
                store = RemoteSessionsStore(session: session)
            }
            await store?.refresh()
        }
    }

    private func play(on sessionID: String) {
        guard let itemID = item.id, let store else { return }
        Task {
            await store.play(itemID: itemID, on: sessionID, startPositionTicks: startPositionTicks)
            dismiss()
        }
    }
}
