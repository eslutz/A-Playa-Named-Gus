import Foundation

struct MediaItemPage: Sendable {
    var items: [MediaItem]
    var totalRecordCount: Int?
}

struct MediaItemQuery: Sendable {
    var parentID: String?
    var searchTerm: String?
    /// Restricts results to albums by this artist (provider-mapped, e.g. Jellyfin `artistIds`).
    var artistID: String?
    var genreID: String?
    var studioID: String?
    var personID: String?
    /// Restricts results to these item types (provider-mapped, e.g. Jellyfin `includeItemTypes`).
    var includeTypes: [MediaItemType]?
    var startIndex: Int
    var limit: Int
    var isRecursive: Bool
    var sort: MediaItemSort?
    var statusFilter: MediaItemStatusFilter
    /// Catalog scans do not need chapters or stream metadata for every title.
    var isBookCatalog = false

    init(
        parentID: String? = nil,
        searchTerm: String? = nil,
        artistID: String? = nil,
        genreID: String? = nil,
        studioID: String? = nil,
        personID: String? = nil,
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
        self.genreID = genreID
        self.studioID = studioID
        self.personID = personID
        self.includeTypes = includeTypes
        self.startIndex = startIndex
        self.limit = limit
        self.isRecursive = isRecursive
        self.sort = sort
        self.statusFilter = statusFilter
    }
}

struct PlaybackSourceResolution: Sendable {
    var url: URL
    var playSessionID: String?
    var mediaSourceID: String?
    var playMethod: MediaPlaybackMethod
    var stereoLayout: Stereo3DLayout
    var stereoFallbackReason: StreamURLBuilder.StereoFallbackReason?
    var mediaSource: MediaSource? = nil
    var resource: PlaybackResource? = nil
    var isLive = false

    var isTranscoding: Bool {
        playMethod == .transcode
    }
}

/// Opaque server allocation owned by one negotiated playback generation.
struct PlaybackResource: Hashable, Sendable {
    let liveStreamID: String?
    let playSessionID: String?
    var isTranscoding = false
}

struct DownloadSourceResolution {
    var url: URL
    var fileExtension: String
    var requiresTranscoding: Bool
    var operation: DownloadActivity.SourceOperation? = nil
    var mediaSourceID: String? = nil
    var estimatedByteCount: Int64? = nil
}

struct PlaybackReportContext: Sendable {
    let itemID: String
    let mediaSourceID: String?
    let playSessionID: String?
    let playMethod: MediaPlaybackMethod
    var streamSelection: PlaybackStreamSelection
    var reportID = UUID()
    var liveStreamID: String? = nil
    var canSeek = false
    var isFailed = false
}

enum LiveTVAvailability: Equatable, Sendable {
    case enabled, notConfigured, restricted
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
    func resolveRelatedSearch(_ target: RelatedSearch) async throws -> RelatedSearch?
    func item(id: String) async throws -> MediaItem
    func similarItems(itemID: String, limit: Int) async throws -> [MediaItem]
    func specialFeatures(itemID: String) async throws -> [MediaItem]
    func seasons(seriesID: String) async throws -> [MediaItem]
    func episodesPage(seriesID: String, seasonID: String, startIndex: Int, limit: Int) async throws -> MediaItemPage

    func primaryImageURL(for item: MediaItem, context: ImageURLBuilder.ImageContext) -> URL?
    func primaryImageURL(for item: MediaItem, maxWidth: Int) -> URL?
    func backdropImageURL(for item: MediaItem, context: ImageURLBuilder.ImageContext) -> URL?
    func backdropImageURL(for item: MediaItem, maxWidth: Int) -> URL?
    func artworkURLs(for item: MediaItem, request: MediaArtworkRequest) -> [URL]
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
    func resolveAudioPlayback(for itemID: String, streamSelection: PlaybackStreamSelection) async throws -> PlaybackSourceResolution
    /// Releases an allocated resource that has not been handed to terminal
    /// reporting. Live-stream Stop owns its consumer release; repeating a raw
    /// Close after an ambiguous Stop response can close another consumer.
    func releasePlaybackResource(_ resource: PlaybackResource) async throws

