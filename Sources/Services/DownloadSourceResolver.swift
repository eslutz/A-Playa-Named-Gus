import Foundation
import Get
import JellyfinAPI

struct DownloadSourceResolver {
    enum SourceKind: String, Codable, Equatable {
        case original
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
        if let original = try Self.originalSource(for: item) {
            return original
        }

        guard let itemID = item.id else { throw ResolverError.missingItemID }
        guard item.canDownload == true else { throw ResolverError.notDownloadable }

        let response = try await client.send(playbackInfoRequest(itemID: itemID)).value
        guard let source = response.mediaSources?.first else { throw ResolverError.noMediaSource }
        guard let mediaSourceID = source.id else { throw ResolverError.missingMediaSourceID }
        return Self.transcodedSource(itemID: itemID, mediaSourceID: mediaSourceID)
    }

    static func localSource(for item: MediaItem) throws -> Source {
        if let original = try originalSource(for: item) {
            return original
        }

        guard let itemID = item.id else { throw ResolverError.missingItemID }
        guard item.canDownload == true else { throw ResolverError.notDownloadable }

        if let source = item.mediaSources.first,
           let mediaSourceID = source.id
        {
            return transcodedSource(itemID: itemID, mediaSourceID: mediaSourceID)
        }

        throw ResolverError.noMediaSource
    }

    private static func originalSource(for item: MediaItem) throws -> Source? {
        guard let itemID = item.id else { throw ResolverError.missingItemID }
        guard item.canDownload == true else { throw ResolverError.notDownloadable }

        if let source = item.mediaSources.first(where: OfflineDownloadEligibility.isAVPlayerPlayable) {
            return Source(
                kind: .original,
                request: Paths.getDownload(itemID: itemID),
                fileExtension: fileExtension(for: source) ?? "mp4"
            )
        }

        return nil
    }

    static func transcodedSource(itemID: String, mediaSourceID: String) -> Source {
        let parameters = Paths.GetVideoStreamByContainerParameters(
            isStatic: false,
            mediaSourceID: mediaSourceID,
            deviceID: DeviceIdentity.deviceID,
            audioCodec: "aac",
            enableAutoStreamCopy: false,
            allowVideoStreamCopy: false,
            allowAudioStreamCopy: false,
            maxAudioChannels: 2,
            maxVideoBitDepth: 8,
            videoCodec: "h264",
            context: .streaming
        )
        return Source(
            kind: .transcoded,
            request: Paths.getVideoStreamByContainer(itemID: itemID, container: "mp4", parameters: parameters),
            fileExtension: "mp4"
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
            .first { ["mp4", "m4v", "mov"].contains($0) }
    }
}
