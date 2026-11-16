import Foundation
@testable import Gus
import JellyfinAPI
import os
import Testing

@Suite("AVPlayer device profile")
struct StreamURLBuilderTests {
    private let fullCapabilities = DevicePlaybackCapabilities(
        supportsHEVCDecode: true,
        supportsAV1Decode: true,
        supportsHDRPlayback: true
    )

    private let baselineCapabilities = DevicePlaybackCapabilities(
        supportsHEVCDecode: false,
        supportsAV1Decode: false,
        supportsHDRPlayback: false
    )

    @Test("declares hardware-gated direct play and an HEVC-preferred fMP4 HLS transcode")
    func avPlayerProfileLeansDirectPlayWithModernTranscode() {
        let profile = StreamURLBuilder.avPlayerProfile(maxStreamingBitrate: 42_000_000, capabilities: fullCapabilities)
        let directPlay = profile.directPlayProfiles?.first
        let transcoding = profile.transcodingProfiles?.first

        #expect(profile.maxStaticBitrate == 42_000_000)
        #expect(profile.maxStreamingBitrate == 42_000_000)
        #expect(directPlay?.container == "mp4,m4v,mov")
        #expect(directPlay?.videoCodec == "h264,hevc,av1")
        #expect(transcoding?.protocol == .hls)
        #expect(transcoding?.container == "mp4")
        #expect(transcoding?.videoCodec == "hevc,h264")
        #expect(transcoding?.maxAudioChannels == "8")
        #expect(transcoding?.enableSubtitlesInManifest == true)
        #expect(transcoding?.isBreakOnNonKeyFrames == true)
        #expect(transcoding?.type == .video)
        #expect(transcoding?.context == .streaming)
    }

    @Test("baseline hardware drops HEVC/AV1 from direct play and transcodes to H.264")
    func avPlayerProfileHonorsBaselineHardware() {
        let profile = StreamURLBuilder.avPlayerProfile(maxStreamingBitrate: 42_000_000, capabilities: baselineCapabilities)
        let directPlay = profile.directPlayProfiles?.first
        let transcoding = profile.transcodingProfiles?.first

        #expect(directPlay?.videoCodec == "h264")
        #expect(transcoding?.videoCodec == "h264")
    }

    @Test("Blu-ray TS and M2TS require HLS rather than raw-file direct play")
    func avPlayerProfileRemuxesTransportStreams() throws {
        let profile = StreamURLBuilder.avPlayerProfile(maxStreamingBitrate: 42_000_000, capabilities: fullCapabilities)
        let containers = profile.directPlayProfiles?.flatMap { ($0.container ?? "").split(separator: ",") } ?? []
        #expect(!containers.contains("ts"))
        #expect(!containers.contains("mpegts"))
        #expect(!containers.contains("m2ts"))
        let hls = try #require(profile.transcodingProfiles?.first)
        #expect(hls.protocol == .hls)
        #expect(hls.container == "mp4")
        #expect(hls.videoCodec?.split(separator: ",").contains("h264") == true)
        #expect(hls.audioCodec?.split(separator: ",").contains("dts") == false)
    }

    @Test("compatibility-mode Live TV has an H.264 TS HLS option after preferred fMP4", arguments: [false, true])
    func liveHLSCompatibilityProfile(supportsHEVC: Bool) throws {
        let capabilities = DevicePlaybackCapabilities(supportsHEVCDecode: supportsHEVC, supportsAV1Decode: false, supportsHDRPlayback: false)
        let profile = StreamURLBuilder.avPlayerProfile(maxStreamingBitrate: 42_000_000, capabilities: capabilities)
        let profiles = try #require(profile.transcodingProfiles)
        #expect(profiles.map(\.container) == ["mp4", "ts"])
        #expect(profiles.first?.protocol == .hls)
        #expect(profiles.first?.videoCodec == (supportsHEVC ? "hevc,h264" : "h264"))
        // Jellyfin's UseMostCompatibleTranscodingProfile filters on this container.
        let live = try #require(profiles.first { $0.container == "ts" })
        #expect(live.protocol == .hls)
        #expect(live.videoCodec == "h264")
        #expect(live.audioCodec == "aac,ac3,eac3")
        #expect(live.type == .video)
        #expect(live.context == .streaming)
        #expect(live.enableSubtitlesInManifest == true)
        #expect(live.minSegments == 2)
    }

