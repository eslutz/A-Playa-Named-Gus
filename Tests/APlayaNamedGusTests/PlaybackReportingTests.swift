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
        let resumable = MediaItem(userData: MediaUserData(playbackPositionTicks: 42))
        let fresh = MediaItem(userData: MediaUserData(playbackPositionTicks: 0))

        #expect(PlaybackTime.resumePositionTicks(for: resumable) == 42)
        #expect(PlaybackTime.resumePositionTicks(for: fresh) == nil)
    }

    @Test("keeps provider-neutral playback context values")
    func keepsProviderNeutralContextValues() {
        let context = PlaybackReportContext(
            itemID: "item-1",
            mediaSourceID: "media-1",
            playSessionID: "play-1",
            playMethod: .transcode,
            streamSelection: PlaybackStreamSelection(audioStreamIndex: 2, subtitleStreamIndex: 7)
        )

        #expect(context.itemID == "item-1")
        #expect(context.mediaSourceID == "media-1")
        #expect(context.playSessionID == "play-1")
        #expect(context.playMethod == .transcode)
        #expect(context.streamSelection.audioStreamIndex == 2)
        #expect(context.streamSelection.subtitleStreamIndex == 7)
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
        let item = MediaItem(
            chapters: [
                MediaChapterInfo(name: "Credits", startPositionTicks: 900_000_000),
                MediaChapterInfo(name: "Cold Open", startPositionTicks: 0),
                MediaChapterInfo(name: nil, startPositionTicks: 300_000_000),
            ]
        )

        let targets = PlaybackChapter.seekTargets(for: item)

        #expect(targets.map(\.title) == ["Cold Open", "Chapter 2", "Credits"])
        #expect(targets.map(\.startPositionTicks) == [0, 300_000_000, 900_000_000])
        #expect(targets[1].seconds == 30)
    }
}
