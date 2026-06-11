import AVFoundation
import Foundation
import JellyfinAPI
import OSLog
#if canImport(VideoToolbox)
    import VideoToolbox
#endif

/// What this device's hardware can actually decode and display.
///
/// Direct play is declared only for codecs the device handles natively — an honest
/// profile lets compatible files play untouched while anything questionable goes to the
/// server transcoder, instead of failing in `AVPlayer` at play time. Injectable so the
/// profile builder is deterministic under test.
struct DevicePlaybackCapabilities {
    var supportsHEVCDecode: Bool
    var supportsAV1Decode: Bool
    var supportsHDRPlayback: Bool

    static let current: DevicePlaybackCapabilities = {
        #if canImport(VideoToolbox)
            let hevc = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
            let av1 = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        #else
            // watchOS has no VideoToolbox; constrained playback sticks to H.264.
            let hevc = false
            let av1 = false
        #endif
        #if os(watchOS)
            let hdr = false
        #else
            let hdr = AVPlayer.eligibleForHDRPlayback
        #endif
        return DevicePlaybackCapabilities(
            supportsHEVCDecode: hevc,
            supportsAV1Decode: av1,
            supportsHDRPlayback: hdr
        )
    }()
}

/// Resolves a playable URL for an item using pure AVKit + Jellyfin server transcoding.
///
/// Pattern reference: Swiftfin's `MediaPlayerItem+Build.streamURL`. The `DeviceProfile`
/// leans **direct play** for everything this device's hardware genuinely decodes
/// (gated via VideoToolbox/HDR eligibility), and falls back to server-side HLS/fMP4
/// transcoding — HEVC-preferred, surround preserved, text subtitles in the manifest —
/// only when the source needs it.
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

        // The server negotiates the play method against the device profile: it returns a
        // transcoding URL only when the source genuinely needs server-side work for this
        // device/selection. Absent one, the file direct-streams below.
        if !stereoLayout.requiresDirectPlay, let transcodingURL = source.transcodingURL, let url = authenticatedPlaybackURL(path: transcodingURL) {
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

    /// An AVKit-honest profile: direct-play every container/codec combination this
    /// device's hardware decodes, otherwise transcode to HLS with fMP4 segments —
    /// HEVC-preferred where supported, up to 7.1 audio (AVFoundation downmixes for the
    /// active output), and text subtitles delivered in the manifest instead of burned in.
    static func avPlayerProfile(
        maxStreamingBitrate: Int,
        capabilities: DevicePlaybackCapabilities = .current
    ) -> DeviceProfile {
        DeviceProfile(
            codecProfiles: codecProfiles(capabilities: capabilities),
            directPlayProfiles: directPlayProfiles(capabilities: capabilities),
            maxStaticBitrate: maxStreamingBitrate,
            maxStreamingBitrate: maxStreamingBitrate,
            name: DeviceIdentity.clientName,
            subtitleProfiles: subtitleProfiles(),
            transcodingProfiles: [hlsTranscodingProfile(capabilities: capabilities)]
        )
    }

    private static func directPlayProfiles(capabilities: DevicePlaybackCapabilities) -> [DirectPlayProfile] {
        var mp4Video = ["h264"]
        if capabilities.supportsHEVCDecode { mp4Video.append("hevc") }
        if capabilities.supportsAV1Decode { mp4Video.append("av1") }

        var tsVideo = ["h264"]
        if capabilities.supportsHEVCDecode { tsVideo.append("hevc") }

        return [
            DirectPlayProfile(
                audioCodec: "aac,mp3,ac3,eac3,alac,flac",
                container: "mp4,m4v,mov",
                type: .video,
                videoCodec: mp4Video.joined(separator: ",")
            ),
            // Live TV and PVR recordings commonly arrive as transport streams.
            DirectPlayProfile(
                audioCodec: "aac,mp3,ac3,eac3",
                container: "ts,mpegts",
                type: .video,
                videoCodec: tsVideo.joined(separator: ",")
            ),
        ]
    }

    /// Constraints that route AVFoundation-incompatible variants of otherwise
    /// direct-playable codecs (Hi10P H.264, interlaced video, 12-bit HEVC, HDR on
    /// non-HDR displays) to the server transcoder instead of failing at play time.
    private static func codecProfiles(capabilities: DevicePlaybackCapabilities) -> [CodecProfile] {
        let hevcRanges = capabilities.supportsHDRPlayback
            ? "SDR|HDR10|HLG|DOVIWithHDR10|DOVIWithHLG|DOVIWithSDR"
            : "SDR"

        return [
            CodecProfile(
                codec: "h264",
                conditions: [
                    ProfileCondition(condition: .lessThanEqual, isRequired: false, property: .videoBitDepth, value: "8"),
                    ProfileCondition(condition: .notEquals, isRequired: false, property: .isInterlaced, value: "true"),
                ],
                type: .video
            ),
            CodecProfile(
                codec: "hevc",
                conditions: [
                    ProfileCondition(condition: .lessThanEqual, isRequired: false, property: .videoBitDepth, value: "10"),
                    ProfileCondition(condition: .equalsAny, isRequired: false, property: .videoRangeType, value: hevcRanges),
                ],
                type: .video
            ),
        ]
    }

    /// Text subtitles ride the HLS manifest (the server converts SRT/ASS/etc. to VTT
    /// segments); embedded TTML/CC pass through; bitmap formats burn in — the only
    /// delivery `AVPlayer` can render for them.
    private static func subtitleProfiles() -> [SubtitleProfile] {
        [
            SubtitleProfile(format: "vtt", method: .hls),
            SubtitleProfile(format: "webvtt", method: .hls),
            SubtitleProfile(format: "ttml", method: .embed),
            SubtitleProfile(format: "cc_dec", method: .embed),
            SubtitleProfile(format: "pgssub", method: .encode),
            SubtitleProfile(format: "dvbsub", method: .encode),
            SubtitleProfile(format: "dvdsub", method: .encode),
            SubtitleProfile(format: "xsub", method: .encode),
        ]
    }

    private static func hlsTranscodingProfile(capabilities: DevicePlaybackCapabilities) -> TranscodingProfile {
        TranscodingProfile(
            protocol: .hls,
            // Listing AC3/EAC3/FLAC/ALAC lets the server copy those streams into the
            // transcode untouched; otherwise audio re-encodes to AAC.
            audioCodec: "aac,ac3,eac3,alac,flac",
            container: "mp4",
            context: .streaming,
            enableSubtitlesInManifest: true,
            isBreakOnNonKeyFrames: true,
            maxAudioChannels: "8",
            minSegments: 2,
            type: .video,
            videoCodec: capabilities.supportsHEVCDecode ? "hevc,h264" : "h264"
        )
    }

    static func directPlayOnlyProfile(
        maxStreamingBitrate: Int,
        capabilities: DevicePlaybackCapabilities = .current
    ) -> DeviceProfile {
        var profile = avPlayerProfile(maxStreamingBitrate: maxStreamingBitrate, capabilities: capabilities)
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

    /// Builds an authenticated `/Audio/{id}/universal` URL. The endpoint direct-plays
    /// AVPlayer-native audio containers and transparently transcodes everything else,
    /// so `AVPlayer` always receives playable audio.
    func universalAudioURL(for itemID: String) throws -> URL {
        let parameters = Paths.GetUniversalAudioStreamParameters(
            container: ["mp3", "aac", "m4a", "m4b", "flac", "alac", "wav"],
            deviceID: DeviceIdentity.deviceID,
            userID: userID,
            maxStreamingBitrate: 12_000_000,
            transcodingContainer: "mp3",
            transcodingProtocol: .http
        )
        let request = Paths.getUniversalAudioStream(itemID: itemID, parameters: parameters)
        guard let url = client.url(with: request, queryAPIKey: true) else {
            throw StreamError.noURL
        }
        return url
    }

    /// Threat model note: the access token rides in the URL query (`api_key`) because
    /// AVPlayer/HLS fetches can't carry auth headers — the standard Jellyfin-client
    /// pattern. Consequence: these URLs are sensitive (server/proxy logs see them), so
    /// they must never be logged here; OSLog statements in this file log item ids only.
    private func authenticatedPlaybackURL(path: String) -> URL? {
        guard let url = client.url(path: path) else { return nil }
        return Self.appendingAPIKeyIfNeeded(to: url, accessToken: client.accessToken)
    }

    private static func appendingAPIKeyIfNeeded(to url: URL, accessToken: String?) -> URL {
        guard let accessToken,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }

        var queryItems = components.queryItems ?? []
        guard !queryItems.contains(where: { $0.name == "api_key" }) else { return url }

        queryItems.append(URLQueryItem(name: "api_key", value: accessToken))
        components.queryItems = queryItems
        return components.url ?? url
    }
}
