import Foundation
import JellyfinAPI
import OSLog

/// Resolves a playable URL for an item using pure AVKit + Jellyfin server transcoding.
///
/// Pattern reference: Swiftfin's `MediaPlayerItem+Build.streamURL`. Gus biases the
/// `DeviceProfile` toward **HLS transcoding** so `AVPlayer` is handed an `.m3u8` it can
/// always play, while still allowing direct play of AVKit-native containers (mp4/mov/m4v).
struct StreamURLBuilder {
    struct Resolution {
        let url: URL
        let playSessionID: String?
        let mediaSourceID: String?
        /// True when the server returned a transcoding (HLS) URL rather than a direct file.
        let isTranscoding: Bool
    }

    enum StreamError: LocalizedError {
        case noMediaSource
        case noURL

        var errorDescription: String? {
            switch self {
            case .noMediaSource:
                return String(localized: "The server returned no playable media source.", comment: "Playback error: no media source")
            case .noURL:
                return String(localized: "Could not build a playable URL for this item.", comment: "Playback error: URL build failed")
            }
        }
    }

    let client: JellyfinClient
    let userID: String

    private let logger = Logger(category: .stream)

    func resolvePlayback(for itemID: String, maxStreamingBitrate: Int = 120_000_000) async throws -> Resolution {
        let body = PlaybackInfoDto(
            deviceProfile: Self.avPlayerProfile(maxStreamingBitrate: maxStreamingBitrate),
            enableDirectPlay: true,
            enableDirectStream: true,
            enableTranscoding: true,
            maxStreamingBitrate: maxStreamingBitrate,
            userID: userID
        )

        let request = Paths.getPostedPlaybackInfo(
            itemID: itemID,
            parameters: .init(userID: userID, maxStreamingBitrate: maxStreamingBitrate),
            body
        )

        let response = try await client.send(request).value

        guard let source = response.mediaSources?.first else {
            throw StreamError.noMediaSource
        }

        let playSessionID = response.playSessionID

        // Prefer a server-built transcoding URL (HLS) when present.
        if let transcodingURL = source.transcodingURL, let url = client.url(path: transcodingURL) {
            logger.debug("Resolved HLS transcoding URL for item \(itemID, privacy: .public)")
            return Resolution(
                url: url,
                playSessionID: playSessionID,
                mediaSourceID: source.id,
                isTranscoding: true
            )
        }

        // Otherwise direct-stream the file (AVPlayer-native container).
        let streamParameters = Paths.GetVideoStreamParameters(
            isStatic: true,
            tag: source.eTag,
            playSessionID: playSessionID,
            mediaSourceID: source.id,
            deviceID: DeviceIdentity.deviceID
        )
        let streamRequest = Paths.getVideoStream(itemID: itemID, parameters: streamParameters)

        guard let url = client.url(with: streamRequest, queryAPIKey: true) else {
            throw StreamError.noURL
        }

        logger.debug("Resolved direct-stream URL for item \(itemID, privacy: .public)")
        return Resolution(
            url: url,
            playSessionID: playSessionID,
            mediaSourceID: source.id,
            isTranscoding: false
        )
    }

    // MARK: - Device profile

    /// A minimal AVKit-friendly profile: direct-play common containers, otherwise
    /// transcode to H.264/AAC HLS, which `AVPlayer` reliably handles on every platform.
    static func avPlayerProfile(maxStreamingBitrate: Int) -> DeviceProfile {
        let directPlay = [
            DirectPlayProfile(
                audioCodec: "aac,mp3,ac3,eac3,alac,flac",
                container: "mp4,m4v,mov",
                type: .video,
                videoCodec: "h264,hevc"
            ),
        ]

        let transcoding = [
            TranscodingProfile(
                protocol: .hls,
                audioCodec: "aac",
                container: "ts",
                context: .streaming,
                enableMpegtsM2TsMode: true,
                maxAudioChannels: "2",
                minSegments: 2,
                type: .video,
                videoCodec: "h264,hevc"
            ),
        ]

        return DeviceProfile(
            directPlayProfiles: directPlay,
            maxStaticBitrate: maxStreamingBitrate,
            maxStreamingBitrate: maxStreamingBitrate,
            name: DeviceIdentity.clientName,
            transcodingProfiles: transcoding
        )
    }
}
