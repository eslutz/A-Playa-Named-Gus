import Foundation

struct MediaItemPage {
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

    var isTranscoding: Bool {
        playMethod == .transcode
    }
}

struct DownloadSourceResolution {
    var url: URL
    var fileExtension: String
    var requiresTranscoding: Bool
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
protocol MediaProviderSession: AnyObject {
    var providerKind: MediaProviderKind { get }
    var capabilities: ProviderCapabilities { get }

    func userViews() async throws -> [MediaItem]
    func resumeItems(limit: Int) async throws -> [MediaItem]
    func nextUpItems(seriesID: String?, limit: Int) async throws -> [MediaItem]
    func latestMedia(in library: MediaItem, limit: Int) async throws -> [MediaItem]
    func items(query: MediaItemQuery) async throws -> MediaItemPage
    func item(id: String) async throws -> MediaItem
    func similarItems(itemID: String, limit: Int) async throws -> [MediaItem]
    func specialFeatures(itemID: String) async throws -> [MediaItem]
    func seasons(seriesID: String) async throws -> [MediaItem]
    func episodes(seriesID: String, seasonID: String, limit: Int) async throws -> [MediaItem]

    func primaryImageURL(for item: MediaItem, context: ImageURLBuilder.ImageContext) -> URL?
    func primaryImageURL(for item: MediaItem, maxWidth: Int) -> URL?
    func backdropImageURL(for item: MediaItem, context: ImageURLBuilder.ImageContext) -> URL?
    func backdropImageURL(for item: MediaItem, maxWidth: Int) -> URL?
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

    func reportPlaybackStart(context: PlaybackReportContext, positionTicks: Int, isPaused: Bool) async throws
    func reportPlaybackProgress(context: PlaybackReportContext, positionTicks: Int, isPaused: Bool) async throws
    func reportPlaybackStopped(context: PlaybackReportContext, positionTicks: Int) async throws

    // MARK: Book reading progress (gated by `capabilities.supportsBookProgressSync`)

    /// Reports EPUB reading position as a 0...1 fraction through the book, so it surfaces
    /// in "Continue" and syncs to other clients. Coarse by design — exact-page resume
    /// stays local; the server holds only the percentage.
    func reportBookProgress(itemID: String, fraction: Double) async throws
    /// Returns the server-side reading fraction (0...1), or nil if none is stored.
    func bookProgress(itemID: String) async throws -> Double?
}
