import SwiftUI

/// Track list for a music album, playlist, or audiobook container: artwork header,
/// Play/Shuffle actions, and tappable track rows that start the audio player queue.
struct AlbumDetailView: View {
    @Environment(AudioPlaybackCoordinator.self) private var audio
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let album: MediaItem

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    @State private var tracks: [MediaItem] = []
    @State private var state: LoadState = .idle

    var body: some View {
        LoadingStateView(
            state: state,
            isEmpty: tracks.isEmpty,
            emptyTitle: "No Tracks",
            emptySymbol: "music.note",
            retryAction: { Task { await loadTracks() } }
        ) {
            ScrollView {
                albumContent
                    .gusPhonePagePadding()
                    .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .lookToScroll()
        }
        .navigationTitle(album.displayTitle)
        .gusTVDetailTitle()
        .task {
            await loadTracks()
        }
    }

    @ViewBuilder private var albumContent: some View {
        #if os(iOS)
            if DeviceIdentity.usesIPadPresentation, widthClass == .regular, !dynamicTypeSize.isAccessibilitySize {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 32) {
                        VStack(alignment: .leading, spacing: 16) {
                            albumArtwork
                            if let artist = album.albumArtist ?? album.artists.first {
                                Text(artist).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if let year = album.productionYear {
                                Text(String(year)).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text("\(tracks.count) tracks").font(.subheadline).foregroundStyle(.secondary)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 12) { albumActions }
                                VStack(alignment: .leading, spacing: 12) { albumActions }
                            }
                        }
                        .frame(width: 240, alignment: .leading)
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Tracks").font(.headline)
                            trackList
                        }
                        .frame(minWidth: 280, maxWidth: .infinity, alignment: .leading)
                    }
                    stackedContent
                }
            } else {
                stackedContent
            }
        #elseif os(tvOS)
            HStack(alignment: .top, spacing: 64) {
                VStack(alignment: .leading, spacing: 32) {
                    albumArtwork
                    VStack(alignment: .leading, spacing: 24) { albumActions }
                }
                .frame(width: 360)
                VStack(alignment: .leading, spacing: 24) {
                    Text("Tracks").font(.title2.bold())
                    trackList
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .gusTVContentHeading(album.displayTitle)
            .padding(64)
        #else
            stackedContent
        #endif
    }

    private var stackedContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            trackList
        }
    }

    @ViewBuilder private var header: some View {
        #if os(iOS)
            if widthClass == .compact {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 6) {
                        if let artist = album.albumArtist ?? album.artists.first {
                            Text(artist)
                        }
                        if let year = album.productionYear {
                            Text(String(year))
                        }
                        Text("\(tracks.count) tracks")
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                    albumArtwork
                    HStack(spacing: 12) { albumActions }
                }
            } else {
                adaptiveHeader
            }
        #else
            adaptiveHeader
        #endif
    }

    private var adaptiveHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) { albumArtwork; albumInfo }
            VStack(alignment: .leading, spacing: 20) { albumArtwork; albumInfo }
        }
    }

    private var artworkWidth: CGFloat {
        #if os(iOS)
            widthClass == .compact ? 160 : (DeviceIdentity.usesIPadPresentation ? 240 : 180)
        #elseif os(tvOS)
            360
        #else
            180
        #endif
    }

    private var albumArtwork: some View {
        ArtworkTile(url: session.mediaProvider.primaryImageURL(for: album, context: .posterGrid), aspectRatio: 1, placeholderSymbol: "music.note")
            .frame(width: artworkWidth)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var albumInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(album.displayTitle).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
            if let artist = album.albumArtist ?? album.artists.first {
                Text(artist).font(.title3)
            }
            if let year = album.productionYear {
                Text(String(year)).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { albumActions }
                VStack(alignment: .leading, spacing: 12) { albumActions }
            }
        }
    }

    @ViewBuilder private var albumActions: some View {
        Button { play(startingAt: 0) } label: {
            Label("Play", systemImage: "play.fill")
                .gusProminentActionForeground()
                .gusPhoneActionLabelHeight()
        }
        .gusProminentGlassButtonStyle()
        .controlSize(.large)
        .fixedSize()
        Button { play(startingAt: 0, shuffled: true) } label: {
            Label("Shuffle", systemImage: "shuffle").gusPhoneActionLabelHeight()
        }
        .gusGlassButtonStyle()
        .controlSize(.large)
        .fixedSize()
    }

    private var trackList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    play(startingAt: index)
                } label: {
                    TrackRow(index: track.indexNumber ?? index + 1, track: track)
                }
                .buttonStyle(.plain)
                .visionHoverEffect(cornerRadius: 8)

                if index < tracks.count - 1 {
                    Divider()
                }
            }
        }
        .tvFocusSection()
    }

    private func loadTracks() async {
        guard state != .loading, tracks.isEmpty else { return }
        state = .loading
        do {
            let page = try await session.mediaProvider.items(query: MediaItemQuery(
                parentID: album.id,
                startIndex: 0,
                limit: 1000,
                sort: .trackOrder
            ))
            tracks = page.items.filter(\.isAudioPlayable)
            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            state = .failed(gusError.localizedDescription)
        }
    }

    private func play(startingAt index: Int, shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }
        audio.play(tracks: tracks, startIndex: index, shuffled: shuffled, session: session, downloads: downloads)
    }
}

private struct TrackRow: View {
    let index: Int
    let track: MediaItem

    var body: some View {
        HStack(spacing: 16) {
            Text(String(index))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)

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
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        if let runtime = track.runtimeText {
            Text("\(track.displayTitle), \(runtime)")
        } else {
            Text(track.displayTitle)
        }
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
            ScrollView {
                LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: PosterGrid.spacing) {
                    ForEach(albums, id: \.id) { albumItem in
                        NavigationLink(value: ItemRef(item: albumItem)) {
                            PosterCard(
                                title: albumItem.displayTitle,
                                subtitle: albumItem.productionYear.map(String.init),
                                imageURL: session.mediaProvider.primaryImageURL(for: albumItem, context: .posterGrid),
                                aspectRatio: 1,
                                placeholderSymbol: "music.note"
                            )
                        }
                        .posterNavigationStyle()
                    }
                }
                .gusTVContentHeading(artist.displayTitle)
                .padding()
                .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .tvFocusSection()
            }
            .lookToScroll()
        }
        .navigationTitle(artist.displayTitle)
        .gusTVDetailTitle()
        .task {
            await loadAlbums()
        }
    }

    private func loadAlbums() async {
        guard state != .loading, albums.isEmpty else { return }
        state = .loading
        do {
            let page = try await session.mediaProvider.items(query: MediaItemQuery(
                artistID: artist.id,
                startIndex: 0,
                limit: 200,
                sort: .name
            ))
            albums = page.items
            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            state = .failed(gusError.localizedDescription)
        }
    }
}
