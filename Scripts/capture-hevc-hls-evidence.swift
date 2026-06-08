#!/usr/bin/env swift

import Darwin
import Foundation

enum EvidenceError: LocalizedError {
    case missingEnvironment(String)
    case invalidURL(String)
    case invalidResponse(URL)
    case missingTranscodingURL
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case let .missingEnvironment(name):
            return "Missing required environment variable: \(name)"
        case let .invalidURL(value):
            return "Invalid URL: \(value)"
        case let .invalidResponse(url):
            return "The server did not return a valid HTTP response for \(url)"
        case .missingTranscodingURL:
            return "PlaybackInfo response did not include MediaSources[0].TranscodingUrl"
        case .invalidJSON:
            return "The PlaybackInfo response was not a JSON object"
        }
    }
}

struct Config {
    let serverURL: URL
    let accessToken: String
    let userID: String
    let itemID: String
    let maxStreamingBitrate: Int

    init(environment: [String: String]) throws {
        guard let server = environment["GUS_JELLYFIN_URL"] else {
            throw EvidenceError.missingEnvironment("GUS_JELLYFIN_URL")
        }

        let trimmedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let serverURL = URL(string: trimmedServer), serverURL.scheme != nil, serverURL.host != nil else {
            throw EvidenceError.invalidURL(server)
        }

        guard let accessToken = environment["GUS_JELLYFIN_ACCESS_TOKEN"], !accessToken.isEmpty else {
            throw EvidenceError.missingEnvironment("GUS_JELLYFIN_ACCESS_TOKEN")
        }

        guard let userID = environment["GUS_JELLYFIN_USER_ID"], !userID.isEmpty else {
            throw EvidenceError.missingEnvironment("GUS_JELLYFIN_USER_ID")
        }

        guard let itemID = environment["GUS_JELLYFIN_ITEM_ID"], !itemID.isEmpty else {
            throw EvidenceError.missingEnvironment("GUS_JELLYFIN_ITEM_ID")
        }

        self.serverURL = serverURL
        self.accessToken = accessToken
        self.userID = userID
        self.itemID = itemID
        maxStreamingBitrate = Int(environment["GUS_MAX_STREAMING_BITRATE"] ?? "") ?? 120_000_000
    }
}

enum CaptureHEVCHLSEvidence {
    static func run() async throws {
        let config = try Config(environment: ProcessInfo.processInfo.environment)
        let playbackInfo = try await requestPlaybackInfo(config: config)
        let mediaSource = try firstMediaSource(from: playbackInfo)
        let transcodingURL = try authenticatedTranscodingURL(from: mediaSource, config: config)
        let manifest = try await fetchText(transcodingURL)
        let mediaPlaylistURL = firstPlaylistURL(in: manifest, relativeTo: transcodingURL)
        let mediaPlaylist = if let mediaPlaylistURL {
            try await fetchText(mediaPlaylistURL)
        } else {
            manifest
        }
        let report = renderReport(
            playbackInfo: playbackInfo,
            mediaSource: mediaSource,
            transcodingURL: transcodingURL,
            masterPlaylist: manifest,
            mediaPlaylist: mediaPlaylist,
            config: config
        )
        print(report)
    }

    private static func requestPlaybackInfo(config: Config) async throws -> [String: Any] {
        var components = URLComponents(
            url: config.serverURL.appending(path: "Items/\(config.itemID)/PlaybackInfo"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "UserId", value: config.userID),
            URLQueryItem(name: "MaxStreamingBitrate", value: String(config.maxStreamingBitrate)),
            URLQueryItem(name: "api_key", value: config.accessToken),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: playbackInfoBody(config: config),
            options: [.sortedKeys]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200 ..< 300 ~= http.statusCode else {
            throw EvidenceError.invalidResponse(request.url!)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EvidenceError.invalidJSON
        }
        return json
    }

    private static func playbackInfoBody(config: Config) -> [String: Any] {
        [
            "UserId": config.userID,
            "MaxStreamingBitrate": config.maxStreamingBitrate,
            "EnableDirectPlay": true,
            "EnableDirectStream": true,
            "EnableTranscoding": true,
            "DeviceProfile": [
                "Name": "Gus HEVC HLS Evidence",
                "DirectPlayProfiles": [
                    [
                        "Type": "Video",
                        "Container": "mp4,m4v,mov",
                        "VideoCodec": "h264,hevc",
                        "AudioCodec": "aac,mp3,ac3,eac3,alac,flac",
                    ],
                ],
                "MaxStaticBitrate": config.maxStreamingBitrate,
                "MaxStreamingBitrate": config.maxStreamingBitrate,
                "TranscodingProfiles": [
                    [
                        "Type": "Video",
                        "Context": "Streaming",
                        "Protocol": "hls",
                        "Container": "mp4",
                        "VideoCodec": "hevc",
                        "AudioCodec": "aac",
                        "MaxAudioChannels": "2",
                        "MinSegments": 2,
                        "EnableMpegtsM2TsMode": false,
                    ],
                    [
                        "Type": "Video",
                        "Context": "Streaming",
                        "Protocol": "hls",
                        "Container": "ts",
                        "VideoCodec": "h264",
                        "AudioCodec": "aac",
                        "MaxAudioChannels": "2",
                        "MinSegments": 2,
                        "EnableMpegtsM2TsMode": true,
                    ],
                ],
            ],
        ]
    }

    private static func firstMediaSource(from playbackInfo: [String: Any]) throws -> [String: Any] {
        guard let mediaSources = playbackInfo["MediaSources"] as? [[String: Any]],
              let first = mediaSources.first
        else {
            throw EvidenceError.missingTranscodingURL
        }
        return first
    }

    private static func authenticatedTranscodingURL(from mediaSource: [String: Any], config: Config) throws -> URL {
        guard let path = mediaSource["TranscodingUrl"] as? String else {
            throw EvidenceError.missingTranscodingURL
        }

        guard let baseURL = URL(string: path, relativeTo: config.serverURL)?.absoluteURL else {
            throw EvidenceError.invalidURL(path)
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var queryItems = components.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "api_key" }) {
            queryItems.append(URLQueryItem(name: "api_key", value: config.accessToken))
        }
        components.queryItems = queryItems
        return components.url!
    }

