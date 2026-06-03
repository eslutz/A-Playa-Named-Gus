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
}
