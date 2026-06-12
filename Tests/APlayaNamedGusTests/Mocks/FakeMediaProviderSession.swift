import Foundation
@testable import Gus

/// A minimal `MediaProviderSession` stand-in for unit tests that need a provider
/// without a live Jellyfin connection. Responses are empty no-ops; override individual
/// methods in a subclass when a test needs specific behaviour.
@MainActor
final class FakeMediaProviderSession: MediaProviderSession {
    let providerKind: MediaProviderKind = .jellyfin
    let capabilities: ProviderCapabilities
    var downloadSourceCallCount = 0

    init(capabilities: ProviderCapabilities) {
        self.capabilities = capabilities
    }

    func userViews() async throws -> [MediaItem] {
        []
    }

    func resumeItems(limit: Int) async throws -> [MediaItem] {
        []
    }

    func nextUpItems(seriesID: String?, limit: Int) async throws -> [MediaItem] {
        []
    }

    func latestMedia(in library: MediaItem, limit: Int) async throws -> [MediaItem] {
        []
    }

    func items(query: MediaItemQuery) async throws -> MediaItemPage {
        MediaItemPage(items: [], totalRecordCount: 0)
    }

    func item(id: String) async throws -> MediaItem {
        MediaItem(id: id)
    }

    func similarItems(itemID: String, limit: Int) async throws -> [MediaItem] {
        []
    }

    func specialFeatures(itemID: String) async throws -> [MediaItem] {
        []
    }

    func seasons(seriesID: String) async throws -> [MediaItem] {
        []
    }

    func episodes(seriesID: String, seasonID: String, limit: Int) async throws -> MediaItemPage {
        MediaItemPage(items: [], totalRecordCount: 0)
    }

    func primaryImageURL(for item: MediaItem, context: ImageURLBuilder.ImageContext) -> URL? {
        nil
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
        PlaybackSourceResolution(
            url: URL(string: "https://example.com/video.mp4")!,
            playSessionID: nil,
            mediaSourceID: nil,
            playMethod: .directPlay,
            stereoLayout: .none,
            stereoFallbackReason: nil
        )
    }

    func resolveAudioPlayback(for itemID: String) async throws -> PlaybackSourceResolution {
        PlaybackSourceResolution(
            url: URL(string: "https://example.com/audio.mp3")!,
            playSessionID: nil,
            mediaSourceID: nil,
            playMethod: .directStream,
            stereoLayout: .none,
            stereoFallbackReason: nil
        )
    }

    func liveTVIsEnabled() async -> Bool {
        false
    }

    func liveTVChannels(startIndex: Int, limit: Int) async throws -> MediaItemPage {
        MediaItemPage(items: [], totalRecordCount: 0)
    }

    func liveTVRecordings(limit: Int) async throws -> [MediaItem] {
        []
    }

    func liveTVTimers() async throws -> [LiveTVTimer] {
        []
    }

    func cancelLiveTVTimer(id: String) async throws {}

    func downloadSource(for item: MediaItem) async throws -> DownloadSourceResolution {
        downloadSourceCallCount += 1
        return DownloadSourceResolution(
            url: URL(string: "https://example.com/download.mp4")!,
            fileExtension: "mp4",
            requiresTranscoding: false
        )
    }

    func toggleWatched(itemID: String, currentlyWatched: Bool) async throws {}

    func toggleFavorite(itemID: String, currentlyFavorite: Bool) async throws {}

    func reportPlaybackStart(context: PlaybackReportContext, positionTicks: Int, isPaused: Bool) async throws {}

    func reportPlaybackProgress(context: PlaybackReportContext, positionTicks: Int, isPaused: Bool) async throws {}

    func reportPlaybackStopped(context: PlaybackReportContext, positionTicks: Int) async throws {}

    var reportedBookProgress: (itemID: String, fraction: Double)?
    var storedBookProgress: Double?

    func reportBookProgress(itemID: String, fraction: Double) async throws {
        reportedBookProgress = (itemID, fraction)
    }

    func bookProgress(itemID: String) async throws -> Double? {
        storedBookProgress
    }
}
