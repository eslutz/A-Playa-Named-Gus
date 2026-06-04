import Foundation
import JellyfinAPI

/// Builds image URLs for `BaseItemDto`s via `client.url(with: Paths.getItemImage(...))`.
///
/// Pattern reference: Swiftfin's `BaseItemDto+Images`. We deliberately request by
/// `maxWidth` (server-side resize) rather than multiplying by `UIScreen.main.scale`,
/// which doesn't exist on macOS.
struct ImageURLBuilder {
    enum ImageContext: Int {
        case posterGrid = 360
        case posterRail = 260
        case backdrop = 1280
        case nowPlayingArtwork = 600

        var maxWidth: Int {
            rawValue
        }
    }

    let client: JellyfinClient

    /// Primary (poster) image for an item, falling back to the series' primary image
    /// for episodes when the item itself has no primary tag.
    func primaryImageURL(for item: BaseItemDto, context: ImageContext) -> URL? {
        primaryImageURL(for: item, maxWidth: context.maxWidth)
    }

    func primaryImageURL(for item: BaseItemDto, maxWidth: Int = 400) -> URL? {
        if let id = item.id, let tag = item.imageTags?[ImageType.primary.rawValue] {
            return imageURL(itemID: id, type: .primary, tag: tag, maxWidth: maxWidth)
        }
        if let seriesID = item.seriesID, let tag = item.seriesPrimaryImageTag {
            return imageURL(itemID: seriesID, type: .primary, tag: tag, maxWidth: maxWidth)
        }
        if let id = item.id {
            return imageURL(itemID: id, type: .primary, tag: nil, maxWidth: maxWidth)
        }
        return nil
    }

    /// Wide backdrop image for an item, falling back to the parent's backdrop.
    func backdropImageURL(for item: BaseItemDto, context: ImageContext) -> URL? {
        backdropImageURL(for: item, maxWidth: context.maxWidth)
    }

    func backdropImageURL(for item: BaseItemDto, maxWidth: Int = 1280) -> URL? {
        if let id = item.id, let tag = item.backdropImageTags?.first {
            return imageURL(itemID: id, type: .backdrop, tag: tag, maxWidth: maxWidth)
        }
        if let parentID = item.parentID, let tag = item.parentBackdropImageTags?.first {
            return imageURL(itemID: parentID, type: .backdrop, tag: tag, maxWidth: maxWidth)
        }
        // Some items only ship a primary image; use it as a last-resort backdrop.
        return primaryImageURL(for: item, maxWidth: maxWidth)
    }

    func imageURL(itemID: String, type: ImageType, tag: String?, maxWidth: Int) -> URL? {
        let parameters = Paths.GetItemImageParameters(
            maxWidth: maxWidth,
            tag: tag
        )
        let request = Paths.getItemImage(
            itemID: itemID,
            imageType: type.rawValue,
            parameters: parameters
        )
        return client.url(with: request)
    }

    func userImageURL(for user: UserDto) -> URL? {
        guard let userID = user.id else { return nil }
        let parameters = Paths.GetUserImageParameters(
            userID: userID,
            tag: user.primaryImageTag,
            format: .jpg
        )
        return client.url(with: Paths.getUserImage(parameters: parameters))
    }
}