    /// Returns an authenticated temporary original. The caller owns moving or removing it.
    func downloadBook(for item: MediaItem) async throws -> (file: URL, filename: String)
    func downloadSource(for item: MediaItem, streamSelection: PlaybackStreamSelection) async throws -> DownloadSourceResolution

    // MARK: Live TV (no-tuner servers report unavailable)

    func liveTVAvailability() async throws -> LiveTVAvailability
    func liveTVChannels(startIndex: Int, limit: Int) async throws -> MediaItemPage
    func liveTVRecordingsPage(startIndex: Int, limit: Int) async throws -> MediaItemPage
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
    func canEditMediaListMetadata(_ list: EditableMediaList) async throws -> Bool
    func canEditMediaListCover(_ list: EditableMediaList) async throws -> Bool
    func editMediaListMetadata(_ list: EditableMediaList, name: String?, expectedName: String, overview: String?, expectedOverview: String) async throws
    func editMediaListCover(_ list: EditableMediaList, change: MediaListCoverEdit, expectedTag: String?) async throws

    // MARK: Library collections

    func collectionCapabilities(id: String?) async throws -> CollectionCapabilities
    func collectionPage(startIndex: Int, limit: Int) async throws -> MediaItemPage
    func collectionItem(id: String) async throws -> MediaItem
    func collectionMembers(id: String, startIndex: Int, limit: Int) async throws -> MediaItemPage
    func createCollection(name: String, itemIDs: [String]) async throws -> String
    func deleteCollection(id: String) async throws
    func addCollectionMembers(id: String, itemIDs: [String]) async throws
    func removeCollectionMembers(id: String, itemIDs: [String]) async throws

    /// A server-confirmable series metadata edit on an ebook. A collection-management
    /// grant alone does not grant permission to change book metadata.
    func canEditBookSeries() async throws -> Bool
    func setBookSeries(itemID: String, from expectedName: String?, to newName: String?) async throws

    // MARK: Book reading progress (gated by `capabilities.supportsBookProgressSync`)

    /// Reports EPUB reading position as a 0...1 fraction through the book, so it surfaces
    /// in "Continue" and syncs to other clients. Coarse by design — exact-page resume
    /// stays local; the server holds only the percentage.
    func reportBookProgress(itemID: String, fraction: Double) async throws
    /// Returns the server-side reading fraction (0...1), or nil if none is stored.
    func bookProgress(itemID: String) async throws -> Double?
}

extension MediaProviderSession {
    func resolveRelatedSearch(_ target: RelatedSearch) async throws -> RelatedSearch? {
        target.id == nil ? nil : target
    }

    func canEditMediaListMetadata(_ list: EditableMediaList) async throws -> Bool {
        false
    }

    func canEditMediaListCover(_ list: EditableMediaList) async throws -> Bool {
        false
    }

    func editMediaListMetadata(_ list: EditableMediaList, name: String?, expectedName: String, overview: String?, expectedOverview: String) async throws {
        throw GusError.forbidden
    }

    func editMediaListCover(_ list: EditableMediaList, change: MediaListCoverEdit, expectedTag: String?) async throws {
        throw GusError.forbidden
    }

    func releasePlaybackResource(_ resource: PlaybackResource) async throws {}

    func canEditBookSeries() async throws -> Bool {
        false
    }

    func setBookSeries(itemID: String, from expectedName: String?, to newName: String?) async throws {
        throw GusError.forbidden
    }

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

    func deleteCollection(id: String) async throws {
        throw unsupportedCollections()
    }

    func addCollectionMembers(id: String, itemIDs: [String]) async throws {
        throw unsupportedCollections()
    }

