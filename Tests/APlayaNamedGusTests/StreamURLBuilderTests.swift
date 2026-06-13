import Foundation
@testable import Gus
import JellyfinAPI
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

    @Test("transport-stream direct play covers Live TV containers")
    func avPlayerProfileDirectPlaysTransportStreams() throws {
        let profile = StreamURLBuilder.avPlayerProfile(maxStreamingBitrate: 42_000_000, capabilities: fullCapabilities)
        let ts = try #require(profile.directPlayProfiles?.first { $0.container?.contains("mpegts") == true })

        #expect(ts.videoCodec == "h264,hevc")
        #expect(ts.audioCodec?.split(separator: ",").contains("eac3") == true)
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

        #expect(queryItems.contains(URLQueryItem(name: "MediaSourceId", value: "hls-source")))
        #expect(queryItems.contains(URLQueryItem(name: "api_key", value: "token")))
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

    init(responses: [PlaybackInfoResponse]) throws {
        state = PlaybackInfoURLProtocolState(responses: responses)
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

    private static let lock = NSLock()
    private static var states: [String: PlaybackInfoURLProtocolState] = [:]

    static func register(state: PlaybackInfoURLProtocolState) -> String {
        let stateID = UUID().uuidString
        lock.lock()
        defer { lock.unlock() }
        states[stateID] = state
        return stateID
    }

    static func unregister(stateID: String) {
        lock.lock()
        defer { lock.unlock() }
        states[stateID] = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.hasSuffix("/PlaybackInfo") == true
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
        guard let stateID = request.value(forHTTPHeaderField: stateHeaderName) else {
            throw URLError(.badServerResponse)
        }

        lock.lock()
        defer { lock.unlock() }

        guard let state = states[stateID] else {
            throw URLError(.badServerResponse)
        }
        return state
    }
}

private final class PlaybackInfoURLProtocolState {
    private let lock = NSLock()
    private var responses: [PlaybackInfoResponse]
    private var bodies: [PlaybackInfoDto] = []

    init(responses: [PlaybackInfoResponse]) {
        self.responses = responses
    }

    var recordedBodies: [PlaybackInfoDto] {
        lock.lock()
        defer { lock.unlock() }
        return bodies
    }

    func response(for request: URLRequest) throws -> PlaybackInfoResponse {
        let body = try Self.decodePlaybackInfoBody(from: request)
        lock.lock()
        defer { lock.unlock() }

        bodies.append(body)
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