    @Test("text subtitles ride the HLS manifest; bitmap subtitles burn in")
    func avPlayerProfileDeclaresSubtitleDelivery() throws {
        let profile = StreamURLBuilder.avPlayerProfile(maxStreamingBitrate: 42_000_000, capabilities: fullCapabilities)
        let subtitles = try #require(profile.subtitleProfiles)

        #expect(subtitles.contains { $0.format == "vtt" && $0.method == .hls })
        #expect(subtitles.contains { $0.format == "pgssub" && $0.method == .encode })
        #expect(subtitles.contains { $0.format == "ttml" && $0.method == .embed })
        // Nothing may declare external delivery — AVPlayer can't attach sidecar files.
        #expect(!subtitles.contains { $0.method == .external })
    }

    @Test("codec conditions exclude Hi10P/interlaced H.264 and gate HDR on display eligibility")
    func avPlayerProfileConstrainsCodecVariants() throws {
        let hdrProfile = StreamURLBuilder.avPlayerProfile(maxStreamingBitrate: 42_000_000, capabilities: fullCapabilities)
        let sdrProfile = StreamURLBuilder.avPlayerProfile(maxStreamingBitrate: 42_000_000, capabilities: baselineCapabilities)

        let h264 = try #require(hdrProfile.codecProfiles?.first { $0.codec == "h264" })
        #expect(h264.conditions?.contains { $0.property == .videoBitDepth && $0.value == "8" } == true)
        #expect(h264.conditions?.contains { $0.property == .isInterlaced } == true)

        let hevcHDR = try #require(hdrProfile.codecProfiles?.first { $0.codec == "hevc" })
        let hdrRange = try #require(hevcHDR.conditions?.first { $0.property == .videoRangeType }?.value)
        #expect(hdrRange.contains("HDR10"))
        #expect(hdrRange.contains("HLG"))

        let hevcSDR = try #require(sdrProfile.codecProfiles?.first { $0.codec == "hevc" })
        #expect(hevcSDR.conditions?.first { $0.property == .videoRangeType }?.value == "SDR")
    }

    @Test("MP4 hev1 originals require remuxing while HEVC stream copy remains allowed")
    func avPlayerProfileRemuxesIncompatibleHEVCTag() throws {
        let profile = StreamURLBuilder.avPlayerProfile(maxStreamingBitrate: 42_000_000, capabilities: fullCapabilities)
        let container = try #require(profile.containerProfiles?.first { $0.type == .video })
        #expect(container.container == "mp4,m4v,mov")
        let condition = try #require(container.conditions?.first { $0.property == .videoCodecTag })
        #expect(condition.condition == .notEquals)
        #expect(condition.value == "hev1")
        #expect(condition.isRequired == false)
        // A codec restriction would force encoding instead of repairing the container.
        #expect(profile.codecProfiles?.flatMap { $0.conditions ?? [] }.contains { $0.property == .videoCodecTag } == false)
        #expect(profile.transcodingProfiles?.first?.videoCodec == "hevc,h264")
    }

    @Test("direct-play body disables transcoding for stereo sources")
    func playbackInfoBodyDisablesTranscodingForStereoSources() {
        let body = StreamURLBuilder.playbackInfoBody(
            userID: "user-1",
            maxStreamingBitrate: 42_000_000,
            streamSelection: .none,
            startTimeTicks: nil,
            stereoLayout: .sideBySide(half: true)
        )

        #expect(body.enableDirectPlay == true)
        #expect(body.enableDirectStream == true)
        #expect(body.enableTranscoding == false)
        #expect(body.deviceProfile?.directPlayProfiles?.first?.container == "mp4,m4v,mov")
        #expect(body.deviceProfile?.transcodingProfiles?.isEmpty == true)
    }

    @Test("ordinary playback body keeps the HLS transcode bias")
    func playbackInfoBodyKeepsTranscodingForOrdinarySources() {
        let body = StreamURLBuilder.playbackInfoBody(
            userID: "user-1",
            maxStreamingBitrate: 42_000_000,
            streamSelection: .none,
            startTimeTicks: nil,
            stereoLayout: .none
        )

        #expect(body.enableTranscoding == true)
        #expect(body.deviceProfile?.transcodingProfiles?.first?.protocol == .hls)
    }

