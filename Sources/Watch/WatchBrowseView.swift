import SwiftUI

/// Lightweight library browsing per the watchOS brief: shallow entry points focused on
/// recent content — not full replacement browsing. Entry rows come from the server's
/// libraries; each opens a short recent-items list tuned per collection type.
struct WatchBrowseView: View {
    @Environment(SessionStore.self) private var session

    @State private var libraries: [MediaItem] = []
    @State private var state: LoadState = .idle

    var body: some View {
        LoadingStateView(
            state: state,
            isEmpty: libraries.isEmpty,
            emptyTitle: "No Libraries",
            emptySymbol: "rectangle.stack",
            retryAction: { Task { await load() } }
        ) {
            List(libraries, id: \.id) { library in
                NavigationLink {
                    WatchLibraryView(library: library)
                } label: {
                    Label(library.name ?? "Library", systemImage: library.librarySymbol)
                }
            }
        }
        .navigationTitle("Browse")
        .task {
            await load()
        }
    }

    private func load() async {
        guard state != .loading else { return }
        state = .loading
        do {
            libraries = try await session.mediaProvider.userViews()
            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            state = .failed(gusError.localizedDescription)
        }
    }
}

/// Recent items for one library, shaped per collection type (episodes for shows,
/// albums for music, books+audiobooks for book libraries, movies otherwise).
struct WatchLibraryView: View {
    @Environment(SessionStore.self) private var session
    let library: MediaItem

    @State private var items: [MediaItem] = []
    @State private var state: LoadState = .idle

    var body: some View {
        LoadingStateView(
            state: state,
            isEmpty: items.isEmpty,
            emptyTitle: "Nothing Recent",
            emptySymbol: library.librarySymbol,
            retryAction: { Task { await load() } }
        ) {
            List(items, id: \.id) { item in
                WatchItemRow(item: item)
            }
        }
        .navigationTitle(library.name ?? "Library")
        .task {
            await load()
        }
    }

    private func load() async {
        guard state != .loading else { return }
        state = .loading
        do {
            let page = try await session.mediaProvider.items(query: MediaItemQuery(
                parentID: library.id,
                includeTypes: includeTypes,
                startIndex: 0,
                limit: 30,
                isRecursive: true,
                sort: .recentlyAdded
            ))
            items = ContentRatingGate.filter(page.items)
            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            state = .failed(gusError.localizedDescription)
        }
    }

    private var includeTypes: [MediaItemType]? {
        switch library.collectionType {
        case .movies: return [.movie]
        case .tvshows: return [.episode]
        case .music: return [.musicAlbum]
        case .books: return [.book, .audioBook]
        default: return nil
        }
    }
}

/// One browsable item: albums drill into tracks; everything else opens actions.
struct WatchItemRow: View {
    let item: MediaItem

    var body: some View {
        if item.type == .musicAlbum {
            NavigationLink {
                WatchAlbumView(album: item)
            } label: {
                label
            }
        } else {
            NavigationLink {
                WatchItemActionsView(item: item)
            } label: {
                label
            }
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            WatchPoster(item: item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                if item.type == .episode, let series = item.seriesName {
                    Text(series)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let year = item.yearText {
                    Text(year)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Album track list — tapping a track starts the on-watch audio queue at that song.
struct WatchAlbumView: View {
    @Environment(SessionStore.self) private var session
    let album: MediaItem

    @State private var tracks: [MediaItem] = []
    @State private var state: LoadState = .idle
    @State private var playerQueue: WatchAudioQueueRef?

    var body: some View {
        LoadingStateView(
            state: state,
            isEmpty: tracks.isEmpty,
            emptyTitle: "No Tracks",
            emptySymbol: "music.note",
            retryAction: { Task { await load() } }
        ) {
            List(Array(tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    playerQueue = WatchAudioQueueRef(tracks: tracks, startIndex: index)
                } label: {
                    Text(track.displayTitle)
                        .lineLimit(2)
                }
            }
        }
        .navigationTitle(album.displayTitle)
        .task {
            await load()
        }
        .sheet(item: $playerQueue) { queue in
            WatchAudioPlayerView(tracks: queue.tracks, startIndex: queue.startIndex)
        }
    }

    private func load() async {
        guard state != .loading else { return }
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
}

/// Identifiable wrapper so a queue + start index can drive `sheet(item:)`.
struct WatchAudioQueueRef: Identifiable {
    let tracks: [MediaItem]
    let startIndex: Int

    var id: String {
        "\(tracks.first?.id ?? "queue")-\(startIndex)"
    }
}
