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
    enum StereoFallbackReason: Equatable, Sendable {
        case directPlayUnavailable(Stereo3DLayout)
    }

    struct Resolution: Sendable {
        let url: URL
        let playSessionID: String?
        let mediaSourceID: String?
        /// True when the server returned a transcoding (HLS) URL rather than a direct file.
        let isTranscoding: Bool
        let stereoLayout: Stereo3DLayout
        let stereoFallbackReason: StereoFallbackReason?
        var mediaSource: JellyfinAPI.MediaSourceInfo? = nil
        var resource: PlaybackResource? = nil
        var isDirectPlay = false

        func fallingBackTo2D(from layout: Stereo3DLayout) -> Resolution {
            Resolution(
                url: url,
                playSessionID: playSessionID,
                mediaSourceID: mediaSourceID,
                isTranscoding: isTranscoding,
                stereoLayout: .none,
                stereoFallbackReason: .directPlayUnavailable(layout),
                mediaSource: mediaSource,
                resource: resource,
                isDirectPlay: isDirectPlay
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

    @MainActor
    func resolvePlayback(
        for itemID: String,
        maxStreamingBitrate: Int = 120_000_000,
        streamSelection: PlaybackStreamSelection = .none,
        startTimeTicks: Int? = nil,
        stereoLayout: Stereo3DLayout = .none,
        allowOriginalHLS: Bool = true
    ) async throws -> Resolution {
        try PlaybackResolutionBudget.check()
        var body = Self.playbackInfoBody(
            userID: userID,
            maxStreamingBitrate: maxStreamingBitrate,
            streamSelection: streamSelection,
            startTimeTicks: startTimeTicks,
            stereoLayout: stereoLayout
        )
        if !allowOriginalHLS {
            body.enableDirectPlay = false
            body.enableDirectStream = false
        }

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

        // Playback negotiation may allocate a live/transcode resource. A lost response
        // cannot be retried safely because its allocation ID may never reach us.
        let response = try await client.send(request).value
        var ownsResponse = true
        do {
            try PlaybackResolutionBudget.check()

            let sources = response.mediaSources ?? []
            let source = streamSelection.mediaSourceID.flatMap { requested in sources.first { $0.id == requested } }
                ?? (streamSelection.mediaSourceID == nil || sources.contains(where: { $0.liveStreamID != nil }) ? sources.first : nil)
            guard let source else {
                if stereoLayout.requiresDirectPlay {
                    await releaseResources(in: response)
                    ownsResponse = false
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
            let resource: PlaybackResource? = source.liveStreamID != nil || source.transcodingURL != nil
                ? PlaybackResource(liveStreamID: source.liveStreamID, playSessionID: playSessionID, isTranscoding: source.transcodingURL != nil) : nil

            if stereoLayout.requiresDirectPlay, source.isSupportsDirectPlay == false {
                await releaseResources(in: response)
                ownsResponse = false
                return try await resolvePlayback(
                    for: itemID,
                    maxStreamingBitrate: maxStreamingBitrate,
                    streamSelection: streamSelection,
                    startTimeTicks: startTimeTicks,
                    stereoLayout: .none
                )
                .fallingBackTo2D(from: stereoLayout)
            }

            if Self.isHLS(source), source.transcodingURL == nil {
                if allowOriginalHLS, let url = Self.originalHLSURL(source) {
                    await releaseUnselected(in: response, keeping: source.liveStreamID)
                    return Resolution(url: url, playSessionID: playSessionID, mediaSourceID: source.id, isTranscoding: false, stereoLayout: stereoLayout, stereoFallbackReason: nil, mediaSource: source, resource: resource, isDirectPlay: true)
                }
                // The static Jellyfin endpoint proxies master bytes without rewriting
                // relative renditions. Unsupported headers/local masters need server
                // HLS; this is a new negotiation after a known response, never a retry
                // of an allocation whose response was lost.
                guard allowOriginalHLS else { throw StreamError.noURL }
                await releaseResources(in: response)
                ownsResponse = false
                let fallback = try await resolvePlayback(for: itemID, maxStreamingBitrate: maxStreamingBitrate, streamSelection: streamSelection, startTimeTicks: startTimeTicks, stereoLayout: .none, allowOriginalHLS: false)
                return stereoLayout.requiresDirectPlay ? fallback.fallingBackTo2D(from: stereoLayout) : fallback
            }

            // The server negotiates the play method against the device profile: it returns a
            // transcoding URL only when the source genuinely needs server-side work for this
            // device/selection. Absent one, the file direct-streams below.
            if !stereoLayout.requiresDirectPlay, let transcodingURL = source.transcodingURL, let url = authenticatedPlaybackURL(path: transcodingURL) {
                logger.debug("Resolved HLS transcoding URL for item \(itemID, privacy: .private)")
                await releaseUnselected(in: response, keeping: source.liveStreamID)
                return Resolution(
                    url: url,
                    playSessionID: playSessionID,
                    mediaSourceID: source.id,
                    isTranscoding: true,
                    stereoLayout: .none,
                    stereoFallbackReason: nil,
                    mediaSource: source,
                    resource: resource
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
                liveStreamID: source.liveStreamID,
                audioStreamIndex: streamSelection.audioStreamIndex
            )
            let streamRequest = Paths.getVideoStream(itemID: itemID, parameters: streamParameters)

            guard let url = client.url(with: streamRequest, queryAPIKey: true) else {
                throw StreamError.noURL
            }

            logger.debug("Resolved direct-stream URL for item \(itemID, privacy: .private)")
            await releaseUnselected(in: response, keeping: source.liveStreamID)
            return Resolution(
                url: url,
                playSessionID: playSessionID,
                mediaSourceID: source.id,
                isTranscoding: false,
                stereoLayout: stereoLayout,
                stereoFallbackReason: nil,
                mediaSource: source,
                resource: resource
            )
        } catch {
            if ownsResponse {
                await releaseResources(in: response)
            }
            throw error
        }
    }

    private static func isHLS(_ source: MediaSourceInfo) -> Bool {
        (source.container ?? "").lowercased().split(separator: ",").contains { $0 == "hls" || $0 == "m3u8" }
    }

    /// Preserve the actual manifest origin/base URL and never append Jellyfin
    /// credentials to a foreign origin. AVPlayer receives no undocumented headers.
    static func originalHLSURL(_ source: MediaSourceInfo) -> URL? {
        guard isHLS(source), source.isSupportsDirectPlay == true, source.isRemote == true,
              source.protocol == .http, source.requiredHTTPHeaders?.isEmpty != false,
              let path = source.path, let url = URL(string: path),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }

    @MainActor
    func release(resource: PlaybackResource) async throws {
        let client = client
        try await PlaybackDeadline.run(for: .seconds(5)) {
            if let id = resource.liveStreamID {
                _ = try await client.send(Paths.closeLiveStream(liveStreamID: id))
            } else if resource.isTranscoding, let id = resource.playSessionID {
                _ = try await client.send(Paths.stopEncodingProcess(deviceID: DeviceIdentity.deviceID, playSessionID: id))
            }
        }
    }

    @MainActor
    private func releaseUnselected(in response: PlaybackInfoResponse, keeping liveStreamID: String?) async {
        let ids = Set((response.mediaSources ?? []).compactMap(\.liveStreamID)).filter { $0 != liveStreamID }
        guard !ids.isEmpty else { return }
        let client = client
        try? await PlaybackDeadline.run(for: .seconds(5)) {
            for id in ids {
                _ = try? await client.send(Paths.closeLiveStream(liveStreamID: id))
            }
        }
    }

    @MainActor
    private func releaseResources(in response: PlaybackInfoResponse) async {
        let ids = Set((response.mediaSources ?? []).compactMap(\.liveStreamID))
        let client = client
        try? await PlaybackDeadline.run(for: .seconds(5)) {
            for id in ids {
                _ = try? await client.send(Paths.closeLiveStream(liveStreamID: id))
            }
            if ids.isEmpty, (response.mediaSources ?? []).contains(where: { $0.transcodingURL != nil }), let id = response.playSessionID {
                _ = try? await client.send(Paths.stopEncodingProcess(deviceID: DeviceIdentity.deviceID, playSessionID: id))
            }
        }
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
            containerProfiles: [AVPlayerContainerCompatibility.mp4Profile],
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
        if capabilities.supportsHEVCDecode {
            mp4Video.append("hevc")
        }
        if capabilities.supportsAV1Decode {
            mp4Video.append("av1")
        }

        return [
            DirectPlayProfile(
                audioCodec: "aac,mp3,ac3,eac3,alac,flac",
                container: "mp4,m4v,mov",
                type: .video,
                videoCodec: mp4Video.joined(separator: ",")
            ),
            DirectPlayProfile(audioCodec: "aac,mp3,ac3,eac3,alac,flac", container: "hls,m3u8", type: .video, videoCodec: mp4Video.joined(separator: ",")),
            // Standalone TS/M2TS is not an AVPlayer direct-play contract. Jellyfin
            // can approve a file because *another* audio track matches this profile,
            // while the selected Blu-ray DTS track remains unsupported. Use HLS so
            // the server selects the track, copies compatible video and converts audio.
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
            isAutoOpenLiveStream: true,
            maxStreamingBitrate: maxStreamingBitrate,
            mediaSourceID: streamSelection.mediaSourceID,
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
            subtitleStreamIndex: streamSelection.subtitleStreamIndex,
            mediaSourceID: streamSelection.mediaSourceID
        )
    }

    /// Negotiate audio once so delivery/session telemetry describes the selected stream.
    @MainActor
    func resolveAudioPlayback(for itemID: String, streamSelection: PlaybackStreamSelection = .none) async throws -> Resolution {
        try PlaybackResolutionBudget.check()
        let profile = DeviceProfile(
            directPlayProfiles: [DirectPlayProfile(audioCodec: "aac,mp3,ac3,eac3,alac,flac,pcm_s16le,pcm_s24le", container: "mp3,aac,m4a,m4b,mp4,flac,alac,wav", type: .audio)],
            maxStreamingBitrate: 12_000_000,
            transcodingProfiles: [TranscodingProfile(protocol: .http, audioCodec: "mp3", container: "mp3", context: .streaming, type: .audio)]
        )
        let response = try await client.send(Paths.getPostedPlaybackInfo(
            itemID: itemID,
            PlaybackInfoDto(audioStreamIndex: streamSelection.audioStreamIndex, deviceProfile: profile, isAutoOpenLiveStream: true, maxStreamingBitrate: 12_000_000, mediaSourceID: streamSelection.mediaSourceID, userID: userID)
        )).value
        do {
            try PlaybackResolutionBudget.check()
            let sources = response.mediaSources ?? []
            guard let source = streamSelection.mediaSourceID.flatMap({ id in sources.first { $0.id == id } }) ?? (streamSelection.mediaSourceID == nil ? sources.first : nil) else { throw StreamError.noMediaSource }
            let url: URL?
            if let path = source.transcodingURL {
                url = authenticatedPlaybackURL(path: path)
            } else {
                url = client.url(with: Paths.getAudioStream(itemID: itemID, parameters: .init(
                    isStatic: true,
                    tag: source.eTag,
                    playSessionID: response.playSessionID,
                    mediaSourceID: source.id,
                    deviceID: DeviceIdentity.deviceID,
                    liveStreamID: source.liveStreamID,
                    audioStreamIndex: streamSelection.audioStreamIndex
                )), queryAPIKey: true)
            }
            guard let url else { throw StreamError.noURL }
            await releaseUnselected(in: response, keeping: source.liveStreamID)
            return Resolution(
                url: url,
                playSessionID: response.playSessionID,
                mediaSourceID: source.id,
                isTranscoding: source.transcodingURL != nil,
                stereoLayout: .none,
                stereoFallbackReason: nil,
                mediaSource: source,
                resource: source.liveStreamID != nil || source.transcodingURL != nil
                    ? PlaybackResource(liveStreamID: source.liveStreamID, playSessionID: response.playSessionID, isTranscoding: source.transcodingURL != nil) : nil
            )
        } catch {
            await releaseResources(in: response)
            throw error
        }
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
