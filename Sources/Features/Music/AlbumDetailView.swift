import SwiftUI

/// Track list for a music album, playlist, or audiobook container: artwork header,
/// Play/Shuffle actions, and tappable track rows that start the audio player queue.
struct AlbumDetailView: View {
    @Environment(AudioPlaybackCoordinator.self) private var audio
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    let album: MediaItem

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    @State private var tracks: [MediaItem] = []
    @State private var state: LoadState = .idle
    @State private var continuation: AudioQueueContinuation?
    @State private var loadingMore = false
    @State private var pageError: String?
    @State private var refreshError: String?

    var body: some View {
        LoadingStateView(
            state: state,
            isEmpty: tracks.isEmpty && continuation == nil,
            emptyTitle: "No Tracks",
            emptySymbol: "music.note",
            retryAction: { Task { await loadTracks() } },
            preservesContent: true
        ) {
            ArtworkDetailPage { albumHeader } sections: { trackList }
        }
        .refreshable { await loadTracks() }
        .navigationTitle(album.displayTitle)
        .toolbarTitleDisplayMode(.inline)
        .gusTVDetailTitle()
        .task {
            await loadTracks()
        }
    }

    private var albumHeader: some View {
        DetailCoverHeader(maximumCoverWidth: artworkWidth) {
            albumArtwork
        } summary: {
            Text(album.displayTitle).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            if let artist = album.albumArtist ?? album.artists.first {
                Text(artist).font(.title3)
            }
            if let year = album.productionYear {
                Text(String(year)).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(trackCount).font(.subheadline).foregroundStyle(.secondary)
            albumActions
            if let overview = album.overview {
                DetailSynopsis(title: album.displayTitle, overview: overview)
            }
        }
    }

    private var trackCount: String {
        continuation == nil ? String(localized: "\(tracks.count) tracks") : String(localized: "\(tracks.count) tracks loaded")
    }

    private var artworkWidth: CGFloat {
        #if os(iOS)
            widthClass == .compact ? 220 : 240
        #elseif os(tvOS)
            360
        #else
            180
        #endif
    }

    private var albumArtwork: some View {
        Group {
            if album.type == .playlist {
                PlaylistCoverArtwork(playlist: album, entries: tracks, maxWidth: 360, contentMode: .fit)
            } else {
                ArtworkTile(url: session.mediaProvider.primaryImageURL(for: album, context: .posterGrid), aspectRatio: 1, contentMode: .fit, placeholderSymbol: "music.note", fallbackURLs: session.mediaProvider.artworkURLs(for: album, request: .init(role: .square, maxWidth: 360)))
            }
        }

        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var albumActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailPrimaryButton("Play", systemImage: "play.fill") { play(startingAt: 0) }
            DetailActionRow {
                ItemUserActionButton(title: "Shuffle", systemImage: "shuffle") { play(startingAt: 0, shuffled: true) }
            }
        }
        .frame(maxWidth: DetailActionMetrics.maximumRowWidth)
        .disabled(tracks.isEmpty)
    }

