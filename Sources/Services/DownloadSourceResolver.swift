import Foundation

// Get is jellyfin-sdk-swift's transport package. JellyfinAPI does not re-export Request<T>,
// and Paths.* functions return Request<T> values whose URL is relative to the client's base
// URL — so the type cannot be removed without abandoning the Paths namespace entirely.
// This is the only file in Gus that requires a direct Get import. See ADR 0011.
import Get
import JellyfinAPI

struct DownloadSourceResolver {
    enum SourceKind: String, Codable, Equatable {
        case original
        case remuxed
        case transcoded
    }

    struct Source {
        let kind: SourceKind
        let request: Request<Data>
        let fileExtension: String
    }

    enum ResolverError: LocalizedError {
        case missingItemID
        case notDownloadable
        case noMediaSource
        case missingMediaSourceID

        var errorDescription: String? {
            switch self {
            case .missingItemID:
                return String(localized: "This item cannot be downloaded because it is missing a media id.", comment: "Download source resolver missing item id")
            case .notDownloadable:
                return String(localized: "This item is not available for download.", comment: "Download unavailable message")
            case .noMediaSource:
                return String(localized: "The server returned no downloadable media source.", comment: "Download source resolver no media source")
            case .missingMediaSourceID:
                return String(localized: "The server returned a media source that cannot be downloaded.", comment: "Download source resolver missing media source id")
            }
        }
    }

    let client: JellyfinClient
    let userID: String

