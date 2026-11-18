import Foundation
@testable import Gus

/// A minimal `MediaProviderSession` stand-in for unit tests that need a provider
/// without a live Jellyfin connection. Responses are empty no-ops; override individual
/// methods in a subclass when a test needs specific behaviour.
@MainActor
final class FakeMediaProviderSession: MediaProviderSession {
    let providerKind: MediaProviderKind = .jellyfin
    let capabilities: ProviderCapabilities
    var collectionCapabilitiesHandler: ((String?) async throws -> CollectionCapabilities)?
    var collectionPageHandler: ((Int, Int) async throws -> MediaItemPage)?
    var collectionItemHandler: ((String) async throws -> MediaItem)?
    var collectionMembersHandler: ((String, Int, Int) async throws -> MediaItemPage)?
    var createCollectionHandler: ((String, [String]) async throws -> String)?
    var editMediaListMetadataHandler: ((EditableMediaList, String?, String?) async throws -> Void)?
    var deleteCollectionHandler: ((String) async throws -> Void)?
    var addCollectionMembersHandler: ((String, [String]) async throws -> Void)?
    var removeCollectionMembersHandler: ((String, [String]) async throws -> Void)?
    var editMediaListCoverHandler: ((EditableMediaList, MediaListCoverEdit) async throws -> Void)?
    var userViewsHandler: (() async throws -> [MediaItem])?
    var resumePageHandler: ((Int, Int) async throws -> MediaItemPage)?
    var nextPageHandler: ((Int, Int) async throws -> MediaItemPage)?
    var latestHandler: ((MediaItem) async throws -> [MediaItem])?
    var itemsHandler: ((MediaItemQuery) async throws -> MediaItemPage)?
    var itemHandler: ((String) async throws -> MediaItem)?
    var similarItemsHandler: ((String) async throws -> [MediaItem])?
    var specialFeaturesHandler: ((String) async throws -> [MediaItem])?
    var episodesHandler: ((String) async throws -> MediaItemPage)?
    var liveTVAvailabilityHandler: (() async throws -> LiveTVAvailability)?
    var liveTVChannelsHandler: ((Int, Int) async throws -> MediaItemPage)?
    var liveTVRecordingsHandler: ((Int, Int) async throws -> MediaItemPage)?
    var liveTVTimersHandler: (() async throws -> [LiveTVTimer])?
    var cancelLiveTVTimerHandler: ((String) async throws -> Void)?
    var seasonsHandler: (() async throws -> [MediaItem])?
    var progressHandler: ((String, Int) async throws -> Void)?
    private(set) var watchedRequests: [(itemID: String, currentlyWatched: Bool)] = []
    private(set) var favoriteRequests: [(itemID: String, currentlyFavorite: Bool)] = []
    var watchedHandler: (() async throws -> Void)?
    var favoriteHandler: (() async throws -> Void)?
    var audioHandler: (() async throws -> PlaybackSourceResolution)?
    var playbackHandler: (() async throws -> PlaybackSourceResolution)?
    var playbackReportHandler: ((String, PlaybackReportContext, Int, Bool) async throws -> Void)?
    private(set) var playbackReports: [(kind: String, context: PlaybackReportContext, position: Int)] = []
    private(set) var releasedPlaybackResources: [PlaybackResource] = []
    private(set) var playbackRequestedSelections: [PlaybackStreamSelection] = []
    /// Long-running native lifecycle probes keep observations bounded between samples.
    func drainPlaybackReports() -> [(kind: String, context: PlaybackReportContext, position: Int)] {
        let result = playbackReports
        playbackReports.removeAll(keepingCapacity: true)
        return result
    }

    var mediaListsHandler: ((ServerMediaListKind) async throws -> [ServerMediaList])?
    var mediaListHandler: ((UUID, ServerMediaListKind) async throws -> ServerMediaList)?
    var createMediaListHandler: ((String, ServerMediaListKind, [String]) async throws -> UUID)?
    var renameMediaListHandler: ((UUID, ServerMediaListKind, String) async throws -> Void)?
    var deleteMediaListHandler: ((UUID, ServerMediaListKind) async throws -> Void)?
    var addToMediaListHandler: ((UUID, ServerMediaListKind, [String]) async throws -> Void)?
    var removeFromMediaListHandler: ((UUID, ServerMediaListKind, [UUID]) async throws -> Void)?
    var moveMediaListEntryHandler: ((UUID, UUID, Int) async throws -> Void)?
    var downloadSourceCallCount = 0
    var playbackResolutionCallCount = 0
    var playbackRequestedStartTicks: [Int?] = []
    var audioResolutionCallCount = 0
    var nextUpCallCount = 0
    var playbackReportCallCount = 0
    var artworkCallCount = 0

    init(capabilities: ProviderCapabilities) {
        self.capabilities = capabilities
    }

    func mediaLists(kind: ServerMediaListKind) async throws -> [ServerMediaList] {
        try await mediaListsHandler?(kind) ?? []
    }

    func mediaList(id: UUID, kind: ServerMediaListKind) async throws -> ServerMediaList {
        guard let mediaListHandler else { throw GusError.notFound }
        return try await mediaListHandler(id, kind)
    }

