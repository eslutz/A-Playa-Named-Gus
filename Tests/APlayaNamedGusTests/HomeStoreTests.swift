@testable import Gus
import Testing

@Suite("Home store helpers")
struct HomeStoreTests {
    @Test("maps latest episodes to unique series display items with posters")
    func mapsLatestEpisodesToUniqueSeriesDisplayItems() {
        let episodes = [
            MediaItem(
                id: "episode-1",
                imageTags: [:],
                name: "Pilot",
                seriesID: "series-1",
                seriesName: "Psych",
                seriesPrimaryImageTag: "poster-1",
                type: .episode
            ),
            MediaItem(
                id: "episode-2",
                imageTags: [:],
                name: "Spellingg Bee",
                seriesID: "series-1",
                seriesName: "Psych",
                seriesPrimaryImageTag: "poster-1",
                type: .episode
            ),
            MediaItem(
                id: "episode-3",
                imageTags: [:],
                name: "The Kidnapping",
                seriesID: "series-2",
                seriesName: "Monk",
                seriesPrimaryImageTag: "poster-2",
                type: .episode
            ),
        ]

        let displayItems = LatestMediaDisplayMapper.displayItems(from: episodes, libraryCollectionType: .tvshows)

        #expect(displayItems.map(\.id) == ["series-1", "series-2"])
        #expect(displayItems.map(\.name) == ["Psych", "Monk"])
        #expect(displayItems.map(\.type) == [.series, .series])
        #expect(displayItems.first?.imageTags[MediaImageKind.primary.rawValue] == "poster-1")
    }
}
