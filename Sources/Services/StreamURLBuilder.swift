import Foundation
import JellyfinAPI
import OSLog

/// Resolves a playable URL for an item using pure AVKit + Jellyfin server transcoding.
///
/// Pattern reference: Swiftfin's `MediaPlayerItem+Build.streamURL`. Gus biases the
/// `DeviceProfile` toward **HLS transcoding** so `AVPlayer` is handed an `.m3u8` it can
/// always play, while still allowing direct play of AVKit-native containers (mp4/mov/m4v).
struct StreamURLBuilder {
    enum StereoFallbackReason: Equatable {
        case directPlayUnavailable(Stereo3DLayout)
    }

    struct Resolution {
        let url: URL
        let playSessionID: String?
        let mediaSourceID: String?
        /// True when the server returned a transcoding (HLS) URL rather than a direct file.
        let isTranscoding: Bool
        let stereoLayout: Stereo3DLayout
        let stereoFallbackReason: StereoFallbackReason?

        func fallingBackTo2D(from layout: Stereo3DLayout) -> Resolution {
            Resolution(
                url: url,
                playSessionID: playSessionID,
                mediaSourceID: mediaSourceID,
                isTranscoding: isTranscoding,
                stereoLayout: .none,
                stereoFallbackReason: .directPlayUnavailable(layout)
            )
        }
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

    func resolvePlayback(
        for itemID: String,
        maxStreamingBitrate: Int = 120_000_000,
        streamSelection: PlaybackStreamSelection = .none,
        startTimeTicks: Int? = nil,
        stereoLayout: Stereo3DLayout = .none
    ) async throws -> Resolution {
        let body = Self.playbackInfoBody(
            userID: userID,
            maxStreamingBitrate: maxStreamingBitrate,
            streamSelection: streamSelection,
            startTimeTicks: startTimeTicks,
            stereoLayout: stereoLayout
        )

        let request = Paths.getPostedPlaybackInfo(
            itemID: itemID,
            parameters: Self.playbackInfoParameters(
                userID: userID,
                maxStreamingBitrate: maxStreamingBitrate,
                streamSelection: streamSelection,
                startTimeTicks: startTimeTicks
            ),
            body
        )

        let response = try await client.send(request).value

        guard let source = response.mediaSources?.first else {
            if stereoLayout.requiresDirectPlay {
                return try await resolvePlayback(
                    for: itemID,
                    maxStreamingBitrate: maxStreamingBitrate,
                    streamSelection: streamSelection,
                    startTimeTicks: startTimeTicks,
                    stereoLayout: .none
                )
                .fallingBackTo2D(from: stereoLayout)
            }
            throw StreamError.noMediaSource
        }

        let playSessionID = response.playSessionID

        if stereoLayout.requiresDirectPlay, source.isSupportsDirectPlay == false {
            return try await resolvePlayback(
                for: itemID,
                maxStreamingBitrate: maxStreamingBitrate,
                streamSelection: streamSelection,
                startTimeTicks: startTimeTicks,
                stereoLayout: .none
            )
            .fallingBackTo2D(from: stereoLayout)
        }

        // Prefer a server-built transcoding URL (HLS) when present for ordinary 2D playback.
        if !stereoLayout.requiresDirectPlay, let transcodingURL = source.transcodingURL, let url = client.url(path: transcodingURL) {
            logger.debug("Resolved HLS transcoding URL for item \(itemID, privacy: .public)")
            return Resolution(
                url: url,
                playSessionID: playSessionID,
                mediaSourceID: source.id,
                isTranscoding: true,
                stereoLayout: .none,
                stereoFallbackReason: nil
            )
        }

        // Otherwise direct-stream the file (AVPlayer-native container).
        let streamParameters = Paths.GetVideoStreamParameters(
            isStatic: true,
            tag: source.eTag,
            playSessionID: playSessionID,
            mediaSourceID: source.id,
            deviceID: DeviceIdentity.deviceID,
            subtitleStreamIndex: streamSelection.subtitleStreamIndex,
            audioStreamIndex: streamSelection.audioStreamIndex
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
            isTranscoding: false,
            stereoLayout: stereoLayout,
            stereoFallbackReason: nil
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

    static func directPlayOnlyProfile(maxStreamingBitrate: Int) -> DeviceProfile {
        var profile = avPlayerProfile(maxStreamingBitrate: maxStreamingBitrate)
        profile.transcodingProfiles = []
        return profile
    }

    static func playbackInfoBody(
        userID: String,
        maxStreamingBitrate: Int,
        streamSelection: PlaybackStreamSelection,
        startTimeTicks: Int?,
        stereoLayout: Stereo3DLayout = .none
    ) -> PlaybackInfoDto {
        let requiresDirectPlay = stereoLayout.requiresDirectPlay
        return PlaybackInfoDto(
            audioStreamIndex: streamSelection.audioStreamIndex,
            deviceProfile: requiresDirectPlay
                ? directPlayOnlyProfile(maxStreamingBitrate: maxStreamingBitrate)
                : avPlayerProfile(maxStreamingBitrate: maxStreamingBitrate),
            enableDirectPlay: true,
            enableDirectStream: true,
            enableTranscoding: !requiresDirectPlay,
            maxStreamingBitrate: maxStreamingBitrate,
            startTimeTicks: startTimeTicks,
            subtitleStreamIndex: streamSelection.subtitleStreamIndex,
            userID: userID
        )
    }

    static func playbackInfoParameters(
        userID: String,
        maxStreamingBitrate: Int,
        streamSelection: PlaybackStreamSelection,
        startTimeTicks: Int?
    ) -> Paths.GetPostedPlaybackInfoParameters {
        Paths.GetPostedPlaybackInfoParameters(
            userID: userID,
            maxStreamingBitrate: maxStreamingBitrate,
            startTimeTicks: startTimeTicks,
            audioStreamIndex: streamSelection.audioStreamIndex,
            subtitleStreamIndex: streamSelection.subtitleStreamIndex
        )
    }
}