    func resolve(for item: MediaItem) async throws -> Source {
        if let source = try Self.metadataResolvedSource(for: item, userID: userID) {
            return source
        }

        // Video needing a server transcode: ask the server for the media source.
        guard let itemID = item.id else { throw ResolverError.missingItemID }
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(playbackInfoRequest(itemID: itemID)).value
        }
        guard let source = response.mediaSources?.first else { throw ResolverError.noMediaSource }
        return try Self.convertedSource(itemID: itemID, source: JellyfinMediaItemMapper.mediaSource(from: source))
    }

    /// Synchronous resolution from item metadata only (no network round-trip); video
    /// transcodes fall back to the item's own media-source list.
    static func localSource(for item: MediaItem, capabilities: DevicePlaybackCapabilities = .current) throws -> Source {
        if let source = try metadataResolvedSource(for: item, userID: nil, capabilities: capabilities) {
            return source
        }

        guard let itemID = item.id else { throw ResolverError.missingItemID }
        if let source = item.mediaSources.first {
            return try convertedSource(itemID: itemID, source: source, capabilities: capabilities)
        }

        throw ResolverError.noMediaSource
    }

    /// The shared, metadata-only cases: AVPlayer-native originals, book originals, and
    /// audio via the universal endpoint. Returns nil when a video transcode is needed.
    private static func metadataResolvedSource(for item: MediaItem, userID: String?, capabilities: DevicePlaybackCapabilities = .current) throws -> Source? {
        guard let itemID = item.id else { throw ResolverError.missingItemID }
        guard item.canDownload == true else { throw ResolverError.notDownloadable }

        // GetDownload serves the primary source, so an alternate playable source
        // cannot make downloading the primary original safe.
        if let source = item.mediaSources.first, OfflineDownloadEligibility.isAVPlayerPlayable(source, capabilities: capabilities) {
            return Source(
                kind: .original,
                request: Paths.getDownload(itemID: itemID),
                fileExtension: fileExtension(for: source) ?? "mp4"
            )
        }

        if item.type == .book {
            return bookOriginalSource(itemID: itemID, item: item)
        }

        if item.isAudioPlayable {
            return audioTranscodedSource(itemID: itemID, userID: userID)
        }

        return nil
    }

    /// Books always download the original file — there is no server transcode for
    /// epub/pdf, and the original is what Apple Books and the in-app reader consume.
    static func bookOriginalSource(itemID: String, item: MediaItem) -> Source {
        let knownBookExtensions: Set<String> = ["epub", "pdf", "azw3", "mobi", "cbz", "cbr"]
        let containerExtension = item.mediaSources.first?.container?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .first { knownBookExtensions.contains($0) }
        return Source(
            kind: .original,
            request: Paths.getDownload(itemID: itemID),
            fileExtension: containerExtension ?? "epub"
        )
    }

    /// Songs/audiobooks that aren't AVPlayer-native download as a progressive MP3
    /// through the universal audio endpoint instead of the video transcode path.
    static func audioTranscodedSource(itemID: String, userID: String?) -> Source {
        let parameters = Paths.GetUniversalAudioStreamParameters(
            container: Array(OfflineDownloadEligibility.playableAudioContainers),
            deviceID: DeviceIdentity.deviceID,
            userID: userID,
            transcodingContainer: "mp3",
            transcodingProtocol: .http
        )
        return Source(
            kind: .transcoded,
            request: Paths.getUniversalAudioStream(itemID: itemID, parameters: parameters),
            fileExtension: "mp3"
        )
    }

    /// Copy compatible streams independently; changing an MKV container alone must
    /// not force video encoding, stereo downmixing, or a resolution reduction.
    static func convertedSource(itemID: String, source: MediaSource, capabilities: DevicePlaybackCapabilities = .current) throws -> Source {
        guard let mediaSourceID = source.id else { throw ResolverError.missingMediaSourceID }
        let videos = source.mediaStreams.filter { $0.type == .video }
        let audios = source.mediaStreams.filter { $0.type == .audio }
        let video = videos.first(where: { $0.isDefault == true }) ?? videos.first
        let audio = audios.first(where: { $0.isDefault == true }) ?? audios.first
        let copyVideo = video.map { OfflineDownloadEligibility.isVideoStreamPlayable($0, capabilities: capabilities) } ?? false
        let copyAudio = audio.map { ["aac", "ac3", "eac3", "alac"].contains($0.codec?.lowercased() ?? "") && ($0.channels ?? 2) <= 8 } ?? true
        let videoCodec = copyVideo ? (video?.codec?.lowercased() ?? "h264") : "h264"
        // The file store normalizes Jellyfin's hev1 tag to Apple's hvc1 after the
        // transfer; neither the video nor the audio needs encoding for that repair.
        let container = "mp4"
        let parameters = Paths.GetVideoStreamByContainerParameters(
            isStatic: false,
            mediaSourceID: mediaSourceID,
            deviceID: DeviceIdentity.deviceID,
            audioCodec: copyAudio ? (audio?.codec?.lowercased() ?? "aac") : "aac",
            enableAutoStreamCopy: true,
            allowVideoStreamCopy: copyVideo,
            allowAudioStreamCopy: copyAudio,
            audioBitRate: copyAudio ? nil : 256_000,
            maxAudioChannels: 8,
            maxWidth: video?.width ?? 4096,
            maxHeight: video?.height ?? 4096,
            videoBitRate: copyVideo ? 120_000_000 : 40_000_000,
            subtitleStreamIndex: -1,
            maxVideoBitDepth: videoCodec == "hevc" ? 10 : 8,
            videoCodec: videoCodec,
            audioStreamIndex: audio?.index,
            videoStreamIndex: video?.index,
            context: .streaming
        )
        return Source(
            kind: copyVideo && copyAudio ? .remuxed : .transcoded,
            request: Paths.getVideoStreamByContainer(itemID: itemID, container: container, parameters: parameters),
            fileExtension: container
        )
    }

    private func playbackInfoRequest(itemID: String) -> Request<PlaybackInfoResponse> {
        let body = StreamURLBuilder.playbackInfoBody(
            userID: userID,
            maxStreamingBitrate: 120_000_000,
            streamSelection: .none,
            startTimeTicks: nil
        )
        return Paths.getPostedPlaybackInfo(
            itemID: itemID,
            parameters: StreamURLBuilder.playbackInfoParameters(
                userID: userID,
                maxStreamingBitrate: 120_000_000,
                streamSelection: .none,
                startTimeTicks: nil
            ),
            body
        )
    }

    private static func fileExtension(for source: MediaSource) -> String? {
        source.container?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .first { ["mp4", "m4v", "mov"].contains($0) || OfflineDownloadEligibility.playableAudioContainers.contains($0) }
    }
}
