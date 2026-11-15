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
            retryAction: { Task { await load() } },
            preservesContent: true
        ) {
            List(items, id: \.id) { item in
                Button {
                    targetPickerItem = item
                } label: {
                    HStack(spacing: 8) {
                        WatchPoster(item: item)
                            .overlay(alignment: .bottom) {
                                if let progress = item.playbackProgress, progress > 0, progress < 1 {
                                    ProgressView(value: progress).tint(.white)
                                        .padding(3).background(.black.opacity(0.65))
                                        .accessibilityLabel("Playback progress")
                                        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
                                }
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayTitle)
                                .font(.headline)
                                .lineLimit(2)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.mediaAccessibility.label)
                    .accessibilityValue(item.mediaAccessibility.value)
                }
            }
        }
        .navigationTitle("Resume")
        .task {
            await load()
        }
        .sheet(item: $targetPickerItem) { item in
            WatchPlayTargetPicker(request: PlaybackRequest(item: item, startPositionTicks: PlaybackTime.resumePositionTicks(for: item)))
        }
    }

    private func load() async {
        guard state != .loading else { return }
        state = .loading
        do {
            let loadedItems = try await session.mediaProvider.resumeItems(limit: 3)
            try Task.checkCancellation()
            items = ContentRatingGate.filter(loadedItems)
            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { state = .idle; return }
            state = .failed(gusError.localizedDescription)
        }
    }
}

/// Picks which remote client should play an item, then sends `Sessions/{id}/Playing`.
struct WatchPlayTargetPicker: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let request: PlaybackRequest
    private var item: MediaItem {
        request.item
    }

    @State private var store: RemoteSessionsStore?
    @State private var commandError: String?
    @State private var commandTask: Task<Void, Never>?
    @State private var acceptedNotice: String?

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
                                    if store.pendingSessionIDs.contains(remote.id) {
                                        ProgressView("Sending Request")
                                    }
                                }
                            }
                            .disabled(!store.pendingSessionIDs.isEmpty || !remote.canPlay(item))
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Play On")
            .safeAreaInset(edge: .bottom) {
                if let commandError {
                    Label(commandError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .padding()
                }
            }
        }
        .task {
            if store == nil {
                store = RemoteSessionsStore(session: session)
            }
            await store?.refresh()
        }
        .alert("Playback Requested", isPresented: Binding(get: { acceptedNotice != nil }, set: {
            if !$0 {
                dismiss()
            }
        })) {
            Button("Done") { dismiss() }
        } message: {
            Text(acceptedNotice ?? "")
        }
        .onDisappear {
            commandTask?.cancel()
            store?.stopLiveUpdates()
        }
    }

    private func play(on sessionID: String) {
        guard item.id != nil, let store else { return }
        commandError = nil
        commandTask = Task {
            do {
                _ = try await store.play(request, on: sessionID)
                guard !Task.isCancelled else { return }
                if let notice = store.commandNotices[sessionID] {
                    acceptedNotice = notice
                } else {
                    dismiss()
                }
            } catch {
                guard !Task.isCancelled, !GusError(from: error).isCancellation else { return }
                commandError = error.localizedDescription
            }
        }
    }
}
