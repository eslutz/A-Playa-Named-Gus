import SwiftUI

/// Actions for one item on the watch. Audio plays on the watch (and can download for
/// offline); video offers the constrained on-watch player plus remote playback; books
/// point back to iPhone/iPad per the brief's audio-first scope.
struct WatchItemActionsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    let item: MediaItem
    @State private var request: PlaybackRequest
    @State private var pendingSourceID: String?
    @State private var confirmingSourceChange = false
    @State private var metadataError: String?

    init(item: MediaItem) {
        self.item = item
        _request = State(initialValue: PlaybackRequest(item: item))
    }

    @State private var isAudioPlayerPresented = false
    @State private var isVideoPlayerPresented = false
    @State private var isTargetPickerPresented = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    WatchPoster(item: item)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayTitle)
                            .font(.headline)
                            .lineLimit(3)
                        if let runtime = item.runtimeText {
                            Text(runtime)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let metadataError {
                Section {
                    Text(metadataError)
                    Button("Reload Media") { Task { await loadMetadata() } }
                }
            }
            if !request.item.mediaSources.isEmpty, item.type != .book {
                Section("Playback Choices") { playbackChoices }
            }
            Section {
                if item.isAudioPlayable {
                    Button {
                        isAudioPlayerPresented = true
                    } label: {
                        Label("Play on Watch", systemImage: "applewatch")
                    }
                    downloadRow
                } else if item.type == .book {
                    Text("Read this book in A Playa Named Gus on iPhone or iPad.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        isTargetPickerPresented = true
                    } label: {
                        Label("Play On…", systemImage: "play.tv")
                    }
                    Button {
                        isVideoPlayerPresented = true
                    } label: {
                        Label("Play on Watch", systemImage: "applewatch")
                    }
                }
            }
        }
        .navigationTitle(item.displayTitle)
        .sheet(isPresented: $isAudioPlayerPresented) {
            WatchAudioPlayerView(tracks: [request.item], startIndex: 0, request: request)
        }
        .sheet(isPresented: $isVideoPlayerPresented) {
            WatchVideoPlayerView(request: request)
        }
        .sheet(isPresented: $isTargetPickerPresented) {
            WatchPlayTargetPicker(request: request)
        }
        .task {
            downloads.load(serverID: session.server.id, userID: session.user.id)
            await loadMetadata()
        }
        .confirmationDialog("Change Version?", isPresented: $confirmingSourceChange) {
            Button("Start Over") { applySource(pendingSourceID, fromBeginning: true) }
            Button("Resume at Timestamp") { applySource(pendingSourceID, fromBeginning: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Different versions may have different timelines.")
        }
    }

    private var selectedSource: MediaSource? {
        request.streamSelection.mediaSourceID.flatMap { id in request.item.mediaSources.first { $0.id == id } } ?? request.item.mediaSources.first
    }

    @ViewBuilder private var playbackChoices: some View {
        if request.item.mediaSources.count > 1 {
            Picker("Version", selection: Binding(get: { request.streamSelection.mediaSourceID }, set: chooseSource)) {
                Text("Automatic").tag(nil as String?)
                ForEach(Array(request.item.mediaSources.enumerated()), id: \.offset) { index, source in
                    if let id = source.id {
                        Text(source.name ?? String(localized: "Version \(index + 1)")).tag(id as String?)
                    }
                }
            }
        }
        if let source = selectedSource {
            let audio = source.mediaStreams.filter { $0.type == .audio && $0.index != nil }
            if !audio.isEmpty {
                Picker("Audio", selection: Binding(get: { request.selection(in: source).audioStreamIndex }, set: { selectAudio($0, source: source) })) {
                    Text("Automatic").tag(nil as Int?)
                    ForEach(audio, id: \.index) { stream in
                        Text(stream.displayTitle ?? stream.title ?? stream.language ?? String(localized: "Audio")).tag(stream.index)
                    }
                }
            }
            let subtitles = source.mediaStreams.filter { $0.type == .subtitle && $0.index != nil }
            if !subtitles.isEmpty {
                Picker("Subtitles", selection: Binding(get: { request.selection(in: source).subtitleStreamIndex }, set: { selectSubtitle($0, source: source) })) {
                    Text("Automatic").tag(nil as Int?)
                    Text("Off").tag(-1 as Int?)
                    ForEach(subtitles, id: \.index) { stream in
                        Text(stream.displayTitle ?? stream.title ?? stream.language ?? String(localized: "Subtitles")).tag(stream.index)
                    }
                }
            }
        }
    }

    private func chooseSource(_ id: String?) {
        let current = selectedSource?.id
        let next = id ?? request.item.mediaSources.first?.id
        guard current != next else { return }
        pendingSourceID = id
        if (request.requestedStartTicks ?? PlaybackTime.resumePositionTicks(for: request.item) ?? 0) > 0 {
            confirmingSourceChange = true
        } else {
            applySource(id, fromBeginning: true)
        }
    }

    private func applySource(_ id: String?, fromBeginning: Bool) {
        let ticks = request.requestedStartTicks ?? PlaybackTime.resumePositionTicks(for: request.item)
        request.streamSelection.mediaSourceID = id
        request.streamSelection.audioStreamIndex = nil
        request.streamSelection.subtitleStreamIndex = request.subtitleIntent == .off ? -1 : nil
        request.start = fromBeginning ? .fromBeginning : .automatic
        request.startPositionTicks = fromBeginning ? 0 : ticks
    }

    private func selectAudio(_ index: Int?, source: MediaSource) {
        request.streamSelection.audioStreamIndex = index
        request.audioTrack = source.mediaStreams.first { $0.type == .audio && $0.index == index }
        PlaybackTrackMemory.shared.remember(item: request.item, source: source, selection: request.selection(in: source), scope: session.references.scope, audioExplicit: true, subtitleExplicit: false)
    }

    private func selectSubtitle(_ index: Int?, source: MediaSource) {
        request.streamSelection.subtitleStreamIndex = index
        request.subtitleTrack = source.mediaStreams.first { $0.type == .subtitle && $0.index == index }
        request.subtitleIntent = index == nil ? .automatic : index == -1 ? .off : .explicit
        PlaybackTrackMemory.shared.remember(item: request.item, source: source, selection: request.selection(in: source), scope: session.references.scope, audioExplicit: false, subtitleExplicit: true)
    }

    private func loadMetadata() async {
        do {
            let current = try await session.references.currentItem(item)
            guard session.isActive, !Task.isCancelled else { return }
            request.item = current
            metadataError = nil
        } catch {
            guard session.isActive, !Task.isCancelled else { return }
            metadataError = GusError(from: error).localizedDescription
        }
    }

    /// Offline audio per the brief: audio-only, conservative budget, clear states.
    @ViewBuilder
    private var downloadRow: some View {
        if let failure = downloads.loadErrorMessage {
            Text(failure).font(.footnote).foregroundStyle(.secondary)
            Button("Try Again") { downloads.load(serverID: session.server.id, userID: session.user.id) }
        } else if let record = downloads.record(for: request.item, serverID: session.server.id, userID: session.user.id, mediaSourceID: request.streamSelection.mediaSourceID) {
            switch record.status {
            case .complete:
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            case .queued, .downloading:
                Label("Downloading", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            case .paused, .failed:
                retryDownloadButton
            }
        } else if OfflineDownloadEligibility.canDownload(item) {
            retryDownloadButton
        }
        if let failure = downloads.errorMessage {
            Text(failure).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var retryDownloadButton: some View {
        Button {
            Task { await downloads.download(request, session: session) }
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }
    }
}
