import Foundation
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
            playMethod: .transcode,
            streamSelection: PlaybackStreamSelection(audioStreamIndex: 2, subtitleStreamIndex: 7)
        )

        let payload = context.stateInfo(positionTicks: 123, isPaused: false)

        #expect(payload.itemID == "item-1")
        #expect(payload.mediaSourceID == "media-1")
        #expect(payload.playSessionID == "play-1")
        #expect(payload.playMethod == .transcode)
        #expect(payload.positionTicks == 123)
        #expect(payload.isPaused == false)
        #expect(payload.canSeek == true)
        #expect(payload.audioStreamIndex == 2)
        #expect(payload.subtitleStreamIndex == 7)
    }

    @Test("builds playback stop payloads from stream metadata")
    func buildsStopPayload() {
        let context = PlaybackReportContext(
            itemID: "item-1",
            mediaSourceID: "media-1",
            playSessionID: "play-1",
            playMethod: .directStream,
            streamSelection: .none
        )

        let payload = context.stopInfo(positionTicks: 456)

        #expect(payload.itemID == "item-1")
        #expect(payload.mediaSourceID == "media-1")
        #expect(payload.playSessionID == "play-1")
        #expect(payload.positionTicks == 456)
        #expect(payload.isFailed == false)
    }

    @Test("builds playback info requests with selected stream indices")
    func buildsPlaybackInfoWithSelectedStreams() {
        let selection = PlaybackStreamSelection(audioStreamIndex: 2, subtitleStreamIndex: 7)

        let body = StreamURLBuilder.playbackInfoBody(
            userID: "user-1",
            maxStreamingBitrate: 42_000_000,
            streamSelection: selection,
            startTimeTicks: 123
        )
        let parameters = StreamURLBuilder.playbackInfoParameters(
            userID: "user-1",
            maxStreamingBitrate: 42_000_000,
            streamSelection: selection,
            startTimeTicks: 123
        )

        #expect(body.audioStreamIndex == 2)
        #expect(body.subtitleStreamIndex == 7)
        #expect(body.startTimeTicks == 123)
        #expect(parameters.audioStreamIndex == 2)
        #expect(parameters.subtitleStreamIndex == 7)
        #expect(parameters.startTimeTicks == 123)
    }

    @Test("maps chapters into ordered seek targets")
    func mapsChaptersIntoSeekTargets() {
        let item = BaseItemDto(
            chapters: [
                ChapterInfo(name: "Credits", startPositionTicks: 900_000_000),
                ChapterInfo(name: "Cold Open", startPositionTicks: 0),
                ChapterInfo(name: nil, startPositionTicks: 300_000_000),
            ]
        )

        let targets = PlaybackChapter.seekTargets(for: item)

        #expect(targets.map(\.title) == ["Cold Open", "Chapter 2", "Credits"])
        #expect(targets.map(\.startPositionTicks) == [0, 300_000_000, 900_000_000])
        #expect(targets[1].seconds == 30)
    }

    @Test("prefers a local playback URL when available")
    func resolvesLocalPlaybackURLBeforeRemote() throws {
        let local = try #require(URL(string: "file:///tmp/gus-local.mp4"))
        let remote = try #require(URL(string: "https://jellyfin.example.com/video.m3u8"))

        #expect(resolvePlaybackURL(local: local, remote: remote) == local)
        #expect(resolvePlaybackURL(local: nil, remote: remote) == remote)
    }
}
