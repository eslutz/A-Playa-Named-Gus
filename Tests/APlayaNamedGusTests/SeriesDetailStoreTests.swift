@testable import Gus
import JellyfinAPI
import Testing

@Suite("Series detail helpers")
struct SeriesDetailStoreTests {
    @Test("builds season request parameters with detail metadata fields")
    func buildsSeasonParameters() {
        let parameters = SeriesRequest.seasonsParameters(userID: "user-1")

        #expect(parameters.userID == "user-1")
        #expect(parameters.fields == SearchRequest.metadataFields)
        #expect(parameters.enableImages == true)
        #expect(parameters.enableUserData == true)
    }

    @Test("builds episode request parameters for the selected season")
    func buildsEpisodeParameters() {
        let parameters = SeriesRequest.episodesParameters(userID: "user-1", seasonID: "season-1")

        #expect(parameters.userID == "user-1")
        #expect(parameters.seasonID == "season-1")
        #expect(parameters.startIndex == 0)
        #expect(parameters.limit == 300)
        #expect(parameters.fields == SearchRequest.metadataFields)
        #expect(parameters.enableImages == true)
        #expect(parameters.enableUserData == true)
    }

    @Test("prefers the first numbered season as the initial selection")
    func choosesInitialSeason() {
        let special = BaseItemDto(id: "specials", indexNumber: 0, name: "Specials")
        let firstSeason = BaseItemDto(id: "season-1", indexNumber: 1, name: "Season 1")

        #expect(SeriesRequest.initialSeasonID(from: [special, firstSeason]) == "season-1")
    }
}