    @Test("transcoding URLs include the access token for AVPlayer requests")
    func resolvePlaybackAddsAPIKeyToTranscodingURL() async throws {
        let fixture = try makePlaybackInfoFixture(responses: [
            PlaybackInfoResponse(
                mediaSources: [
                    MediaSourceInfo(
                        id: "hls-source",
                        transcodingURL: "/Videos/item-1/master.m3u8?MediaSourceId=hls-source"
                    ),
                ],
                playSessionID: "session-hls"
            ),
        ])

        let builder = StreamURLBuilder(
            client: fixture.client,
            userID: "user-1"
        )

        let resolution = try await builder.resolvePlayback(for: "item-1")
        let components = try #require(URLComponents(url: resolution.url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []

        #expect(resolution.mediaSource?.id == "hls-source")
        #expect(queryItems.contains(URLQueryItem(name: "MediaSourceId", value: "hls-source")))
        #expect(queryItems.contains(URLQueryItem(name: "api_key", value: "token")))
    }

    @MainActor
    @Test("Live TV advertises TS HLS and retains the negotiated live resource without another allocation")
    func liveHLSNegotiationRetainsResource() async throws {
        let source = MediaSourceInfo(
            container: "ts",
            id: "live-source",
            isInfiniteStream: true,
            isSupportsDirectPlay: false,
            liveStreamID: "live-allocation",
            transcodingContainer: "ts",
            transcodingSubProtocol: .hls,
            transcodingURL: "/Videos/channel/master.m3u8?LiveStreamId=live-allocation"
        )
        let fixture = try makePlaybackInfoFixture(responses: [PlaybackInfoResponse(mediaSources: [source], playSessionID: "live-session")])
        let resolution = try await StreamURLBuilder(client: fixture.client, userID: "user").resolvePlayback(for: "channel")
        let body = try #require(fixture.recordedPlaybackInfoBodies.first)
        #expect(body.deviceProfile?.transcodingProfiles?.contains { $0.container == "ts" && $0.protocol == .hls && $0.videoCodec == "h264" } == true)
        #expect(body.enableDirectPlay == true)
        #expect(body.enableDirectStream == true)
        #expect(body.isAutoOpenLiveStream == true)
        #expect(resolution.url.path == "/Videos/channel/master.m3u8")
        #expect(resolution.isTranscoding)
        #expect(resolution.mediaSourceID == "live-source")
        #expect(resolution.playSessionID == "live-session")
        #expect(resolution.resource == PlaybackResource(liveStreamID: "live-allocation", playSessionID: "live-session", isTranscoding: true))
        // No second PlaybackInfo POST or premature Close of the retained allocation.
        #expect(fixture.recordedRequestCount == 1)
    }

    @MainActor
    @Test("the Live TV compatibility profile preserves compatible MP4 direct delivery")
    func compatibleMP4StillDirectStreams() async throws {
        let fixture = try makePlaybackInfoFixture(responses: [PlaybackInfoResponse(mediaSources: [MediaSourceInfo(container: "mp4", id: "mp4-source", isSupportsDirectPlay: true)], playSessionID: "mp4-session")])
        let resolution = try await StreamURLBuilder(client: fixture.client, userID: "user").resolvePlayback(for: "movie")
        let body = try #require(fixture.recordedPlaybackInfoBodies.first)
        #expect(body.enableDirectPlay == true)
        #expect(body.enableDirectStream == true)
        #expect(body.deviceProfile?.directPlayProfiles?.first?.container == "mp4,m4v,mov")
        #expect(body.deviceProfile?.transcodingProfiles?.first?.container == "mp4")
        #expect(resolution.url.path == "/Videos/movie/stream")
        #expect(resolution.mediaSourceID == "mp4-source")
        #expect(resolution.playSessionID == "mp4-session")
        #expect(!resolution.isTranscoding)
        #expect(resolution.resource == nil)
        #expect(fixture.recordedRequestCount == 1)
    }

