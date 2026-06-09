@testable import Gus
import Testing

@Suite("Series detail helpers")
struct SeriesDetailStoreTests {
    @Test("prefers the first numbered season as the initial selection")
    func choosesInitialSeason() {
        let special = MediaItem(id: "specials", indexNumber: 0, name: "Specials")
        let firstSeason = MediaItem(id: "season-1", indexNumber: 1, name: "Season 1")

        #expect(SeriesRequest.initialSeasonID(from: [special, firstSeason]) == "season-1")
    }

    @Test("falls back to specials when no numbered season exists")
    func fallsBackToSpecials() {
        let special = MediaItem(id: "specials", indexNumber: 0, name: "Specials")

        #expect(SeriesRequest.initialSeasonID(from: [special]) == "specials")
    }
}
