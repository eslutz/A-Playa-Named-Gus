import SwiftUI

/// Now-playing surface for songs and audiobooks: artwork, scrubber, queue transport,
/// shuffle/repeat, and — for audiobooks — playback speed and chapter navigation.
struct AudioPlayerView: View {
    @Environment(AudioPlaybackCoordinator.self) private var audio
    @Environment(SessionStore.self) private var session
    let store: AudioPlayerStore

    @State private var showingQueue = false
    @State private var pendingSource: MediaSource?
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif

    private var usesLeadingTitle: Bool {
        #if os(iOS)
            widthClass == .compact || DeviceIdentity.usesIPadPresentation
        #elseif os(tvOS)
            true
        #else
            false
        #endif
    }

    private var usesInlineTransport: Bool {
        #if os(iOS)
            widthClass == .compact
        #else
            false
        #endif
    }

    @State private var scrubTime: Double = 0
    @State private var isScrubbing = false

    private var track: MediaItem? {
        store.currentTrack
    }

    var body: some View {
        LoadingStateView(state: !store.hasPreparedContent && (store.isCollectingShuffle || store.queueErrorMessage != nil) ? .loaded : store.state, retryAction: { audio.retry() }, preservesContent: store.hasPreparedContent) {
            if !store.hasPreparedContent, store.isCollectingShuffle || store.queueErrorMessage != nil {
                VStack(spacing: 16) {
                    if store.isCollectingShuffle {
                        ProgressView("Preparing Shuffle")
                        Text("\(store.queue.tracks.count) tracks loaded")
                        Button("Cancel", role: .cancel) { audio.stop() }
                    } else if let message = store.queueErrorMessage {
                        Text(message).foregroundStyle(.secondary)
                        Button("Try Again") { audio.retry() }
                        Button("Close") { audio.stop() }
                    }
                }.padding()
            } else {
                #if os(tvOS)
                    if store.state == .loaded, let player = store.nativePlayer {
                        TVAudioPlayerSurface(player: player, store: store, onClose: { audio.close() }, onStop: { audio.stop() }, artworkURL: track.flatMap { session.mediaProvider.primaryImageURL(for: $0, context: .nowPlayingArtwork) })
                    } else {
                        VStack { artwork; titleBlock }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                #else
                    AdaptiveAudioLayout { artwork } controls: { controls.disabled(store.state != .loaded) }
                #endif
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if store.state == .loaded, store.mediaSourceOptions.count > 1 || store.audioOptions.count > 1 {
                Menu("Playback Options", systemImage: "slider.horizontal.3") {
                    if store.mediaSourceOptions.count > 1 {
                        Menu("Version") {
                            ForEach(Array(store.mediaSourceOptions.enumerated()), id: \.element.id) { offset, source in
                                Button(source.name ?? String(localized: "Version \(offset + 1)")) { pendingSource = source }
                                    .disabled(source.id == store.selectedMediaSourceID)
                            }
                        }
                    }
                    if store.audioOptions.count > 1 {
                        Picker("Audio", selection: Binding(get: { store.audioMenuSelection }, set: { selection in
                            guard let selection else { return }
                            switch selection {
                            case .automatic: Task { await store.selectAudioStream(index: nil) }
                            case let .stream(index): Task { await store.selectAudioStream(index: index) }
                            case .off: break
                            }
                        })) {
                            if store.audioMenuSelection == nil {
                                Text("Unavailable").tag(nil as PlaybackTrackMenuSelection?).disabled(true)
                            }
                            Text("Automatic").tag(PlaybackTrackMenuSelection.automatic as PlaybackTrackMenuSelection?)
                            ForEach(store.audioOptions) { option in
                                Text(option.title).tag(PlaybackTrackMenuSelection.stream(option.id) as PlaybackTrackMenuSelection?)
                            }
                        }.pickerStyle(.menu)
                    }
                }.buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding()
                    .background(.regularMaterial)
            }
        }
        .confirmationDialog("Switch Version", isPresented: Binding(get: { pendingSource != nil }, set: {
            if !$0 {
                pendingSource = nil
            }
        }), titleVisibility: .visible) {
            if let source = pendingSource, let id = source.id {
                Button("Start Over") { pendingSource = nil; Task { await store.selectMediaSource(id: id, fromBeginning: true) } }
                Button("Resume at \(PlaybackTime.accessibilityDuration(seconds: store.currentTime))") { pendingSource = nil; Task { await store.selectMediaSource(id: id, fromBeginning: false) } }
                    .disabled(source.runTimeTicks.map { $0 > 0 && PlaybackTime.ticks(fromSeconds: store.currentTime) >= $0 } ?? false)
                Button("Cancel", role: .cancel) { pendingSource = nil }
            }
        } message: { Text("Choose where playback should begin in this version. Versions may have different timelines.") }
        .toolbar {
            #if os(tvOS)
                ToolbarItem { Button { showingQueue = true } label: { GusToolbarLabel("Queue", systemImage: "list.bullet") }.accessibilityLabel("Queue").gusTVToolbarIcon() }
            #endif
        }
        .gusTVTask(isPresented: $showingQueue) {
            NavigationStack {
                List {
                    ForEach(store.queue.order, id: \.self) { index in
                        let queuedTrack = store.queue.tracks[index]
                        Button {
                            if let id = queuedTrack.id {
                                Task { await store.select(trackID: id) }
                            }
                        } label: {
                            HStack {
                                Text(queuedTrack.displayTitle)
                                Spacer()
                                if store.queue.order.indices.contains(store.queue.position), index == store.queue.order[store.queue.position] {
                                    Image(systemName: "speaker.wave.2.fill").accessibilityLabel("Now Playing")
                                }
                            }
                        }
                    }
                    if store.isCollectingShuffle {
                        ProgressView("Preparing Shuffle")
                        Text("\(store.queue.tracks.count) tracks loaded")
                        Button("Cancel") { store.cancelShuffleCollection() }
                    } else {
                        if store.isLoadingQueue {
                            ProgressView("Loading Queue")
                        }
                        if let message = store.queueErrorMessage {
                            Text(message).foregroundStyle(.secondary)
                        }
                        if store.queueContinuation != nil {
                            Button(store.queueErrorMessage == nil ? "Load More" : "Try Again") { Task { await store.loadMoreQueue() } }.disabled(store.isLoadingQueue)
                        }
                    }
                }
                .navigationTitle("Queue")
                .toolbar { ToolbarItem(placement: .cancellationAction) { GusCloseButton { showingQueue = false }.labelStyle(.iconOnly) } }
            }
        }
        .safeAreaInset(edge: .top) {
            if let notice = store.trackSelectionNotice {
                HStack { Text(notice); Button("OK") { store.trackSelectionNotice = nil } }
                    .padding().background(.regularMaterial)
            }
        }
        .onChange(of: SharePlayCoordinator.shared.isSharing) { _, _ in
            if let player = store.nativePlayer, let request = store.request {
                SharePlayCoordinator.shared.attachPlayer(player, request: request, session: session)
            }
        }
        .onChange(of: store.currentTime, initial: true) { _, time in
            guard !isScrubbing else { return }
            scrubTime = time
        }
    }

    private var controls: some View {
        VStack(spacing: usesLeadingTitle ? 24 : 20) {
            titleBlock
            progressBlock
            transportControls
            #if os(iOS)
                if widthClass == .compact || DeviceIdentity.usesIPadPresentation {
                    GusSystemVolumeControl().frame(height: 32)
                }
            #endif
            if !usesInlineTransport || track?.type == .audioBook {
                secondaryControls
            }
        }
    }

    private var artwork: some View {
        ArtworkTile(
            url: track.flatMap { session.mediaProvider.primaryImageURL(for: $0, context: .posterGrid) },
            aspectRatio: 1,
            placeholderSymbol: track?.type == .audioBook ? "book" : "music.note",
            fallbackURLs: track.map { session.mediaProvider.artworkURLs(for: $0, request: .init(role: .square, maxWidth: 360)) } ?? []
        )
        .frame(maxWidth: audioArtworkWidth)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }

    private var audioArtworkWidth: CGFloat {
        #if os(tvOS)
            480
        #else
            320
        #endif
    }

    private var titleBlock: some View {
        VStack(alignment: usesLeadingTitle ? .leading : .center, spacing: 4) {
            Text(track?.displayTitle ?? "")
                .font(.title2.bold())
                .lineLimit(2)
                .multilineTextAlignment(usesLeadingTitle ? .leading : .center)
            if let artist = track?.albumArtist ?? track?.artists.first {
                Text(artist)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            if let album = track?.album {
                Text(album)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: usesLeadingTitle ? .leading : .center)
        .accessibilityElement(children: .combine)
    }

    private var progressBlock: some View {
        VStack(spacing: 4) {
            #if !os(tvOS)
                Slider(value: $scrubTime, in: 0 ... max(store.duration, 1)) { editing in
                    isScrubbing = editing
                    if !editing {
                        Task { await store.seek(to: scrubTime) }
                    }
                }
                .accessibilityLabel("Playback position")
                .accessibilityValue(Text(
                    "\(timeText(scrubTime)) of \(timeText(store.duration))",
                    comment: "VoiceOver value for the playback scrubber, e.g. 1:30 of 4:05"
                ))
            #endif

            HStack {
                Text(timeText(store.currentTime))
                Spacer()
                Text(timeText(store.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transportControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: usesInlineTransport ? 4 : 12) {
                if usesInlineTransport {
                    queueButton
                }
                shuffleButton; previousButton; playPauseButton; nextButton; repeatButton
                if usesInlineTransport {
                    AirPlayRoutePicker().frame(width: 44, height: 44)
                }
            }
            VStack(spacing: 12) {
                HStack(spacing: 12) { previousButton; playPauseButton; nextButton }
                HStack(spacing: 12) {
                    if usesInlineTransport {
                        queueButton
                    }
                    shuffleButton; repeatButton
                    if usesInlineTransport {
                        AirPlayRoutePicker().frame(width: 44, height: 44)
                    }
                }
            }
        }
        .font(.title2)
        .gusAudioTransportStyle()
        .gusPhoneAudioTransportColor()
    }

    private var shuffleButton: some View {
        Button {
            store.toggleShuffle()
        } label: {
            Image(systemName: "shuffle")
                .symbolVariant(store.isShuffled ? .circle.fill : .none)
        }
        .accessibilityLabel(
            store.isShuffled
                ? String(localized: "Shuffle On", comment: "Accessibility label for the shuffle button when active")
                : String(localized: "Shuffle Off", comment: "Accessibility label for the shuffle button when inactive")
        )
    }

    private var previousButton: some View {
        Button {
            Task { await store.previous() }
        } label: {
            Image(systemName: "backward.fill")
        }
        .accessibilityLabel(String(localized: "Previous Track", comment: "Accessibility label for the previous track button"))
    }

    private var playPauseButton: some View {
        Button {
            store.playPause()
        } label: {
            AudioTransportGlyph(isPlaying: store.isPlaybackRequested)
        }
        .accessibilityLabel(
            store.isPlaybackRequested
                ? String(localized: "Pause", comment: "Accessibility label for the pause button")
                : String(localized: "Play", comment: "Accessibility label for the play button")
        )
    }

    private var nextButton: some View {
        Button {
            Task { await store.next() }
        } label: {
            Image(systemName: "forward.fill")
        }
        .disabled(!store.hasNext)
        .accessibilityLabel(String(localized: "Next Track", comment: "Accessibility label for the next track button"))
    }

    private var repeatButton: some View {
        Button {
            store.cycleRepeatMode()
        } label: {
            Image(systemName: repeatSymbol)
        }
        .accessibilityLabel(repeatAccessibilityLabel)
    }

    private var secondaryControls: some View {
        HStack(spacing: 24) {
            if track?.type == .audioBook {
                speedMenu
                chaptersMenu
            }
            if !usesInlineTransport {
                queueButton
                #if os(iOS)
                    if DeviceIdentity.usesIPadPresentation {
                        Spacer()
                    }
                #endif
                AirPlayRoutePicker().frame(width: 44, height: 44)
            }
        }
    }

    private var queueButton: some View {
        Button("Queue", systemImage: "list.bullet") { showingQueue = true }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
    }

    private var speedMenu: some View {
        Menu {
            ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                Button {
                    store.playbackRate = rate
                } label: {
                    Label(
                        rate.formatted(.number.precision(.fractionLength(0 ... 2))) + "×",
                        systemImage: store.playbackRate == rate ? "checkmark" : "gauge.with.needle"
                    )
                }
            }
        } label: {
            Label("Speed", systemImage: "gauge.with.needle")
        }
        .accessibilityLabel("Playback Speed")
    }

    @ViewBuilder
    private var chaptersMenu: some View {
        if let track, !track.chapters.isEmpty {
            Menu {
                ForEach(PlaybackChapter.seekTargets(for: track)) { chapter in
                    Button(chapter.title) {
                        Task { await store.seek(to: chapter.seconds) }
                    }
                }
            } label: {
                Label("Chapters", systemImage: "list.bullet")
            }
            .accessibilityLabel("Chapters")
        }
    }

    private var repeatSymbol: String {
        switch store.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat.circle.fill"
        case .one: return "repeat.1.circle.fill"
        }
    }

    private var repeatAccessibilityLabel: String {
        switch store.repeatMode {
        case .off: return String(localized: "Repeat Off", comment: "Repeat mode accessibility label")
        case .all: return String(localized: "Repeat All", comment: "Repeat mode accessibility label")
        case .one: return String(localized: "Repeat One", comment: "Repeat mode accessibility label")
        }
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Entry fallback for audio reached through an existing presentation.
struct AudioPlayerScreen: View {
    @Environment(AudioPlaybackCoordinator.self) private var audio
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    let item: MediaItem
    var localOnly = false
    var playbackRequest: PlaybackRequest? = nil
    var body: some View {
        Group {
            if let store = audio.store {
                AudioPlayerView(store: store)
            } else {
                ProgressView()
            }
        }
        .task(id: PlaybackPresentationIdentity(request: playbackRequest ?? PlaybackRequest(item: item), sessionGeneration: session.lease.generation, localOnly: localOnly)) {
            audio.play(tracks: [item], localOnly: localOnly, request: playbackRequest, session: session, downloads: downloads)
        }
    }
}

private struct AudioTransportStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension View {
    @ViewBuilder func gusAudioTransportStyle() -> some View {
        #if os(tvOS)
            buttonStyle(.bordered)
        #else
            buttonStyle(AudioTransportStyle())
        #endif
    }
}