    @Test("resolvePlayback retries in 2D when a stereo source cannot direct play")
    func resolvePlaybackFallsBackTo2DWhenStereoDirectPlayIsUnavailable() async throws {
        let stereoLayout = Stereo3DLayout.sideBySide(half: true)
        let fixture = try makePlaybackInfoFixture(responses: [
            PlaybackInfoResponse(
                mediaSources: [
                    MediaSourceInfo(
                        id: "stereo-source",
                        isSupportsDirectPlay: false,
                        transcodingURL: "/Videos/item-1/master.m3u8"
                    ),
                ],
                playSessionID: "session-stereo"
            ),
            PlaybackInfoResponse(
                mediaSources: [
                    MediaSourceInfo(
                        id: "fallback-source",
                        isSupportsDirectPlay: true,
                        transcodingURL: "/Videos/item-1/master.m3u8"
                    ),
                ],
                playSessionID: "session-2d"
            ),
        ])

        let builder = StreamURLBuilder(
            client: fixture.client,
            userID: "user-1"
        )

        let resolution = try await builder.resolvePlayback(
            for: "item-1",
            maxStreamingBitrate: 42_000_000,
            stereoLayout: stereoLayout
        )
        let requests = fixture.recordedPlaybackInfoBodies

        #expect(resolution.url.absoluteString == "https://jellyfin.example.com/Videos/item-1/master.m3u8?api_key=token")
        #expect(resolution.playSessionID == "session-2d")
        #expect(resolution.mediaSourceID == "fallback-source")
        #expect(resolution.isTranscoding)
        #expect(resolution.stereoLayout == .none)
        #expect(resolution.stereoFallbackReason == .directPlayUnavailable(stereoLayout))

        #expect(requests.map(\.enableTranscoding) == [false, true])
        #expect(requests.first?.deviceProfile?.transcodingProfiles?.isEmpty == true)
        #expect(requests.last?.deviceProfile?.transcodingProfiles?.first?.protocol == .hls)
    }

    @Test("version selection is negotiated and retained even when response ordering differs")
    func chosenMediaSource() async throws {
        let fixture = try makePlaybackInfoFixture(responses: [PlaybackInfoResponse(mediaSources: [
            MediaSourceInfo(id: "first", isSupportsDirectPlay: true),
            MediaSourceInfo(id: "chosen", isSupportsDirectPlay: true),
        ], playSessionID: "version-session")])
        let resolution = try await StreamURLBuilder(client: fixture.client, userID: "user").resolvePlayback(
            for: "movie",
            streamSelection: PlaybackStreamSelection(audioStreamIndex: nil, subtitleStreamIndex: -1, mediaSourceID: "chosen")
        )
        #expect(resolution.mediaSourceID == "chosen")
        #expect(fixture.recordedPlaybackInfoBodies.first?.mediaSourceID == "chosen")
        #expect(fixture.recordedPlaybackInfoBodies.first?.isAutoOpenLiveStream == true)
    }

