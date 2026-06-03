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
}
