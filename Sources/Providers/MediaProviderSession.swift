import Foundation

struct MediaItemPage: Sendable {
    var items: [MediaItem]
    var totalRecordCount: Int?
}

struct MediaItemQuery {
    var parentID: String?
    var searchTerm: String?
    /// Restricts results to albums by this artist (provider-mapped, e.g. Jellyfin `artistIds`).
    var artistID: String?
    /// Restricts results to these item types (provider-mapped, e.g. Jellyfin `includeItemTypes`).
    var includeTypes: [MediaItemType]?
    var startIndex: Int
    var limit: Int
    var isRecursive: Bool
    var sort: MediaItemSort?
    var statusFilter: MediaItemStatusFilter

    init(
        parentID: String? = nil,
        searchTerm: String? = nil,
        artistID: String? = nil,
        includeTypes: [MediaItemType]? = nil,
        startIndex: Int,
        limit: Int,
        isRecursive: Bool = false,
        sort: MediaItemSort? = nil,
        statusFilter: MediaItemStatusFilter = .all
    ) {
        self.parentID = parentID
        self.searchTerm = searchTerm
        self.artistID = artistID
        self.includeTypes = includeTypes
        self.startIndex = startIndex
        self.limit = limit
        self.isRecursive = isRecursive
        self.sort = sort
        self.statusFilter = statusFilter
    }
}

struct PlaybackSourceResolution {
    var url: URL
    var playSessionID: String?
    var mediaSourceID: String?
    var playMethod: MediaPlaybackMethod
    var stereoLayout: Stereo3DLayout
    var stereoFallbackReason: StreamURLBuilder.StereoFallbackReason?
    var mediaSource: MediaSource? = nil

    var isTranscoding: Bool {
        playMethod == .transcode
    }
}

struct DownloadSourceResolution {
    var url: URL
    var fileExtension: String
    var requiresTranscoding: Bool
    var operation: DownloadActivity.SourceOperation? = nil
}

struct PlaybackReportContext {
    let itemID: String
    let mediaSourceID: String?
    let playSessionID: String?
    let playMethod: MediaPlaybackMethod
    let streamSelection: PlaybackStreamSelection
}

/// A scheduled Live TV recording.
struct LiveTVTimer: Identifiable, Equatable {
    let id: String
    let name: String
    let channelName: String?
    let startDate: Date?
}

@MainActor
protocol MediaProviderSession: AnyObject, Sendable {
    var providerKind: MediaProviderKind { get }
    var capabilities: ProviderCapabilities { get }

    func userViews() async throws -> [MediaItem]
    func resumeItems(limit: Int) async throws -> [MediaItem]
    func resumeItemsPage(startIndex: Int, limit: Int) async throws -> MediaItemPage
    func nextUpItems(seriesID: String?, limit: Int) async throws -> [MediaItem]
    func nextUpItemsPage(startIndex: Int, limit: Int) async throws -> MediaItemPage
    func latestMedia(in library: MediaItem, limit: Int) async throws -> [MediaItem]
    func items(query: MediaItemQuery) async throws -> MediaItemPage
    func item(id: String) async throws -> MediaItem
    func similarItems(itemID: String, limit: Int) async throws -> [MediaItem]
    func specialFeatures(itemID: String) async throws -> [MediaItem]
    func seasons(seriesID: String) async throws -> [MediaItem]
    func episodes(seriesID: String, seasonID: String, limit: Int) async throws -> MediaItemPage

    func primaryImageURL(for item: MediaItem, context: ImageURLBuilder.ImageContext) -> URL?
    func primaryImageURL(for item: MediaItem, maxWidth: Int) -> URL?
    func backdropImageURL(for item: MediaItem, context: ImageURLBuilder.ImageContext) -> URL?
    func backdropImageURL(for item: MediaItem, maxWidth: Int) -> URL?
    func artworkURLs(for item: MediaItem, maxWidth: Int) -> [URL]
    func personImageURL(for person: MediaPerson, maxWidth: Int) -> URL?