    func removeCollectionMembers(id: String, itemIDs: [String]) async throws {
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

    func artworkURLs(for item: MediaItem, request: MediaArtworkRequest) -> [URL] {
        let primary = primaryImageURL(for: item, maxWidth: request.maxWidth)
        let backdrop = backdropImageURL(for: item, maxWidth: request.maxWidth)
        switch request.role {
        case .photo, .avatar: return primary.map { [$0] } ?? []
        case .chapter: return []
        case .poster, .square: return ArtworkRequestSequence.unique([primary, backdrop].compactMap { $0 })
        case .episodeStill, .backdrop, .libraryThumbnail: return ArtworkRequestSequence.unique([backdrop, primary].compactMap { $0 })
        }
    }

    func updatePlaybackPosition(itemID: String, positionTicks: Int) async throws {
        throw GusError.server(String(localized: "This server does not support saved playback progress.", comment: "Unsupported offline progress sync"))
    }
}

/// Paging for complete, ordered item collections such as album queues. Preview
/// shelves retain their own explicit limits. Offsets always count raw server rows.
extension MediaProviderSession {
    func allItems(query: MediaItemQuery) async throws -> [MediaItem] {
        try await MediaPageLoader.collect(pageSize: query.limit) { offset, limit in
            var pageQuery = query
            pageQuery.startIndex = query.startIndex + offset
            pageQuery.limit = limit
            var page = try await self.items(query: pageQuery)
            page.totalRecordCount = page.totalRecordCount.map { max(0, $0 - query.startIndex) }
            return page
        }
    }
}

/// A browsing result belongs to one fixed provider/connection/profile session.
/// Playlist occurrences deliberately do not use this item-identity deduplication.
enum MediaPageLoader {
    /// Omitted totals retain the last server count. An empty page below that
    /// count is a retryable failure, not proof that a full list is complete.
    static func validatedTotal(for page: MediaItemPage, startIndex: Int, previousTotal: Int? = nil) throws -> Int? {
        let total = page.totalRecordCount ?? previousTotal
        if page.items.isEmpty, let total, startIndex < total {
            throw GusError.server(String(localized: "The server returned an incomplete collection. Try again."))
        }
        return total
    }

    static func unique(_ items: [MediaItem], after existing: [MediaItem] = []) -> [MediaItem] {
        struct Identity: Hashable { let provider: MediaProviderKind; let id: String }
        var seen = Set(existing.compactMap { item in item.id.map { Identity(provider: item.providerKind, id: $0) } })
        return items.filter { item in
            guard let id = item.id else { return true }
            return seen.insert(Identity(provider: item.providerKind, id: id)).inserted
        }
    }

    /// Publishes validated nonempty pages for incremental readers; an incomplete
    /// later page throws without replacing the content already presented.
    @MainActor
    static func collect(pageSize: Int = 200, didLoadPage: (([MediaItem]) -> Void)? = nil, page: (Int, Int) async throws -> MediaItemPage) async throws -> [MediaItem] {
        let size = max(1, pageSize)
        var offset = 0
        var items: [MediaItem] = []
        var previousPage: [MediaItem]? = nil
        var advertisedTotal: Int?
        while true {
            try Task.checkCancellation()
            let result = try await page(offset, size)
            try Task.checkCancellation()
            // A server ignoring startIndex must fail visibly, rather than spin
            // forever or silently claim a partial collection is complete.
            if !result.items.isEmpty, result.items == previousPage {
                throw GusError.server(String(localized: "The server did not advance to the next page. Try again."))
            }
            previousPage = result.items
            advertisedTotal = try validatedTotal(for: result, startIndex: offset, previousTotal: advertisedTotal)
            items += unique(result.items, after: items)
            offset += result.items.count
            if result.items.isEmpty {
                break
            }
            didLoadPage?(items)
            if let total = advertisedTotal {
                if offset >= total {
                    break
                }
            } else if result.items.count < size {
                break
            }
        }
        return items
    }
}
