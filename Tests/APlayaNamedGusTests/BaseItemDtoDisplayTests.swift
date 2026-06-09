@testable import Gus
import Testing

@Suite("Media item display helpers")
struct BaseItemDtoDisplayTests {
    @Test("formats runtime ticks as hours and minutes")
    func formatsRuntime() {
        let item = MediaItem(runTimeTicks: 6420 * 10_000_000)

        #expect(item.runtimeText == "1h 47m")
    }

    @Test("formats episode locators from season and episode numbers")
    func formatsEpisodeLocator() {
        let episode = MediaItem(indexNumber: 3, parentIndexNumber: 1)
        let special = MediaItem(indexNumber: 2)

        #expect(episode.episodeLocator == "S1·E3")
        #expect(special.episodeLocator == "E2")
    }

    @Test("falls back to the title when an episode number is absent")
    func fallsBackToNameForEpisodeLocator() {
        let item = MediaItem(name: "Pilot")

        #expect(item.episodeLocator == "Pilot")
    }

    @Test("formats community rating with one decimal place")
    func formatsCommunityRating() {
        let item = MediaItem(communityRating: 8.234)

        #expect(item.communityRatingText == "★ 8.2")
    }

    @Test("converts played percentage into fractional playback progress")
    func calculatesPlaybackProgress() {
        let item = MediaItem(userData: MediaUserData(playedPercentage: 37.5))

        #expect(item.playbackProgress == 0.375)
    }

    @Test("formats richer optional metadata only when fields are present")
    func formatsRicherMetadata() {
        let item = MediaItem(
            criticRating: 83,
            genres: ["Comedy", "Mystery"],
            people: [
                MediaPerson(name: "James Roday Rodriguez", role: "Shawn Spencer"),
                MediaPerson(name: "Dule Hill"),
            ],
            studios: [MediaStudio(name: "USA Network")],
            taglines: ["Fake psychic. Real detective."]
        )

        #expect(item.criticRatingText == "83%")
        #expect(item.genreText == "Comedy, Mystery")
        #expect(item.studioText == "USA Network")
        #expect(item.primaryTagline == "Fake psychic. Real detective.")
        #expect(item.peopleText == ["James Roday Rodriguez as Shawn Spencer", "Dule Hill"])
    }

    @Test("omits empty richer metadata")
    func omitsEmptyRicherMetadata() {
        let item = MediaItem(genres: [], people: [], studios: [], taglines: [])

        #expect(item.criticRatingText == nil)
        #expect(item.genreText == nil)
        #expect(item.studioText == nil)
        #expect(item.primaryTagline == nil)
        #expect(item.peopleText.isEmpty)
    }
}