    func createMediaList(name: String, kind: ServerMediaListKind, itemIDs: [String]) async throws -> UUID {
        guard let createMediaListHandler else { throw GusError.notFound }
        return try await createMediaListHandler(name, kind, itemIDs)
    }

    func renameMediaList(id: UUID, kind: ServerMediaListKind, name: String) async throws {
        try await renameMediaListHandler?(id, kind, name)
    }

    func deleteMediaList(id: UUID, kind: ServerMediaListKind) async throws {
        try await deleteMediaListHandler?(id, kind)
    }

    func addToMediaList(id: UUID, kind: ServerMediaListKind, itemIDs: [String]) async throws {
        try await addToMediaListHandler?(id, kind, itemIDs)
    }

    func removeFromMediaList(id: UUID, kind: ServerMediaListKind, entryIDs: [UUID]) async throws {
        try await removeFromMediaListHandler?(id, kind, entryIDs)
    }

    func moveMediaListEntry(id: UUID, entryID: UUID, to index: Int) async throws {
        try await moveMediaListEntryHandler?(id, entryID, index)
    }

    func updatePlaybackPosition(itemID: String, positionTicks: Int) async throws {
        try await progressHandler?(itemID, positionTicks)
    }

    func collectionCapabilities(id: String?) async throws -> CollectionCapabilities {
        try await collectionCapabilitiesHandler?(id) ?? .init()
    }

    func collectionPage(startIndex: Int, limit: Int) async throws -> MediaItemPage {
        try await collectionPageHandler?(startIndex, limit) ?? .init(items: [], totalRecordCount: 0)
    }

    func collectionItem(id: String) async throws -> MediaItem {
        guard let collectionItemHandler else { throw GusError.notFound }; return try await collectionItemHandler(id)
    }

    func collectionMembers(id: String, startIndex: Int, limit: Int) async throws -> MediaItemPage {
        try await collectionMembersHandler?(id, startIndex, limit) ?? .init(items: [], totalRecordCount: 0)
    }

    func createCollection(name: String, itemIDs: [String]) async throws -> String {
        guard let createCollectionHandler else { throw GusError.notFound }; return try await createCollectionHandler(name, itemIDs)
    }

    func editMediaListMetadata(_ list: EditableMediaList, name: String?, expectedName: String, overview: String?, expectedOverview: String) async throws {
        try await editMediaListMetadataHandler?(list, name, overview)
    }

    func deleteCollection(id: String) async throws {
        try await deleteCollectionHandler?(id)
    }

    func addCollectionMembers(id: String, itemIDs: [String]) async throws {
        try await addCollectionMembersHandler?(id, itemIDs)
    }

    func removeCollectionMembers(id: String, itemIDs: [String]) async throws {
        try await removeCollectionMembersHandler?(id, itemIDs)
    }

    func editMediaListCover(_ list: EditableMediaList, change: MediaListCoverEdit, expectedTag: String?) async throws {
        try await editMediaListCoverHandler?(list, change)
    }

    func userViews() async throws -> [MediaItem] {
        try await userViewsHandler?() ?? []
    }

    func resumeItems(limit: Int) async throws -> [MediaItem] {
        []
    }

    func nextUpItems(seriesID: String?, limit: Int) async throws -> [MediaItem] {
        nextUpCallCount += 1
        return []
    }

    func resumeItemsPage(startIndex: Int, limit: Int) async throws -> MediaItemPage {
        if let resumePageHandler {
            return try await resumePageHandler(startIndex, limit)
        }
        return MediaItemPage(items: [], totalRecordCount: 0)
    }

    func nextUpItemsPage(startIndex: Int, limit: Int) async throws -> MediaItemPage {
        if let nextPageHandler {
            return try await nextPageHandler(startIndex, limit)
        }
        nextUpCallCount += 1
        return MediaItemPage(items: [], totalRecordCount: 0)
    }

    func latestMedia(in library: MediaItem, limit: Int) async throws -> [MediaItem] {
        try await latestHandler?(library) ?? []
    }

    func items(query: MediaItemQuery) async throws -> MediaItemPage {
        if let itemsHandler {
            return try await itemsHandler(query)
        }
        return MediaItemPage(items: [], totalRecordCount: 0)
    }

    func item(id: String) async throws -> MediaItem {
        if let itemHandler {
            return try await itemHandler(id)
        }
        return MediaItem(id: id)
    }

    func similarItems(itemID: String, limit: Int) async throws -> [MediaItem] {
        try await similarItemsHandler?(itemID) ?? []
    }

    func specialFeatures(itemID: String) async throws -> [MediaItem] {
        try await specialFeaturesHandler?(itemID) ?? []
    }

    func seasons(seriesID: String) async throws -> [MediaItem] {
        if let seasonsHandler {
            return try await seasonsHandler()
        }
        return []
    }

    func episodesPage(seriesID: String, seasonID: String, startIndex: Int, limit: Int) async throws -> MediaItemPage {
        if let episodesHandler {
            return try await episodesHandler(seasonID)
        }
        return MediaItemPage(items: [], totalRecordCount: 0)
    }