    @Test("an allocating negotiation is not retried after a transient lost response")
    func allocatingPostIsNotRetried() async throws {
        let fixture = try PlaybackInfoClientFixture(responses: [], failure: URLError(.networkConnectionLost))
        do {
            _ = try await StreamURLBuilder(client: fixture.client, userID: "user").resolvePlayback(for: "movie")
            Issue.record("Expected lost response")
        } catch { #expect((error as? URLError)?.code == .networkConnectionLost) }
        #expect(fixture.recordedPlaybackInfoBodies.count == 1)
    }

    @MainActor
    @Test("audio negotiates source, track and session before building authenticated native delivery", arguments: [false, true])
    func negotiatedAudioSource(transcoded: Bool) async throws {
        let fixture = try makePlaybackInfoFixture(responses: [PlaybackInfoResponse(mediaSources: [MediaSourceInfo(container: "aac", id: "audio-version", isSupportsDirectPlay: !transcoded, transcodingURL: transcoded ? "/Audio/song-1/stream.mp3" : nil)], playSessionID: "negotiated-audio")])
        let resolution = try await StreamURLBuilder(client: fixture.client, userID: "user").resolveAudioPlayback(for: "song-1", streamSelection: PlaybackStreamSelection(audioStreamIndex: 3, subtitleStreamIndex: nil, mediaSourceID: "audio-version"))
        #expect(resolution.mediaSourceID == "audio-version")
        #expect(resolution.playSessionID == "negotiated-audio")
        #expect(resolution.isTranscoding == transcoded)
        #expect(resolution.url.host == "jellyfin.example.com")
        #expect(resolution.url.path == (transcoded ? "/Audio/song-1/stream.mp3" : "/Audio/song-1/stream"))
        #expect(URLComponents(url: resolution.url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "api_key" && $0.value == "token" } == true)
        let request = try #require(fixture.recordedPlaybackInfoBodies.first)
        #expect(request.mediaSourceID == "audio-version")
        #expect(request.audioStreamIndex == 3)
        #expect(request.isAutoOpenLiveStream == true)
        #expect(fixture.recordedPlaybackInfoBodies.count == 1)
    }

    @MainActor
    @Test("compatible remote HLS preserves its master origin and relative renditions without Jellyfin credentials")
    func originalHLSMaster() async throws {
        let source = MediaSourceInfo(protocol: .http, container: "hls", id: "hls-source", isRemote: true, isSupportsDirectPlay: true, path: "https://media.example.net/library/master.m3u8?signature=public-fixture", requiredHTTPHeaders: [:])
        let fixture = try makePlaybackInfoFixture(responses: [PlaybackInfoResponse(mediaSources: [source], playSessionID: "hls-play")])
        let resolution = try await StreamURLBuilder(client: fixture.client, userID: "user").resolvePlayback(for: "movie")
        #expect(resolution.url.absoluteString == source.path)
        #expect(resolution.isDirectPlay)
        #expect(!resolution.isTranscoding)
        #expect(URLComponents(url: resolution.url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "api_key" } == false)
        #expect(URL(string: "v5/iframe.m3u8", relativeTo: resolution.url)?.absoluteURL.absoluteString == "https://media.example.net/library/v5/iframe.m3u8")
        #expect(fixture.recordedPlaybackInfoBodies.count == 1)
        let profile = try #require(fixture.recordedPlaybackInfoBodies.first?.deviceProfile)
        #expect(profile.directPlayProfiles?.contains { $0.container == "hls,m3u8" && $0.videoCodec?.contains("h264") == true } == true)
    }

    @MainActor
    @Test("remote HLS requiring custom headers renegotiates known response through server HLS")
    func headerProtectedHLSFallsBack() async throws {
        let fixture = try makePlaybackInfoFixture(responses: [
            PlaybackInfoResponse(mediaSources: [MediaSourceInfo(protocol: .http, container: "hls", id: "protected-hls", isRemote: true, isSupportsDirectPlay: true, path: "https://media.example.net/private/master.m3u8", requiredHTTPHeaders: ["Authorization": "fixture-only"])], playSessionID: "known-direct"),
            PlaybackInfoResponse(mediaSources: [MediaSourceInfo(container: "hls", id: "protected-hls", isSupportsDirectPlay: false, transcodingURL: "/Videos/movie/master.m3u8")], playSessionID: "server-hls"),
        ])
        let resolution = try await StreamURLBuilder(client: fixture.client, userID: "user").resolvePlayback(for: "movie")
        #expect(resolution.isTranscoding)
        #expect(!resolution.isDirectPlay)
        #expect(resolution.url.host == "jellyfin.example.com")
        let bodies = fixture.recordedPlaybackInfoBodies
        #expect(bodies.count == 2)
        #expect(bodies.last?.enableDirectPlay == false)
        #expect(bodies.last?.enableDirectStream == false)
        #expect(bodies.last?.enableTranscoding == true)
    }

    @MainActor
    @Test("an exhausted total budget starts no allocation or fallback")
    func exhaustedResolutionBudget() async throws {
        let fixture = try makePlaybackInfoFixture(responses: [])
        do {
            _ = try await PlaybackResolutionBudget.$deadline.withValue(ContinuousClock.now - .seconds(1)) {
                try await StreamURLBuilder(client: fixture.client, userID: "user").resolvePlayback(for: "movie")
            }
            Issue.record("Expected exhausted total resolution budget")
        } catch { #expect(error is PlaybackDeadline.Timeout) }
        #expect(fixture.recordedRequestCount == 0)
    }

    @MainActor
    @Test("a canceled owner releases a late known allocation without starting HLS fallback")
    func canceledOwnerPreventsFallback() async throws {
        let fixture = try makePlaybackInfoFixture(responses: [PlaybackInfoResponse(mediaSources: [MediaSourceInfo(protocol: .http, container: "hls", id: "late-source", isRemote: true, isSupportsDirectPlay: true, liveStreamID: "known-late-live", path: "https://media.example.net/master.m3u8", requiredHTTPHeaders: ["User-Agent": "fixture-only"])])])
        do {
            _ = try await PlaybackResolutionBudget.withValue(deadline: .now + .seconds(30), ownerIsCurrent: { fixture.recordedPlaybackInfoBodies.isEmpty }) {
                try await StreamURLBuilder(client: fixture.client, userID: "user").resolvePlayback(for: "movie")
            }
            Issue.record("Expected canceled owner")
        } catch { #expect(error is CancellationError) }
        #expect(fixture.recordedPlaybackInfoBodies.count == 1)
        #expect(fixture.recordedRequestCount == 2) // one negotiation and one known-resource Close
    }

    @MainActor
    @Test("safe item metadata reads retry at most three transport attempts")
    func safeReadRetryBudget() async throws {
        let fixture = try PlaybackInfoClientFixture(responses: [], failure: URLError(.timedOut))
        let provider = JellyfinMediaProviderSession(client: fixture.client, userID: "user")
        do {
            _ = try await provider.item(id: "movie")
            Issue.record("Expected timeout")
        } catch { #expect((error as? URLError)?.code == .timedOut) }
        #expect(fixture.recordedRequestCount == 3)
    }

    private func makePlaybackInfoFixture(responses: [PlaybackInfoResponse]) throws -> PlaybackInfoClientFixture {
        try PlaybackInfoClientFixture(responses: responses)
    }
}

private final class PlaybackInfoClientFixture {
    let client: JellyfinClient
    private let stateID: String
    private let state: PlaybackInfoURLProtocolState

    var recordedPlaybackInfoBodies: [PlaybackInfoDto] {
        state.recordedBodies
    }

    var recordedRequestCount: Int {
        state.recordedRequestCount
    }

    init(responses: [PlaybackInfoResponse], failure: URLError? = nil) throws {
        state = PlaybackInfoURLProtocolState(responses: responses, failure: failure)
        stateID = PlaybackInfoURLProtocol.register(state: state)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaybackInfoURLProtocol.self]
        configuration.httpAdditionalHeaders = [
            PlaybackInfoURLProtocol.stateHeaderName: stateID,
        ]

        client = try JellyfinClient(
            configuration: .init(
                url: #require(URL(string: "https://jellyfin.example.com")),
                accessToken: "token",
                client: "GusTests",
                deviceName: "Tests",
                deviceID: "test-device",
                version: "1"
            ),
            sessionConfiguration: configuration
        )
    }

    deinit {
        PlaybackInfoURLProtocol.unregister(stateID: stateID)
    }
}

private final class PlaybackInfoURLProtocol: URLProtocol {
    static let stateHeaderName = "X-Gus-PlaybackInfo-State-ID"

    private static let states = OSAllocatedUnfairLock(initialState: [String: PlaybackInfoURLProtocolState]())

    static func register(state: PlaybackInfoURLProtocolState) -> String {
        let stateID = UUID().uuidString
        states.withLock { $0[stateID] = state }
        return stateID
    }

    static func unregister(stateID: String) {
        states.withLock { $0[stateID] = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: stateHeaderName) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let responseBody = try Self.state(for: request).response(for: request)
            let data = try JSONEncoder().encode(responseBody)
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: 200,
                      httpVersion: nil,
                      headerFields: ["Content-Type": "application/json"]
                  )
            else {
                throw URLError(.badURL)
            }

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func state(for request: URLRequest) throws -> PlaybackInfoURLProtocolState {
        guard let stateID = request.value(forHTTPHeaderField: stateHeaderName), let state = states.withLock({ $0[stateID] }) else {
            throw URLError(.badServerResponse)
        }
        return state
    }
}

/// The lock serializes all response consumption and recorded-body snapshots.
private final class PlaybackInfoURLProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [PlaybackInfoResponse]
    private var bodies: [PlaybackInfoDto] = []
    private var requestCount = 0
    private let failure: URLError?

    init(responses: [PlaybackInfoResponse], failure: URLError? = nil) {
        self.responses = responses
        self.failure = failure
    }

    var recordedRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    var recordedBodies: [PlaybackInfoDto] {
        lock.lock()
        defer { lock.unlock() }
        return bodies
    }

    func response(for request: URLRequest) throws -> PlaybackInfoResponse {
        lock.lock()
        defer { lock.unlock() }
        requestCount += 1
        if request.httpMethod == "POST", request.url?.path.hasSuffix("/PlaybackInfo") == true {
            try bodies.append(Self.decodePlaybackInfoBody(from: request))
        }
        if let failure {
            throw failure
        }
        guard request.url?.path.hasSuffix("/PlaybackInfo") == true else { return PlaybackInfoResponse() }
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return responses.removeFirst()
    }

    private static func decodePlaybackInfoBody(from request: URLRequest) throws -> PlaybackInfoDto {
        let data = try bodyData(from: request)
        return try JSONDecoder().decode(PlaybackInfoDto.self, from: data)
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)

        while stream.hasBytesAvailable {
            let readCount = buffer.withUnsafeMutableBufferPointer { pointer in
                stream.read(pointer.baseAddress!, maxLength: pointer.count)
            }

            if readCount < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeContentData)
            }
            if readCount == 0 {
                break
            }

            data.append(buffer, count: readCount)
        }

        return data
    }
}
