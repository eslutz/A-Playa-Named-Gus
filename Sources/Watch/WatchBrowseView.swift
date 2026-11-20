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
            retryAction: { Task { await load() } },
            preservesContent: true
        ) {
            List {
                if #available(watchOS 27, *) {
                    NavigationLink(value: WatchIntelligenceRoute.search) { Label("Search Library", systemImage: "magnifyingglass") }
                        .accessibilityIdentifier("Watch.Browse.search")
                    if session.intelligencePreferences.recommendationsEnabled {
                        NavigationLink(value: WatchIntelligenceRoute.forYou) { Label("For You", systemImage: "heart") }
                    }
                }
                ForEach(libraries, id: \.id) { library in
                    if let id = library.id {
                        NavigationLink(value: WatchLibraryRoute(id: id)) {
                            Label(library.name ?? "Library", systemImage: library.librarySymbol)
                        }
                    }
                }
            }
        }
        .navigationDestination(for: WatchIntelligenceRoute.self) { route in
            if #available(watchOS 27, *) {
                switch route {
                case .search: WatchLibrarySearchView()
                case .forYou: WatchForYouView()
                }
            }
        }
        .navigationDestination(for: WatchLibraryRoute.self) { route in
            if let library = libraries.first(where: { $0.id == route.id }) {
                WatchLibraryView(library: library)
            }
        }
        .refreshable { await load() }
        .navigationTitle("Browse")
        .task {
            await load()
        }
    }

    private func load() async {
        guard session.isActive, state != .loading else { return }
        state = .loading
        do {
            let loadedLibraries = try await session.mediaProvider.userViews()
            try Task.checkCancellation()
            guard session.isActive else { return }
            libraries = loadedLibraries
            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { state = .idle; return }
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
            retryAction: { Task { await load() } },
            preservesContent: true
        ) {
            List(items, id: \.id) { item in
                WatchItemRow(item: item)
            }
        }
        .navigationDestination(for: WatchItemRoute.self) { route in
            if let item = items.first(where: { $0.id == route.id }) {
                if item.type == .musicAlbum {
                    WatchAlbumView(album: item)
                } else {
                    WatchItemActionsView(item: item)
                }
            }
        }
        .refreshable { await load() }
        .navigationTitle(library.name ?? "Library")
        .task {
            await load()
        }
    }

    private func load() async {
        guard session.isActive, state != .loading else { return }
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
            try Task.checkCancellation()
            guard session.isActive else { return }
            items = ContentRatingGate.filter(page.items)
            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { state = .idle; return }
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

private enum WatchIntelligenceRoute: Hashable {
    case search, forYou
}

private struct WatchLibraryRoute: Hashable {
    let id: String
}

struct WatchItemRoute: Hashable {
    let id: String
}

/// One browsable item: albums drill into tracks; everything else opens actions.
struct WatchItemRow: View {
    let item: MediaItem

    var body: some View {
        if let id = item.id {
            NavigationLink(value: WatchItemRoute(id: id)) { label }
        } else {
            label
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
                } else if let subtitle = item.bookBrowseSubtitle ?? item.yearText {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.mediaAccessibility.label)
        .accessibilityValue(item.mediaAccessibility.value)
    }
}

/// Album track list — tapping a track starts the on-watch audio queue at that song.
struct WatchAlbumView: View {
    @Environment(SessionStore.self) private var session
    let album: MediaItem

    @State private var tracks: [MediaItem] = []
    @State private var state: LoadState = .idle
    @State private var continuation: AudioQueueContinuation?
    @State private var loadingMore = false
    @State private var pageError: String?
    @State private var refreshError: String?
    @State private var playerQueue: WatchAudioQueueRef?

    var body: some View {
        LoadingStateView(
            state: state,
            isEmpty: tracks.isEmpty && continuation == nil,
            emptyTitle: "No Tracks",
            emptySymbol: "music.note",
            retryAction: { Task { await load() } },
            preservesContent: true
        ) {
            List {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        playerQueue = WatchAudioQueueRef(tracks: tracks, startIndex: index, continuation: continuation)
                    } label: {
                        Text(track.displayTitle)
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(track.mediaAccessibility.label)
                    .accessibilityValue(track.mediaAccessibility.value)
                }
                if let refreshError {
                    Text(refreshError).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await load() } }.disabled(state == .loading)
                }
                if let pageError {
                    Text(pageError).foregroundStyle(.secondary)
                }
                if continuation != nil {
                    Button("Load More") { Task { await load(reset: false) } }.disabled(loadingMore)
                }
                if loadingMore {
                    ProgressView()
                }
            }
        }
        .refreshable { await load() }
        .navigationTitle(album.displayTitle)
        .task {
            await load()
        }
        .sheet(item: $playerQueue) { queue in
            WatchAudioPlayerView(tracks: queue.tracks, startIndex: queue.startIndex, continuation: queue.continuation)
        }
    }

    private func load(reset: Bool = true) async {
        guard session.isActive, state != .loading, !loadingMore, reset || continuation != nil else { return }
        let previousTracks = tracks
        let previousContinuation = continuation
        if reset {
            state = .loading
        } else {
            loadingMore = true
        }
        defer { loadingMore = false }
        pageError = nil
        refreshError = nil
        var query = continuation?.query ?? MediaItemQuery(parentID: album.id, startIndex: 0, limit: 100, sort: .trackOrder)
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
}

/// Identifiable wrapper so a queue + start index can drive `sheet(item:)`.
struct WatchAudioQueueRef: Identifiable {
    let tracks: [MediaItem]
    let startIndex: Int
    var continuation: AudioQueueContinuation? = nil

    var id: String {
        "\(tracks.first?.id ?? "queue")-\(startIndex)"
    }
}