    func primaryImageURL(for item: MediaItem, context: ImageURLBuilder.ImageContext) -> URL? {
        artworkCallCount += 1
        return nil
    }

    func primaryImageURL(for item: MediaItem, maxWidth: Int) -> URL? {
        nil
    }

    func backdropImageURL(for item: MediaItem, context: ImageURLBuilder.ImageContext) -> URL? {
        nil
    }

    func backdropImageURL(for item: MediaItem, maxWidth: Int) -> URL? {
        nil
    }

    func personImageURL(for person: MediaPerson, maxWidth: Int) -> URL? {
        nil
    }

    func resolvePlayback(
        for itemID: String,
        maxStreamingBitrate: Int,
        streamSelection: PlaybackStreamSelection,
        startTimeTicks: Int?,
        stereoLayout: Stereo3DLayout
    ) async throws -> PlaybackSourceResolution {
        playbackResolutionCallCount += 1
        playbackRequestedStartTicks.append(startTimeTicks)
        playbackRequestedSelections.append(streamSelection)
        if let playbackHandler {
            return try await playbackHandler()
        }
        return PlaybackSourceResolution(
            url: URL(string: "https://example.com/video.mp4")!,
            playSessionID: nil,
            mediaSourceID: nil,
            playMethod: .directPlay,
            stereoLayout: .none,
            stereoFallbackReason: nil
        )
    }

    func releasePlaybackResource(_ resource: PlaybackResource) async throws {
        releasedPlaybackResources.append(resource)
    }

    func resolveAudioPlayback(for itemID: String, streamSelection: PlaybackStreamSelection) async throws -> PlaybackSourceResolution {
        audioResolutionCallCount += 1
        playbackRequestedSelections.append(streamSelection)
        if let audioHandler {
            return try await audioHandler()
        }
        return PlaybackSourceResolution(
            url: URL(string: "https://example.com/audio.mp3")!,
            playSessionID: nil,
            mediaSourceID: nil,
            playMethod: .directStream,
            stereoLayout: .none,
            stereoFallbackReason: nil
        )
    }

    func liveTVAvailability() async throws -> LiveTVAvailability {
        try await liveTVAvailabilityHandler?() ?? .notConfigured
    }

    func liveTVChannels(startIndex: Int, limit: Int) async throws -> MediaItemPage {
        try await liveTVChannelsHandler?(startIndex, limit) ?? MediaItemPage(items: [], totalRecordCount: 0)
    }

    func liveTVRecordingsPage(startIndex: Int, limit: Int) async throws -> MediaItemPage {
        try await liveTVRecordingsHandler?(startIndex, limit) ?? MediaItemPage(items: [], totalRecordCount: 0)
    }

    func liveTVTimers() async throws -> [LiveTVTimer] {
        try await liveTVTimersHandler?() ?? []
    }

    func cancelLiveTVTimer(id: String) async throws {
        try await cancelLiveTVTimerHandler?(id)
    }

    func downloadSource(for item: MediaItem, streamSelection: PlaybackStreamSelection) async throws -> DownloadSourceResolution {
        downloadSourceCallCount += 1
        let sourceID = streamSelection.mediaSourceID ?? item.mediaSources.first?.id
        return DownloadSourceResolution(
            url: URL(string: "https://example.com/download.mp4")!,
            fileExtension: "mp4",
            requiresTranscoding: false,
            mediaSourceID: sourceID,
            estimatedByteCount: item.mediaSources.first { $0.id == sourceID }?.sizeBytes
        )
    }

    func toggleWatched(itemID: String, currentlyWatched: Bool) async throws {
        watchedRequests.append((itemID, currentlyWatched))
        try await watchedHandler?()
    }

    func toggleFavorite(itemID: String, currentlyFavorite: Bool) async throws {
        favoriteRequests.append((itemID, currentlyFavorite))
        try await favoriteHandler?()
    }

    func reportPlaybackStart(context: PlaybackReportContext, positionTicks: Int, isPaused: Bool) async throws {
        playbackReportCallCount += 1
        playbackReports.append(("start", context, positionTicks))
        try await playbackReportHandler?("start", context, positionTicks, isPaused)
    }

    func reportPlaybackProgress(context: PlaybackReportContext, positionTicks: Int, isPaused: Bool) async throws {
        playbackReportCallCount += 1
        playbackReports.append(("progress", context, positionTicks))
        try await playbackReportHandler?("progress", context, positionTicks, isPaused)
    }

    func reportPlaybackStopped(context: PlaybackReportContext, positionTicks: Int) async throws {
        playbackReportCallCount += 1
        playbackReports.append(("stop", context, positionTicks))
        try await playbackReportHandler?("stop", context, positionTicks, false)
    }

    var reportedBookProgress: (itemID: String, fraction: Double)?
    var storedBookProgress: Double?
    var bookProgressCallCount = 0

    func reportBookProgress(itemID: String, fraction: Double) async throws {
        reportedBookProgress = (itemID, fraction)
    }

    func bookProgress(itemID: String) async throws -> Double? {
        bookProgressCallCount += 1
        return storedBookProgress
    }
}
