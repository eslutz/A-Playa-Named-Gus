import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@Suite("AVPlayer device profile")
struct StreamURLBuilderTests {
    @Test("biases playback toward HLS transcoding while preserving direct-play containers")
    func avPlayerProfileUsesHLSAndAVKitContainers() {
        let profile = StreamURLBuilder.avPlayerProfile(maxStreamingBitrate: 42_000_000)
        let directPlay = profile.directPlayProfiles?.first
        let transcoding = profile.transcodingProfiles?.first

        #expect(profile.maxStaticBitrate == 42_000_000)
        #expect(profile.maxStreamingBitrate == 42_000_000)
        #expect(directPlay?.container == "mp4,m4v,mov")
        #expect(directPlay?.videoCodec == "h264,hevc")
        #expect(transcoding?.protocol == .hls)
        #expect(transcoding?.container == "ts")
        #expect(transcoding?.audioCodec == "aac")
        #expect(transcoding?.videoCodec == "h264,hevc")
        #expect(transcoding?.type == .video)
        #expect(transcoding?.context == .streaming)
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

    @Test("resolvePlayback retries in 2D when a stereo source cannot direct play")
    func resolvePlaybackFallsBackTo2DWhenStereoDirectPlayIsUnavailable() async throws {
        let stereoLayout = Stereo3DLayout.sideBySide(half: true)
        PlaybackInfoURLProtocol.configure(responses: [
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

        let builder = try StreamURLBuilder(
            client: makePlaybackInfoClient(),
            userID: "user-1"
        )

        let resolution = try await builder.resolvePlayback(
            for: "item-1",
            maxStreamingBitrate: 42_000_000,
            stereoLayout: stereoLayout
        )
        let requests = PlaybackInfoURLProtocol.recordedPlaybackInfoBodies

        #expect(resolution.url.absoluteString == "https://jellyfin.example.com/Videos/item-1/master.m3u8")
        #expect(resolution.playSessionID == "session-2d")
        #expect(resolution.mediaSourceID == "fallback-source")
        #expect(resolution.isTranscoding)
        #expect(resolution.stereoLayout == .none)
        #expect(resolution.stereoFallbackReason == .directPlayUnavailable(stereoLayout))

        #expect(requests.map(\.enableTranscoding) == [false, true])
        #expect(requests.first?.deviceProfile?.transcodingProfiles?.isEmpty == true)
        #expect(requests.last?.deviceProfile?.transcodingProfiles?.first?.protocol == .hls)
    }

    private func makePlaybackInfoClient() throws -> JellyfinClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaybackInfoURLProtocol.self]
        return try JellyfinClient(
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
}

private final class PlaybackInfoURLProtocol: URLProtocol {
    private static let state = PlaybackInfoURLProtocolState()

    static var recordedPlaybackInfoBodies: [PlaybackInfoDto] {
        state.recordedBodies
    }

    static func configure(responses: [PlaybackInfoResponse]) {
        state.configure(responses: responses)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.hasSuffix("/PlaybackInfo") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let responseBody = try Self.state.response(for: request)
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
}

private final class PlaybackInfoURLProtocolState {
    private let lock = NSLock()
    private var responses: [PlaybackInfoResponse] = []
    private var bodies: [PlaybackInfoDto] = []

    var recordedBodies: [PlaybackInfoDto] {
        lock.lock()
        defer { lock.unlock() }
        return bodies
    }

    func configure(responses: [PlaybackInfoResponse]) {
        lock.lock()
        defer { lock.unlock() }
        self.responses = responses
        bodies = []
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
