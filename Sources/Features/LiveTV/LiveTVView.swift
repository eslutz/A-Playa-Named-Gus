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
            } else if store?.state == .idle {
                await store?.load()
            }
        }
        .playerPresentation(item: $playerItem)
        .alert(
            "Couldn't Cancel Recording",
            isPresented: Binding(
                get: { store?.actionErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        store?.actionErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                store?.actionErrorMessage = nil
            }
        } message: {
            Text(store?.actionErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private func content(_ store: LiveTVStore) -> some View {
        if store.state == .loaded, store.availability == .notConfigured {
            ContentUnavailableView {
                Label("Live TV Not Configured", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text("This Jellyfin server has no Live TV tuner or guide configured.")
            } actions: {
                Button("Refresh") { Task { await store.load() } }
            }
        } else if store.state == .loaded, store.availability == .restricted {
            ContentUnavailableView("Live TV Restricted", systemImage: "lock", description: Text("Your account does not have permission to use Live TV."))
        } else {
            LoadingStateView(
                state: store.state,
                isEmpty: false,
                emptyTitle: String(localized: "No Live TV Content", comment: "Live TV empty-state title when there are no channels or recordings"),
                emptySymbol: "antenna.radiowaves.left.and.right",
                retryAction: { Task { await store.load() } },
                preservesContent: store.availability == .enabled && (!store.channels.isEmpty || !store.recordings.isEmpty || !store.timers.isEmpty)
            ) {
                VStack(spacing: 0) {
                    if let message = store.actionStatusMessage {
                        Text(message).font(.callout).foregroundStyle(.secondary).padding()
                    }
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

    private func sectionContent(_ store: LiveTVStore) -> some View {
        LoadingStateView(state: store.sectionState(section), isEmpty: store.isEmpty(section), emptyTitle: section.emptyTitle, emptySymbol: "antenna.radiowaves.left.and.right", retryAction: { Task { await store.reload(section) } }, preservesContent: true) {
            switch section {
            case .channels: channelList(store)
            case .recordings: recordingList(store)
            case .scheduled: timerList(store)
            }
        }
        .refreshable { await store.reload(section) }
        .task(id: section) {
            if store.sectionState(section) == .idle {
                await store.reload(section)
            }
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
                        placeholderSymbol: "tv",
                        fallbackURLs: session.mediaProvider.artworkURLs(for: channel, request: .init(role: .square, maxWidth: 120))
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(channel.mediaAccessibility.label)
            .accessibilityValue(channel.mediaAccessibility.value)
        }
        .listStyle(.plain)
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(recording.mediaAccessibility.label)
                .accessibilityValue(recording.mediaAccessibility.value)
                .mediaItemContextMenu(item: recording)
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
                    .disabled(!store.canCancelTimer(timer.id))
                }
            }
            .listStyle(.plain)
        }
    }
}

enum LiveTVSection: String, CaseIterable, Identifiable {
    case channels
    case recordings
    case scheduled

    var id: String {
        rawValue
    }

    var emptyTitle: String {
        switch self {
        case .channels: String(localized: "No Channels")
        case .recordings: String(localized: "No Recordings")
        case .scheduled: String(localized: "No Scheduled Recordings")
        }
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
    private(set) var availability: LiveTVAvailability?
    private(set) var channels: [MediaItem] = []
    private(set) var recordings: [MediaItem] = []
    private(set) var timers: [LiveTVTimer] = []
    /// Row-level action failures (e.g. canceling a recording) — surfaced as an alert,
    /// never by replacing the loaded screen.
    var actionErrorMessage: String?
    private(set) var actionStatusMessage: String?
    private(set) var cancellationOutcomes: [String: ActionOutcome] = [:]

    private let session: SessionStore
    private var generation = 0
    private var sectionGenerations: [LiveTVSection: Int] = [:]
    private var sectionStates: [LiveTVSection: LoadState] = [:]
    private(set) var cancelingTimerIDs: Set<String> = []

    init(session: SessionStore) {
        self.session = session
    }

    func sectionState(_ section: LiveTVSection) -> LoadState {
        sectionStates[section] ?? .idle
    }

    func isEmpty(_ section: LiveTVSection) -> Bool {
        switch section {
        case .channels: channels.isEmpty
        case .recordings: recordings.isEmpty
        case .scheduled: timers.isEmpty
        }
    }

    func load() async {
        guard state != .loading, session.isActive else { return }
        generation += 1
        let request = generation
        state = .loading
        do {
            let availability = try await session.mediaProvider.liveTVAvailability()
            try Task.checkCancellation()
            guard request == generation, session.isActive else { return }
            self.availability = availability
            state = .loaded
            guard availability == .enabled else { return }
            async let channels: Void = reload(.channels)
            async let recordings: Void = reload(.recordings)
            async let timers: Void = reload(.scheduled)
            _ = await(channels, recordings, timers)
        } catch {
            guard request == generation, session.isActive else { return }
            let failure = GusError(from: error)
            state = failure.isCancellation ? .idle : .failed(failure.localizedDescription)
            failure.handleIfUnauthorized(session: session)
        }
    }

    func reload(_ section: LiveTVSection, superseding: Bool = false) async {
        guard session.isActive, superseding || sectionState(section) != .loading else { return }
        let request = (sectionGenerations[section] ?? 0) + 1
        sectionGenerations[section] = request
        sectionStates[section] = .loading
        do {
            switch section {
            case .channels:
                let items = try await MediaPageLoader.collect { offset, size in
                    try await self.session.mediaProvider.liveTVChannels(startIndex: offset, limit: size)
                }
                try Task.checkCancellation()
                guard sectionGenerations[section] == request, session.isActive else { return }
                channels = ContentRatingGate.filter(items)
            case .recordings:
                let items = try await MediaPageLoader.collect { offset, size in
                    try await self.session.mediaProvider.liveTVRecordingsPage(startIndex: offset, limit: size)
                }
                try Task.checkCancellation()
                guard sectionGenerations[section] == request, session.isActive else { return }
                recordings = ContentRatingGate.filter(items)
            case .scheduled:
                let items = try await session.mediaProvider.liveTVTimers()
                try Task.checkCancellation()
                guard sectionGenerations[section] == request, session.isActive else { return }
                timers = items
                for (id, outcome) in Array(cancellationOutcomes) where outcome == .accepted || outcome == .uncertain {
                    cancellationOutcomes[id] = items.contains(where: { $0.id == id }) ? nil : .confirmed
                }
            }
            sectionStates[section] = .loaded
        } catch {
            guard sectionGenerations[section] == request, session.isActive else { return }
            let failure = GusError(from: error)
            sectionStates[section] = failure.isCancellation ? (isEmpty(section) ? .idle : .loaded) : .failed(failure.localizedDescription)
            failure.handleIfUnauthorized(session: session)
        }
    }

    func canCancelTimer(_ id: String) -> Bool {
        !cancelingTimerIDs.contains(id) && cancellationOutcomes[id] != .accepted && cancellationOutcomes[id] != .uncertain
    }

    func cancelTimer(id: String) async {
        guard session.isActive, canCancelTimer(id), cancelingTimerIDs.insert(id).inserted else { return }
        cancellationOutcomes[id] = .pending
        actionStatusMessage = nil
        actionErrorMessage = nil
        defer { cancelingTimerIDs.remove(id) }
        do {
            try await session.mediaProvider.cancelLiveTVTimer(id: id)
            guard session.isActive else { return }
            cancellationOutcomes[id] = .accepted
            actionStatusMessage = String(localized: "Recording cancellation accepted. Refresh to confirm.")
            await reload(.scheduled, superseding: true)
            if cancellationOutcomes[id] == .confirmed {
                actionStatusMessage = String(localized: "Recording canceled.")
            }
        } catch {
            let failure = GusError(from: error)
            guard session.isActive else { return }
            if failure.isCancellation {
                cancellationOutcomes[id] = nil; return
            }
            failure.handleIfUnauthorized(session: session)
            switch failure {
            case .timeout, .offline, .network:
                cancellationOutcomes[id] = .uncertain
                actionStatusMessage = String(localized: "The cancellation may have been accepted. Refresh before trying again.")
            default:
                cancellationOutcomes[id] = .failed(failure)
                actionErrorMessage = failure.localizedDescription
            }
        }
    }
}
