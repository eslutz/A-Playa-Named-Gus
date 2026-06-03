@testable import Gus
import JellyfinAPI
import Testing

@Suite("BaseItemDto display helpers")
struct BaseItemDtoDisplayTests {
    @Test("formats runtime ticks as hours and minutes")
    func formatsRuntime() {
        let item = BaseItemDto(runTimeTicks: 6420 * 10_000_000)

        #expect(item.runtimeText == "1h 47m")
    }

    @Test("formats episode locators from season and episode numbers")
    func formatsEpisodeLocator() {
        let episode = BaseItemDto(indexNumber: 3, parentIndexNumber: 1)
        let special = BaseItemDto(indexNumber: 2)

        #expect(episode.episodeLocator == "S1·E3")
        #expect(special.episodeLocator == "E2")
    }

    @Test("falls back to the title when an episode number is absent")
    func fallsBackToNameForEpisodeLocator() {
        let item = BaseItemDto(name: "Pilot")

        #expect(item.episodeLocator == "Pilot")
    }

    @Test("formats community rating with one decimal place")
    func formatsCommunityRating() {
        let item = BaseItemDto(communityRating: 8.234)

        #expect(item.communityRatingText == "★ 8.2")
    }

    @Test("converts played percentage into fractional playback progress")
    func calculatesPlaybackProgress() {
        let item = BaseItemDto(userData: UserItemDataDto(playedPercentage: 37.5))

        #expect(item.playbackProgress == 0.375)
    }
}