    private var trackList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    play(startingAt: index)
                } label: {
                    TrackRow(index: track.indexNumber ?? index + 1, track: track, showsThumbnail: album.type == .playlist)
                }
                .buttonStyle(.plain)
                .visionHoverEffect(cornerRadius: 8)

                if index < tracks.count - 1 {
                    Divider()
                }
            }
            if let refreshError {
                Text(refreshError).foregroundStyle(.secondary)
                Button("Try Again") { Task { await loadTracks() } }.disabled(state == .loading)
            }
            if let pageError {
                Text(pageError).foregroundStyle(.secondary)
            }
            if continuation != nil {
                Button("Load More") { Task { await loadTracks(reset: false) } }.disabled(loadingMore)
            }
            if loadingMore {
                ProgressView()
            }
        }
        .tvFocusSection()
    }

    private func loadTracks(reset: Bool = true) async {
        guard session.isActive, state != .loading, !loadingMore, reset || continuation != nil else { return }
        let previousTracks = tracks
        let previousContinuation = continuation
        if reset {
            state = .loading
        } else {
            loadingMore = true
        }
        pageError = nil
        refreshError = nil
        defer { loadingMore = false }
        var query = continuation?.query ?? MediaItemQuery(parentID: album.id, startIndex: 0, limit: 200, sort: .trackOrder)
        query.startIndex = reset ? 0 : continuation?.nextStartIndex ?? 0
        var replacing = reset
        do {
            for _ in 0 ..< 3 {
                let page = try await session.mediaProvider.items(query: query)
                try Task.checkCancellation()
                guard session.isActive else { return }
                let total = try MediaPageLoader.validatedTotal(for: page, startIndex: query.startIndex, previousTotal: replacing ? nil : continuation?.totalRecordCount)
                let eligible = ContentRatingGate.filter(page.items).filter(\.isAudioPlayable)
                tracks = (replacing ? [] : tracks) + MediaPageLoader.unique(eligible, after: replacing ? [] : tracks)
                replacing = false
                query.startIndex += page.items.count
                let more = !page.items.isEmpty && (total.map { query.startIndex < $0 } ?? (page.items.count >= query.limit))
                continuation = more ? .init(query: query, nextStartIndex: query.startIndex, totalRecordCount: total) : nil
                state = .loaded
                if !eligible.isEmpty || !more {
                    return
                }
            }
        } catch {
            let failure = GusError(from: error)
            guard session.isActive else { return }
            if reset, !previousTracks.isEmpty {
                tracks = previousTracks
                continuation = previousContinuation
            }
            guard !failure.isCancellation else { state = tracks.isEmpty ? .idle : .loaded; return }
            if tracks.isEmpty {
                state = .failed(failure.localizedDescription)
            } else {
                state = .loaded
                if reset {
                    refreshError = failure.localizedDescription
                } else {
                    pageError = failure.localizedDescription
                }
            }
        }
    }

    private func play(startingAt index: Int, shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }
        audio.play(tracks: tracks, startIndex: index, shuffled: shuffled, continuation: continuation, session: session, downloads: downloads)
    }
}

private struct TrackRow: View {
    let index: Int
    let track: MediaItem
    let showsThumbnail: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text(String(index))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)

            if showsThumbnail {
                PlaylistEntryThumbnail(item: track)
            }
            Text(track.displayTitle)
                .lineLimit(1)

            Spacer()

            if let runtime = track.runtimeText {
                Text(runtime)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(track.mediaAccessibility.label)
        .accessibilityValue(track.mediaAccessibility.value)
    }
}

/// Albums by an artist, pushed when an artist tile is opened from a music library.
struct ArtistAlbumsView: View {
    @Environment(SessionStore.self) private var session
    let artist: MediaItem

    @State private var albums: [MediaItem] = []
    @State private var state: LoadState = .idle

    var body: some View {
        LoadingStateView(
            state: state,
            isEmpty: albums.isEmpty,
            emptyTitle: "No Albums",
            emptySymbol: "music.note.list",
            retryAction: { Task { await loadAlbums() } }
        ) {
            ArtworkDetailPage {
                DetailCoverHeader {
                    let urls = session.mediaProvider.artworkURLs(for: artist, request: .init(role: .square, maxWidth: 640))
                    ArtworkTile(url: urls.first, aspectRatio: 1, contentMode: .fit, placeholderSymbol: "music.mic", fallbackURLs: Array(urls.dropFirst()))
                } summary: {
                    Text(artist.displayTitle).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    if let overview = artist.overview {
                        DetailSynopsis(title: artist.displayTitle, overview: overview)
                    }
                }
            } sections: {
                LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: PosterGrid.spacing) {
                    ForEach(albums, id: \.id) { albumItem in
                        NavigationLink(value: GusRoute.item(.init(item: albumItem))) {
                            PosterCard(
                                title: albumItem.displayTitle,
                                subtitle: albumItem.productionYear.map(String.init),
                                statusItem: albumItem,
                                imageURL: session.mediaProvider.primaryImageURL(for: albumItem, context: .posterGrid),
                                aspectRatio: 1,
                                placeholderSymbol: "music.note",
                                fallbackURLs: session.mediaProvider.artworkURLs(for: albumItem, request: .init(role: .square, maxWidth: 360))
                            )
                        }
                        .posterNavigationStyle()
                    }
                }.tvFocusSection()
            }
        }
        .navigationTitle(artist.displayTitle)
        .toolbarTitleDisplayMode(.inline)
        .gusTVDetailTitle()
        .task {
            await loadAlbums()
        }
    }

    private func loadAlbums() async {
        guard state != .loading, albums.isEmpty else { return }
        state = .loading
        do {
            let loaded = try await session.mediaProvider.allItems(query: MediaItemQuery(
                artistID: artist.id,
                startIndex: 0,
                limit: 200,
                sort: .name
            ))
            try Task.checkCancellation()
            guard session.isActive else { return }
            albums = ContentRatingGate.filter(loaded)
            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { state = .idle; return }
            state = .failed(gusError.localizedDescription)
        }
    }
}
