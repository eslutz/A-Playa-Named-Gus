import SwiftUI

/// Live TV destination for a `livetv` library: channel list with now-playing program
/// info, recordings, and scheduled-recording management, with a clear unsupported state
/// when the server has no tuner/DVR configured.
struct LiveTVView: View {
    @Environment(SessionStore.self) private var session
    @State private var store: LiveTVStore?
    @State private var playerItem: ItemRef?
    @State private var section: LiveTVSection = .channels

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Live TV")
        .task {
            if store == nil {
                let store = LiveTVStore(session: session)
                self.store = store
                await store.load()
            }
        }
        .playerPresentation(item: $playerItem)
    }

    @ViewBuilder
    private func content(_ store: LiveTVStore) -> some View {
        if store.state == .loaded, !store.isLiveTVEnabled {
            ContentUnavailableView {
                Label("Live TV Not Configured", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text("This Jellyfin server has no Live TV tuner or guide configured.")
            }
        } else {
            LoadingStateView(
                state: store.state,
                isEmpty: store.channels.isEmpty && store.recordings.isEmpty && store.timers.isEmpty,
                emptyTitle: "No Live TV Content",
                emptySymbol: "antenna.radiowaves.left.and.right"
            ) {
                VStack(spacing: 0) {
                    Picker("Section", selection: $section) {
                        ForEach(LiveTVSection.allCases) { section in
                            Text(section.title).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    sectionContent(store)
                }
                .frame(maxWidth: PageContentMetrics.maxWidth)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func sectionContent(_ store: LiveTVStore) -> some View {
        switch section {
        case .channels:
            channelList(store)
        case .recordings:
            recordingList(store)
        case .scheduled:
            timerList(store)
        }
    }

    private func channelList(_ store: LiveTVStore) -> some View {
        List(store.channels, id: \.id) { channel in
            Button {
                playerItem = ItemRef(item: channel)
            } label: {
                HStack(spacing: 14) {
                    AsyncPoster(
                        url: session.mediaProvider.primaryImageURL(for: channel, maxWidth: 120),
                        contentMode: .fit,
                        placeholderSymbol: "tv"
                    )
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.displayTitle)
                            .font(.headline)
                        if let program = channel.currentProgramName {
                            Text(program)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(channelAccessibilityLabel(channel))
        }
        .listStyle(.plain)
    }

    private func channelAccessibilityLabel(_ channel: MediaItem) -> Text {
        if let program = channel.currentProgramName {
            Text("\(channel.displayTitle), now playing \(program)")
        } else {
            Text(channel.displayTitle)
        }
    }

    @ViewBuilder
    private func recordingList(_ store: LiveTVStore) -> some View {
        if store.recordings.isEmpty {
            ContentUnavailableView {
                Label("No Recordings", systemImage: "record.circle")
            }
        } else {
            List(store.recordings, id: \.id) { recording in
                NavigationLink(value: ItemRef(item: recording)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.displayTitle)
                            .font(.headline)
                        if let runtime = recording.runtimeText {
                            Text(runtime)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func timerList(_ store: LiveTVStore) -> some View {
        if store.timers.isEmpty {
            ContentUnavailableView {
                Label("No Scheduled Recordings", systemImage: "calendar.badge.clock")
            }
        } else {
            List(store.timers) { timer in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timer.name)
                            .font(.headline)
                        HStack(spacing: 6) {
                            if let channelName = timer.channelName {
                                Text(channelName)
                            }
                            if let start = timer.startDate {
                                Text(start.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        Task { await store.cancelTimer(id: timer.id) }
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Cancel recording \(timer.name)")
                }
            }
            .listStyle(.plain)
        }
    }
}

private enum LiveTVSection: String, CaseIterable, Identifiable {
    case channels
    case recordings
    case scheduled

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .channels:
            return String(localized: "Channels", comment: "Live TV section")
        case .recordings:
            return String(localized: "Recordings", comment: "Live TV section")
        case .scheduled:
            return String(localized: "Scheduled", comment: "Live TV section")
        }
    }
}

/// Loads channels, recordings, and timers; exposes the server's Live TV availability.
@MainActor
@Observable
final class LiveTVStore {
    private(set) var state: LoadState = .idle
    private(set) var isLiveTVEnabled = true
    private(set) var channels: [MediaItem] = []
    private(set) var recordings: [MediaItem] = []
    private(set) var timers: [LiveTVTimer] = []

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading

        isLiveTVEnabled = await session.mediaProvider.liveTVIsEnabled()
        guard isLiveTVEnabled else {
            state = .loaded
            return
        }

        do {
            async let channelsLoad = session.mediaProvider.liveTVChannels(startIndex: 0, limit: 200)
            async let recordingsLoad = session.mediaProvider.liveTVRecordings(limit: 100)
            async let timersLoad = session.mediaProvider.liveTVTimers()
            let (channelPage, loadedRecordings, loadedTimers) = try await(channelsLoad, recordingsLoad, timersLoad)
            channels = channelPage.items
            recordings = loadedRecordings
            timers = loadedTimers
            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            state = .failed(gusError.localizedDescription)
        }
    }

    func cancelTimer(id: String) async {
        do {
            try await session.mediaProvider.cancelLiveTVTimer(id: id)
            timers.removeAll { $0.id == id }
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            state = .failed(gusError.localizedDescription)
        }
    }
}
