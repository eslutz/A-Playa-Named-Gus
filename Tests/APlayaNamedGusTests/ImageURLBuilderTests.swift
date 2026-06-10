import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@Suite("Image URL builder")
struct ImageURLBuilderTests {
    @Test("uses fixed image context widths")
    func usesFixedImageContextWidths() throws {
        let client = try JellyfinClientFactory.makeClient(url: #require(URL(string: "https://jellyfin.example.com")))
        let builder = ImageURLBuilder(client: client)
        let item = MediaItem(id: "item-1", imageTags: [MediaImageKind.primary.rawValue: "tag-1"])
        let backdrop = MediaItem(backdropImageTags: ["backdrop-tag"], id: "item-2")

        #expect(ImageURLBuilder.ImageContext.posterGrid.maxWidth == 360)
        #expect(ImageURLBuilder.ImageContext.posterRail.maxWidth == 260)
        #expect(ImageURLBuilder.ImageContext.backdrop.maxWidth == 1280)
        #expect(ImageURLBuilder.ImageContext.nowPlayingArtwork.maxWidth == 600)

        #expect(try #require(builder.primaryImageURL(for: item, context: .posterGrid)).absoluteString.contains("maxWidth=360"))
        #expect(try #require(builder.primaryImageURL(for: item, context: .posterRail)).absoluteString.contains("maxWidth=260"))
        #expect(try #require(builder.backdropImageURL(for: backdrop, context: .backdrop)).absoluteString.contains("maxWidth=1280"))
    }

    @Test("builds public user avatar URLs")
    func buildsPublicUserAvatarURLs() throws {
        let client = try JellyfinClientFactory.makeClient(url: #require(URL(string: "https://jellyfin.example.com")))
        let builder = ImageURLBuilder(client: client)
        let user = UserDto(id: "user-1", name: "Ava", primaryImageTag: "avatar-tag")

        let url = try #require(builder.userImageURL(for: user))

        #expect(url.absoluteString.contains("/UserImage"))
        #expect(url.absoluteString.contains("userId=user-1"))
        #expect(url.absoluteString.contains("tag=avatar-tag"))
    }
}
