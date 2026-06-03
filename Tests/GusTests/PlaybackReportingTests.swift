@testable import Gus
import JellyfinAPI
import Testing

@Suite("Playback reporting")
struct PlaybackReportingTests {
    @Test("converts between seconds and Jellyfin ticks")
    func convertsSecondsAndTicks() {
        #expect(PlaybackTime.ticks(fromSeconds: 12.5) == 125_000_000)
        #expect(PlaybackTime.seconds(fromTicks: 90_000_000) == 9.0)
    }

    @Test("uses saved playback position only when it is positive")
    func extractsResumeTicks() {
        let resumable = BaseItemDto(userData: UserItemDataDto(playbackPositionTicks: 42))
        let fresh = BaseItemDto(userData: UserItemDataDto(playbackPositionTicks: 0))

        #expect(PlaybackTime.resumePositionTicks(for: resumable) == 42)
        #expect(PlaybackTime.resumePositionTicks(for: fresh) == nil)
    }

    @Test("builds playback state payloads from stream metadata")
    func buildsStatePayload() {
        let context = PlaybackReportContext(
            itemID: "item-1",
            mediaSourceID: "media-1",
            playSessionID: "play-1",
            playMethod: .transcode
        )

        let payload = context.stateInfo(positionTicks: 123, isPaused: false)

        #expect(payload.itemID == "item-1")
        #expect(payload.mediaSourceID == "media-1")
        #expect(payload.playSessionID == "play-1")
        #expect(payload.playMethod == .transcode)
        #expect(payload.positionTicks == 123)
        #expect(payload.isPaused == false)
        #expect(payload.canSeek == true)
    }

    @Test("builds playback stop payloads from stream metadata")
    func buildsStopPayload() {
        let context = PlaybackReportContext(
            itemID: "item-1",
            mediaSourceID: "media-1",
            playSessionID: "play-1",
            playMethod: .directStream
        )

        let payload = context.stopInfo(positionTicks: 456)

        #expect(payload.itemID == "item-1")
        #expect(payload.mediaSourceID == "media-1")
        #expect(payload.playSessionID == "play-1")
        #expect(payload.positionTicks == 456)
        #expect(payload.isFailed == false)
    }
}
