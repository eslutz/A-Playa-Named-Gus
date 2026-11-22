import Foundation

/// A library object, never a queue or a playlist occurrence.
struct MediaCollection: Identifiable, Equatable, Sendable {
    var id: String {
        item.id ?? ""
    }

    var item: MediaItem
    var members: [MediaItem] = []
    var membersLoaded = false

    /// The collection ID owns its custom poster. Without one, member artwork is
    /// selected from the same snapshot for both the browser and the detail page.
    func coverItems(limit: ContentRatingGate.Limit, hideUnrated: Bool, ageCeiling: ContentRatingGate.Limit = .off) -> [MediaItem] {
        let covers = ContentRatingGate.coverMembers(members, limit: limit, hideUnrated: hideUnrated, count: 3, ageCeiling: ageCeiling)
        guard limit == .off else { return covers }
        if item.hasTaggedCoverArtwork {
            return [item] + covers
        }
        // Defer an untagged probe until membership has had a chance to supply
        // a cover. Some servers can still serve an image when the tag is absent.
        return membersLoaded ? covers + [item] : covers
    }

    @MainActor func coverURLs(using provider: any MediaProviderSession, limit: ContentRatingGate.Limit, hideUnrated: Bool, ageCeiling: ContentRatingGate.Limit = .off) -> [URL] {
        coverItems(limit: limit, hideUnrated: hideUnrated, ageCeiling: ageCeiling).flatMap { item in
            provider.artworkURLs(for: item, request: .init(role: item.coverArtworkRole, maxWidth: ImageURLBuilder.ImageContext.posterGrid.maxWidth))
        }
    }
}

/// A browse filter describes visible members. A Jellyfin collection can contain
/// several formats, and an empty collection is reachable through All.
enum CollectionFormat: CaseIterable, Hashable {
    case all, movies, books, audiobooks

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .movies: String(localized: "Movies")
        case .books: String(localized: "Books")
        case .audiobooks: String(localized: "Audiobooks")
        }
    }

    var mediaType: MediaItemType? {
        switch self {
        case .all: nil
        case .movies: .movie
        case .books: .book
        case .audiobooks: .audioBook
        }
    }

    init(type: MediaItemType?) {
        switch type {
        case .movie: self = .movies
        case .book: self = .books
        case .audioBook: self = .audiobooks
        default: self = .all
        }
    }

    func includes(_ collection: MediaCollection, admitting: (MediaItem) -> Bool = { ContentRatingGate.admitsStored($0) }) -> Bool {
        guard admitting(collection.item) else { return false }
        guard let mediaType else { return true }
        return collection.membersLoaded && collection.members.contains {
            $0.type == mediaType && admitting($0)
        }
    }
}

struct CollectionCapabilities: Equatable, Sendable {
    var create = false
    var editMetadata = false
    var editArtwork = false
    var delete = false
    var addMembers = false
    var removeMembers = false
}

enum CollectionSort: String, CaseIterable, Identifiable {
    case serverDefault, title, releaseDate
    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .serverDefault: String(localized: "Default Order")
        case .title: String(localized: "Title")
        case .releaseDate: String(localized: "Release Date")
        }
    }

    func sorted(_ items: [MediaItem]) -> [MediaItem] {
        guard self != .serverDefault else { return items }
        return items.sorted { lhs, rhs in
            if self == .releaseDate, lhs.premiereDate != rhs.premiereDate {
                return (lhs.premiereDate ?? .distantFuture) < (rhs.premiereDate ?? .distantFuture)
            }
            let result = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
            return result == .orderedSame ? (lhs.id ?? "") < (rhs.id ?? "") : result == .orderedAscending
        }
    }
}
