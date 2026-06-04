@testable import Gus
import JellyfinAPI
import Testing

@Suite("Library store helpers")
struct LibraryStoreTests {
    @Test("builds paged library parameters with total counts download metadata and rich fields")
    func buildsPagedLibraryParameters() {
        let parameters = LibraryRequest.parameters(
            userID: "user-1",
            parentID: "library-1",
            startIndex: 60,
            limit: 60
        )

        #expect(parameters.userID == "user-1")
        #expect(parameters.parentID == "library-1")
        #expect(parameters.startIndex == 60)
        #expect(parameters.limit == 60)
        #expect(parameters.isRecursive == false)
        #expect(parameters.sortOrder == [.ascending])
        #expect(parameters.sortBy == [.sortName])
        #expect(parameters.enableUserData == true)
        #expect(parameters.enableImages == true)
        #expect(parameters.enableTotalRecordCount == true)
        #expect(parameters.fields == LibraryRequest.metadataFields)
        #expect(parameters.fields?.contains(.canDownload) == true)
        #expect(parameters.fields?.contains(.mediaStreams) == true)
        #expect(parameters.fields?.contains(.chapters) == true)
    }

    @Test("applies status filters and sort options to library parameters")
    func appliesStatusFiltersAndSortOptions() {
        let parameters = LibraryRequest.parameters(
            userID: "user-1",
            parentID: "library-1",
            startIndex: 0,
            limit: 60,
            filter: LibraryFilterState(sort: .recentlyAdded, status: .unplayed)
        )

        #expect(parameters.sortOrder == [.descending])
        #expect(parameters.sortBy == [.dateCreated])
        #expect(parameters.filters == [.isUnplayed])
    }

    @Test("builds favorites and random filter parameters")
    func buildsFavoritesAndRandomFilterParameters() {
        let parameters = LibraryRequest.parameters(
            userID: "user-1",
            parentID: "library-1",
            startIndex: 0,
            limit: 60,
            filter: LibraryFilterState(sort: .random, status: .favorites)
        )

        #expect(parameters.sortOrder == nil)
        #expect(parameters.sortBy == [.random])
        #expect(parameters.filters == [.isFavorite])
    }
}
