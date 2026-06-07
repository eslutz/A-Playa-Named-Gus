@testable import Gus
import JellyfinAPI
import Testing

@Suite("Home store helpers")
struct HomeStoreTests {
    @Test("groups latest TV library media by series")
    func groupsLatestTVLibraryMediaBySeries() {
        let tvLibrary = BaseItemDto(collectionType: .tvshows, id: "tv", name: "TV Shows")
        let movieLibrary = BaseItemDto(collectionType: .movies, id: "movies", name: "Movies")

        let tvParameters = LatestMediaRequest.parameters(userID: "user-1", library: tvLibrary)
        let movieParameters = LatestMediaRequest.parameters(userID: "user-1", library: movieLibrary)

        #expect(tvParameters.parentID == "tv")
        #expect(tvParameters.isGroupItems == true)
        #expect(movieParameters.parentID == "movies")
        #expect(movieParameters.isGroupItems == false)
    }

    @Test("maps latest episodes to unique series display items with posters")
    func mapsLatestEpisodesToUniqueSeriesDisplayItems() {
        let episodes = [
            BaseItemDto(
                id: "episode-1",
                name: "Pilot",
                seriesID: "series-1",
                seriesName: "Psych",
                seriesPrimaryImageTag: "poster-1",
                type: .episode
            ),
            BaseItemDto(
                id: "episode-2",
                name: "Spellingg Bee",
                seriesID: "series-1",
                seriesName: "Psych",
                seriesPrimaryImageTag: "poster-1",
                type: .episode
            ),
            BaseItemDto(
                id: "episode-3",
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
        #expect(displayItems.first?.imageTags?[ImageType.primary.rawValue] == "poster-1")
    }
}
