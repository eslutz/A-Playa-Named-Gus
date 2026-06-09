import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@Suite("Provider architecture")
struct ProviderArchitectureTests {
    @Test("session credential accounts are provider qualified and expose the legacy Jellyfin account")
    func sessionCredentialProviderQualifiedAccount() {
        let credential = SessionCredential(providerKind: .jellyfin, serverID: "server-1", userID: "user-1")

        #expect(credential.account == "jellyfin:server-1:user-1")
        #expect(credential.legacyAccount == "server-1:user-1")
    }

    @Test("stored servers and users decode legacy records as Jellyfin")
    func legacyServerAndUserRecordsDecodeAsJellyfin() throws {
        let serverJSON = """
        {
          "id": "server-1",
          "name": "Psych Office",
          "url": "https://jellyfin.example.com"
        }
        """
        let userJSON = """
        {
          "id": "user-1",
          "name": "Gus",
          "serverID": "server-1",
          "primaryImageTag": "tag-1"
        }
        """

        let server = try JSONDecoder().decode(ServerConnection.self, from: Data(serverJSON.utf8))
        let user = try JSONDecoder().decode(StoredUser.self, from: Data(userJSON.utf8))

        #expect(server.providerKind == .jellyfin)
        #expect(user.providerKind == .jellyfin)
        #expect(SessionCredential(user: user).account == "jellyfin:server-1:user-1")
        #expect(SessionCredential(user: user).legacyAccount == "server-1:user-1")
    }

    @Test("Jellyfin mapper preserves display playback image and download fields")
    func jellyfinMapperPreservesCoreMediaFields() {
        let item = BaseItemDto(
            backdropImageTags: ["backdrop-tag"],
            canDownload: true,
            chapters: [
                ChapterInfo(name: "Cold Open", startPositionTicks: 10_000_000),
            ],
            collectionType: .movies,
            communityRating: 8.2,
            container: "mp4",
            criticRating: 91,
            genres: ["Comedy"],
            id: "item-1",
            imageTags: [ImageType.primary.rawValue: "primary-tag"],
            indexNumber: 3,
            mediaSources: [
                MediaSourceInfo(
                    container: "mp4",
                    id: "source-1",
                    mediaStreams: [
                        MediaStream(codec: "h264", displayTitle: "1080p", index: 0, type: .video),
                        MediaStream(codec: "aac", displayTitle: "English", index: 1, isDefault: true, language: "eng", type: .audio),
                    ],
                    videoType: .videoFile
                ),
            ],
            name: "Office Space",
            officialRating: "PG-13",
            overview: "A movie.",
            parentIndexNumber: 1,
            people: [
                BaseItemPerson(id: "person-1", name: "Dule Hill", primaryImageTag: "person-tag", role: "Gus"),
            ],
            productionYear: 1999,
            runTimeTicks: 6420 * 10_000_000,
            studios: [
                NameIDPair(name: "Psych Studios"),
            ],
            taglines: ["Work happens."],
            type: .movie,
            userData: UserItemDataDto(playbackPositionTicks: 42, playedPercentage: 37.5)
        )

        let mapped = JellyfinMediaItemMapper.mediaItem(from: item)

        #expect(mapped.providerKind == .jellyfin)
        #expect(mapped.id == "item-1")
        #expect(mapped.name == "Office Space")
        #expect(mapped.type == .movie)
        #expect(mapped.collectionType == .movies)
        #expect(mapped.displayTitle == "Office Space")
        #expect(mapped.runtimeText == "1h 47m")
        #expect(mapped.episodeLocator == "S1·E3")
        #expect(mapped.genreText == "Comedy")
        #expect(mapped.studioText == "Psych Studios")
        #expect(mapped.primaryTagline == "Work happens.")
        #expect(mapped.playbackProgress == 0.375)
        #expect(mapped.imageTags[MediaImageKind.primary.rawValue] == "primary-tag")
        #expect(mapped.backdropImageTags == ["backdrop-tag"])
        #expect(mapped.canDownload == true)
        #expect(mapped.mediaSources.first?.id == "source-1")
        #expect(mapped.mediaSources.first?.mediaStreams.count == 2)
        #expect(mapped.chapters.first?.name == "Cold Open")
        #expect(mapped.people.first?.name == "Dule Hill")
    }
}
