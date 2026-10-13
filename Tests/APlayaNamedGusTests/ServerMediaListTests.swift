import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@Suite("Native Jellyfin list identity")
struct ServerMediaListTests {
    let mediaID = "a0000000000000000000000000000001"
    let firstEntryID = "b0000000000000000000000000000001"
    let secondEntryID = "b0000000000000000000000000000002"

    @Test("Jellyfin dashed and compact GUIDs share identity and use N format on requests")
    func nativeGUIDFormats() throws {
        let dashed = "A0000000-0000-0000-0000-000000000001"
        let id = try #require(ServerMediaListID.uuid(dashed))
        #expect(ServerMediaListID.uuid(mediaID) == id)
        #expect(ServerMediaListID.string(id) == mediaID)
        #expect(ServerMediaListID.uuid("not-a-guid") == nil)
        #expect(ServerMediaListID.uuid("a000000000000000000000000000000g") == nil)
    }

    @Test("Duplicate playlist items preserve occurrence IDs and server order")
    func preservesDuplicateEntries() throws {
        let entries = try JellyfinMediaItemMapper.mediaListEntries(from: [
            BaseItemDto(id: mediaID, name: "Movie", playlistItemID: secondEntryID, type: .movie),
            BaseItemDto(id: mediaID, name: "Movie", playlistItemID: firstEntryID, type: .movie),
        ], kind: .playlist)
        #expect(entries.map(\.id) == [ServerMediaListID.uuid(secondEntryID), ServerMediaListID.uuid(firstEntryID)])
        #expect(entries.map(\.item.id) == [mediaID, mediaID])
    }

    @Test("Playlist members preserve audio and episode types")
    func preservesMixedMedia() throws {
        let entries = try JellyfinMediaItemMapper.mediaListEntries(from: [
            BaseItemDto(id: mediaID, playlistItemID: firstEntryID, type: .audio),
            BaseItemDto(id: firstEntryID, playlistItemID: secondEntryID, type: .episode),
        ], kind: .playlist)
        #expect(entries.map(\.item.type) == [.audio, .episode])
    }

    @Test("Collection entries use the member identity and BoxSet is a collection")
    func collectionIdentity() throws {
        let entries = try JellyfinMediaItemMapper.mediaListEntries(from: [BaseItemDto(id: mediaID, type: .movie)], kind: .collection)
        #expect(entries.first?.id == ServerMediaListID.uuid(mediaID))
        #expect(JellyfinMediaItemMapper.mediaItem(from: BaseItemDto(type: .boxSet)).type == .boxSet)
    }

    @Test("Missing occurrence IDs fail instead of inventing identities or dropping content")
    func invalidOccurrenceIDFails() {
        #expect(throws: (any Error).self) {
            try JellyfinMediaItemMapper.mediaListEntries(from: [BaseItemDto(id: mediaID, type: .movie)], kind: .playlist)
        }
    }

    @Test("Ambiguous duplicate server entry IDs are rejected without fabricating occurrences")
    func duplicateServerEntryIDFails() {
        #expect(throws: (any Error).self) {
            try JellyfinMediaItemMapper.mediaListEntries(from: [
                BaseItemDto(id: mediaID, playlistItemID: mediaID, type: .movie),
                BaseItemDto(id: mediaID, playlistItemID: mediaID, type: .movie),
            ], kind: .playlist)
        }
    }

    @Test("A native list round trip retains occurrence identity and loaded state")
    func persistsSnapshot() throws {
        let id = try #require(ServerMediaListID.uuid(mediaID))
        let entryID = try #require(ServerMediaListID.uuid(firstEntryID))
        let list = ServerMediaList(id: id, name: "Weekend", kind: .playlist, entries: [ServerMediaListEntry(id: entryID, item: MediaItem(id: mediaID, type: .movie))], canEdit: false, entriesLoaded: true)
        #expect(try JSONDecoder().decode(ServerMediaList.self, from: JSONEncoder().encode(list)) == list)
    }
}