    func resolvePlayback(
        for itemID: String,
        maxStreamingBitrate: Int,
        streamSelection: PlaybackStreamSelection,
        startTimeTicks: Int?,
        stereoLayout: Stereo3DLayout
    ) async throws -> PlaybackSourceResolution

    /// Resolves a playable URL for a song or audiobook; the provider direct-plays
    /// AVPlayer-native audio containers and transcodes the rest server-side.
    func resolveAudioPlayback(for itemID: String) async throws -> PlaybackSourceResolution

    func downloadSource(for item: MediaItem) async throws -> DownloadSourceResolution

    // MARK: Live TV (no-tuner servers report unavailable)

    func liveTVIsEnabled() async -> Bool
    func liveTVChannels(startIndex: Int, limit: Int) async throws -> MediaItemPage
    func liveTVRecordings(limit: Int) async throws -> [MediaItem]
    func liveTVTimers() async throws -> [LiveTVTimer]
    func cancelLiveTVTimer(id: String) async throws

    /// Marks an item as played or unplayed for the current user.
    func toggleWatched(itemID: String, currentlyWatched: Bool) async throws
    /// Marks or unmarks an item as a favourite for the current user.
    func toggleFavorite(itemID: String, currentlyFavorite: Bool) async throws

    func reportPlaybackStart(context: PlaybackReportContext, positionTicks: Int, isPaused: Bool) async throws
    func reportPlaybackProgress(context: PlaybackReportContext, positionTicks: Int, isPaused: Bool) async throws
    func reportPlaybackStopped(context: PlaybackReportContext, positionTicks: Int) async throws

    /// Updates saved item progress without inventing a live playback session.
    func updatePlaybackPosition(itemID: String, positionTicks: Int) async throws

    // MARK: Native server playlists

    func mediaLists(kind: ServerMediaListKind) async throws -> [ServerMediaList]
    func mediaList(id: UUID, kind: ServerMediaListKind) async throws -> ServerMediaList
    func createMediaList(name: String, kind: ServerMediaListKind, itemIDs: [String]) async throws -> UUID
    func renameMediaList(id: UUID, kind: ServerMediaListKind, name: String) async throws
    func deleteMediaList(id: UUID, kind: ServerMediaListKind) async throws
    func addToMediaList(id: UUID, kind: ServerMediaListKind, itemIDs: [String]) async throws
    func removeFromMediaList(id: UUID, kind: ServerMediaListKind, entryIDs: [UUID]) async throws
    func moveMediaListEntry(id: UUID, entryID: UUID, to index: Int) async throws

    // MARK: Library collections

    func collectionCapabilities(id: String?) async throws -> CollectionCapabilities
    func collectionPage(startIndex: Int, limit: Int) async throws -> MediaItemPage
    func collectionItem(id: String) async throws -> MediaItem
    func collectionMembers(id: String, startIndex: Int, limit: Int) async throws -> MediaItemPage
    func createCollection(name: String, itemIDs: [String]) async throws -> String
    func updateCollection(id: String, name: String, overview: String) async throws
    func deleteCollection(id: String) async throws
    func addCollectionMembers(id: String, itemIDs: [String]) async throws
    func removeCollectionMembers(id: String, itemIDs: [String]) async throws
    func setCollectionArtwork(id: String, jpeg: Data) async throws

    // MARK: Book reading progress (gated by `capabilities.supportsBookProgressSync`)

    /// Reports EPUB reading position as a 0...1 fraction through the book, so it surfaces
    /// in "Continue" and syncs to other clients. Coarse by design — exact-page resume
    /// stays local; the server holds only the percentage.
    func reportBookProgress(itemID: String, fraction: Double) async throws
    /// Returns the server-side reading fraction (0...1), or nil if none is stored.
    func bookProgress(itemID: String) async throws -> Double?
}

