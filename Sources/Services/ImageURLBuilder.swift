import Foundation
import JellyfinAPI

/// The visual purpose of artwork determines candidate identity and aspect ratio.
enum MediaArtworkRole: Equatable, Sendable {
    case poster
    case episodeStill
    case backdrop
    case square
    case photo
    case avatar
    case chapter(index: Int, tag: String?)
}

/// A semantic role plus a server-sized rendition. URL identity retains the
/// origin, content tag, image index and requested dimensions.
struct MediaArtworkRequest: Equatable, Sendable {
    let role: MediaArtworkRole
    let maxWidth: Int
}

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

    func imageURL(itemID: String, type: ImageType, tag: String?, maxWidth: Int, imageIndex: Int? = nil) -> URL? {
        let parameters = Paths.GetItemImageParameters(
            maxWidth: maxWidth,
            tag: tag,
            imageIndex: imageIndex
        )
        let request = Paths.getItemImage(
            itemID: itemID,
            imageType: type.rawValue,
            parameters: parameters
        )
        return client.url(with: request)
    }

    /// Primary (poster) image for a provider-neutral media item, falling back to the
    /// series' primary image for episodes when the item itself has no primary tag.
    func primaryImageURL(for item: MediaItem, context: ImageContext) -> URL? {
        primaryImageURL(for: item, maxWidth: context.maxWidth)
    }

    func primaryImageURL(for item: MediaItem, maxWidth: Int = 400) -> URL? {
        artworkURLs(for: item, request: .init(role: .poster, maxWidth: maxWidth)).first
    }

    func backdropImageURL(for item: MediaItem, context: ImageContext) -> URL? {
        backdropImageURL(for: item, maxWidth: context.maxWidth)
    }

    func backdropImageURL(for item: MediaItem, maxWidth: Int = 1280) -> URL? {
        artworkURLs(for: item, request: .init(role: item.type == .episode ? .episodeStill : .backdrop, maxWidth: maxWidth)).first
    }

    /// An episode still never inherits a parent portrait. A portrait episode card
    /// represents its series before trying the episode's own landscape primary.
    func artworkURLs(for item: MediaItem, request: MediaArtworkRequest) -> [URL] {
        // Generic search and library cards have no membership snapshot from which
        // to choose an admitted fallback. Never fetch an unverified playlist mosaic.
        if item.type == .playlist, ContentRatingGate.storedLimit() != .off {
            return []
        }
        let role = request.role
        let maxWidth = request.maxWidth
        if case let .chapter(index, tag) = role {
            guard let id = item.id, index >= 0 else { return [] }
            return imageURL(itemID: id, type: .chapter, tag: tag, maxWidth: maxWidth, imageIndex: index).map { [$0] } ?? []
        }
        let ownPrimary = item.id.flatMap { imageURL(itemID: $0, type: .primary, tag: item.imageTags["Primary"], maxWidth: maxWidth) }
        let seriesPrimary = item.seriesID.flatMap { id in
            item.seriesPrimaryImageTag.flatMap { imageURL(itemID: id, type: .primary, tag: $0, maxWidth: maxWidth) }
        }
        let ownBackdrop = item.id.flatMap { id in item.backdropImageTags.first.flatMap { imageURL(itemID: id, type: .backdrop, tag: $0, maxWidth: maxWidth) } }
        let parentBackdrop = item.parentBackdropItemID.flatMap { id in item.parentBackdropImageTags.first.flatMap { imageURL(itemID: id, type: .backdrop, tag: $0, maxWidth: maxWidth) } }
        let thumb = item.id.flatMap { id in item.imageTags["Thumb"].flatMap { imageURL(itemID: id, type: .thumb, tag: $0, maxWidth: maxWidth) } }
        let candidates: [URL?]
        switch role {
        case .poster:
            candidates = item.type == .episode ? [seriesPrimary, ownPrimary, thumb, ownBackdrop, parentBackdrop] : [ownPrimary, seriesPrimary, thumb, ownBackdrop, parentBackdrop]
        case .episodeStill:
            let landscapePrimary = item.primaryImageAspectRatio.map { $0 >= 1.33 } ?? true
            candidates = [landscapePrimary ? ownPrimary : nil, thumb, ownBackdrop, parentBackdrop]
        case .backdrop:
            candidates = [ownBackdrop, parentBackdrop, thumb, ownPrimary]
        case .square:
            let albumCover = item.albumID.flatMap { id in
                item.albumPrimaryImageTag.flatMap { imageURL(itemID: id, type: .primary, tag: $0, maxWidth: maxWidth) }
            }
            candidates = item.imageTags["Primary"] == nil ? [albumCover, ownPrimary, thumb, ownBackdrop] : [ownPrimary, albumCover, thumb, ownBackdrop]
        case .photo, .avatar:
            candidates = [ownPrimary]
        case .chapter:
            candidates = []
        }
        return ArtworkRequestSequence.unique(candidates.compactMap { $0 })
    }

    func personImageURL(for person: MediaPerson, maxWidth: Int = 240) -> URL? {
        guard let personID = person.id else { return nil }
        return artworkURLs(for: MediaItem(id: personID, imageTags: person.primaryImageTag.map { ["Primary": $0] } ?? [:]), request: .init(role: .avatar, maxWidth: maxWidth)).first
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
