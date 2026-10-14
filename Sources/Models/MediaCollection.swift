import Foundation

/// A library object, never a queue or a playlist occurrence.
struct MediaCollection: Identifiable, Equatable, Sendable {
    var id: String {
        item.id ?? ""
    }

    var item: MediaItem
    var members: [MediaItem] = []
    var membersLoaded = false
}

struct CollectionCapabilities: Equatable, Sendable {
    var create = false
    var editMetadata = false
    var editArtwork = false
    var delete = false
    var addMembers = false
    var removeMembers = false

    /// Never report a draft as saved while silently omitting its selected artwork.
    func permitsEdit(artworkIncluded: Bool) -> Bool {
        (!artworkIncluded || editArtwork) && (editMetadata || (artworkIncluded && editArtwork))
    }
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