extension MediaProviderSession {
    func collectionCapabilities(id: String?) async throws -> CollectionCapabilities {
        throw unsupportedCollections()
    }

    func collectionPage(startIndex: Int, limit: Int) async throws -> MediaItemPage {
        throw unsupportedCollections()
    }

    func collectionItem(id: String) async throws -> MediaItem {
        throw unsupportedCollections()
    }

    func collectionMembers(id: String, startIndex: Int, limit: Int) async throws -> MediaItemPage {
        throw unsupportedCollections()
    }

    func createCollection(name: String, itemIDs: [String]) async throws -> String {
        throw unsupportedCollections()
    }

    func updateCollection(id: String, name: String, overview: String) async throws {
        throw unsupportedCollections()
    }

    func deleteCollection(id: String) async throws {
        throw unsupportedCollections()
    }

    func addCollectionMembers(id: String, itemIDs: [String]) async throws {
        throw unsupportedCollections()
    }

    func removeCollectionMembers(id: String, itemIDs: [String]) async throws {
        throw unsupportedCollections()
    }

    func setCollectionArtwork(id: String, jpeg: Data) async throws {
        throw unsupportedCollections()
    }

    private func unsupportedCollections() -> GusError {
        GusError.server(String(localized: "This server does not support collections."))
    }

    func mediaLists(kind: ServerMediaListKind) async throws -> [ServerMediaList] {
        throw unsupportedMediaLists()
    }

    func mediaList(id: UUID, kind: ServerMediaListKind) async throws -> ServerMediaList {
        throw unsupportedMediaLists()
    }

    func createMediaList(name: String, kind: ServerMediaListKind, itemIDs: [String]) async throws -> UUID {
        throw unsupportedMediaLists()
    }

    func renameMediaList(id: UUID, kind: ServerMediaListKind, name: String) async throws {
        throw unsupportedMediaLists()
    }

    func deleteMediaList(id: UUID, kind: ServerMediaListKind) async throws {
        throw unsupportedMediaLists()
    }

    func addToMediaList(id: UUID, kind: ServerMediaListKind, itemIDs: [String]) async throws {
        throw unsupportedMediaLists()
    }

    func removeFromMediaList(id: UUID, kind: ServerMediaListKind, entryIDs: [UUID]) async throws {
        throw unsupportedMediaLists()
    }

    func moveMediaListEntry(id: UUID, entryID: UUID, to index: Int) async throws {
        throw unsupportedMediaLists()
    }

    private func unsupportedMediaLists() -> GusError {
        GusError.server(String(localized: "This server does not support playlists.", comment: "Unsupported native media lists"))
    }

    /// Fallback for providers without server pagination. Request the prefix needed
    /// by this page so compatibility does not introduce a hidden fixed ceiling.
    func resumeItemsPage(startIndex: Int, limit: Int) async throws -> MediaItemPage {
        let items = try await resumeItems(limit: startIndex + limit)
        return MediaItemPage(items: Array(items.dropFirst(startIndex).prefix(limit)), totalRecordCount: items.count < startIndex + limit ? items.count : nil)
    }

    func nextUpItemsPage(startIndex: Int, limit: Int) async throws -> MediaItemPage {
        let items = try await nextUpItems(seriesID: nil, limit: startIndex + limit)
        return MediaItemPage(items: Array(items.dropFirst(startIndex).prefix(limit)), totalRecordCount: items.count < startIndex + limit ? items.count : nil)
    }

    func artworkURLs(for item: MediaItem, maxWidth: Int) -> [URL] {
        ArtworkRequestSequence.unique([backdropImageURL(for: item, maxWidth: maxWidth), primaryImageURL(for: item, maxWidth: maxWidth)].compactMap { $0 })
    }

    func updatePlaybackPosition(itemID: String, positionTicks: Int) async throws {
        throw GusError.server(String(localized: "This server does not support saved playback progress.", comment: "Unsupported offline progress sync"))
    }
}
