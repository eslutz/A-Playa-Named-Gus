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
}