    private static func fetchText(_ url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200 ..< 300 ~= http.statusCode else {
            throw EvidenceError.invalidResponse(url)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func firstPlaylistURL(in manifest: String, relativeTo baseURL: URL) -> URL? {
        manifest
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
            .flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
    }

    private static func renderReport(
        playbackInfo: [String: Any],
        mediaSource: [String: Any],
        transcodingURL: URL,
        masterPlaylist: String,
        mediaPlaylist: String,
        config: Config
    ) -> String {
        let transcodingContainer = mediaSource["TranscodingContainer"] as? String ?? "(missing)"
        let transcodingSubProtocol = mediaSource["TranscodingSubProtocol"] as? String ?? "(missing)"
        let redactedURL = redacted(transcodingURL, config: config)
        let codecsLine = masterPlaylist
            .split(separator: "\n")
            .first { $0.contains("CODECS=") }
            .map { redact(String($0), config: config) } ?? "(missing)"
        let hasHEVCCodec = codecsLine.localizedCaseInsensitiveContains("hvc1")
            || codecsLine.localizedCaseInsensitiveContains("hev1")
        let hasFMP4Map = mediaPlaylist.contains("#EXT-X-MAP")
        let mediaSegments = mediaPlaylist
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let firstSegment = mediaSegments.first.map { redact($0, config: config) } ?? "(missing)"
        let lowercasedFirstSegment = firstSegment.lowercased()
        let firstSegmentLooksFMP4 = lowercasedFirstSegment.hasSuffix(".m4s")
            || lowercasedFirstSegment.hasSuffix(".mp4")
        let passed = ["mp4", "fmp4"].contains(transcodingContainer.lowercased())
            && transcodingSubProtocol.lowercased() == "hls"
            && hasHEVCCodec
            && (hasFMP4Map || firstSegmentLooksFMP4)

        return """
        # HEVC HLS Evidence

        ## PlaybackInfo

        - TranscodingUrl: \(redactedURL)
        - TranscodingContainer: \(transcodingContainer)
        - TranscodingSubProtocol: \(transcodingSubProtocol)

        ## Playlist

        - CODECS line: \(codecsLine)
        - Contains HEVC codec: \(hasHEVCCodec)
        - Contains EXT-X-MAP: \(hasFMP4Map)
        - First media segment: \(firstSegment)
        - First media segment looks fMP4: \(firstSegmentLooksFMP4)

        ## Evidence Gate

        - Automated gate passed: \(passed)
        - Manual iOS playback passed: false
        - Manual tvOS playback passed: false

        ## Raw PlaybackInfo Keys

        \(playbackInfo.keys.sorted().joined(separator: ", "))
        """
    }

    private static func redacted(_ url: URL, config: Config) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.scheme = "https"
        components.host = "jellyfin.example.com"
        components.queryItems = components.queryItems?.map { item in
            item.name == "api_key" ? URLQueryItem(name: item.name, value: "REDACTED") : item
        }
        return redact(components.url?.absoluteString ?? "REDACTED_URL", config: config)
    }

    private static func redact(_ value: String, config: Config) -> String {
        value
            .replacingOccurrences(of: config.accessToken, with: "REDACTED")
            .replacingOccurrences(of: config.userID, with: "REDACTED_USER_ID")
            .replacingOccurrences(of: config.itemID, with: "REDACTED_ITEM_ID")
    }
}

do {
    try await CaptureHEVCHLSEvidence.run()
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
