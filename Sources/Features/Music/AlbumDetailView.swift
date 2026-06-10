import SwiftUI

/// Track list for a music album, playlist, or audiobook container: artwork header,
/// Play/Shuffle actions, and tappable track rows that start the audio player queue.
struct AlbumDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    let album: MediaItem

    @State private var tracks: [MediaItem] = []
    @State private var state: LoadState = .idle
    @State private var audioPlayer: AudioPlayerStore?
    @State private var isPlayerPresented = false

    var body: some View {
        LoadingStateView(
            state: state,
            isEmpty: tracks.isEmpty,
            emptyTitle: "No Tracks",
            emptySymbol: "music.note"
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    trackList
                }
                .padding()
                .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .lookToScroll()
        }
        .navigationTitle(album.displayTitle)
        .task {
            await loadTracks()
        }
        .sheet(isPresented: $isPlayerPresented) {
            audioPlayer?.teardown()
            audioPlayer = nil
        } content: {
            if let audioPlayer {
                AudioPlayerView(store: audioPlayer)
                    .task { await audioPlayer.start() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            AsyncPoster(
                url: session.mediaProvider.primaryImageURL(for: album, context: .posterGrid),
                placeholderSymbol: "music.note"
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(width: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(album.displayTitle)
                    .font(.title.bold())
                if let artist = album.albumArtist ?? album.artists.first {
                    Text(artist)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                if let year = album.productionYear {
                    Text(String(year))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button {
                        play(startingAt: 0)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        play(startingAt: 0, shuffled: true)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 8)
            }
            Spacer()
        }
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
                limit: 300,
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
        let store = AudioPlayerStore(session: session, tracks: tracks, startIndex: index, downloads: downloads)
        if shuffled {
            store.toggleShuffle()
        }
        audioPlayer = store
        isPlayerPresented = true
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
            emptySymbol: "music.note.list"
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
                .padding()
                .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .tvFocusSection()
            }
            .lookToScroll()
        }
        .navigationTitle(artist.displayTitle)
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
