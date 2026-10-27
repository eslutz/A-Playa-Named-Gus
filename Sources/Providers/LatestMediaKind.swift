import Foundation

/// Recently added content is a media-type feed spanning all permitted libraries.
enum LatestMediaKind: String, CaseIterable, Sendable {
    case movies, shows, music, books, audiobooks, photos, videos

    var title: String {
        switch self {
        case .movies: String(localized: "Recently Added Movies")
        case .shows: String(localized: "Recently Added Shows")
        case .music: String(localized: "Recently Added Music")
        case .books: String(localized: "Recently Added Books")
        case .audiobooks: String(localized: "Recently Added Audiobooks")
        case .photos: String(localized: "Recently Added Photos")
        case .videos: String(localized: "Recently Added Videos")
        }
    }

    var includeTypes: [MediaItemType] {
        switch self {
        case .movies: [.movie]
        case .shows: [.episode, .series]
        case .music: [.musicAlbum]
        case .books: [.book]
        case .audiobooks: [.audioBook]
        case .photos: [.photo]
        case .videos: [.video]
        }
    }

    func displayItems(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.compactMap { item in
            let display = self == .shows ? item.latestTVDisplayItem : item
            guard let id = display.id, seen.insert(id).inserted else { return nil }
            return display
        }
    }
}

extension MediaProviderSession {
    /// Uses user-scoped server ordering; no six-library cap or client date guesses.
    func latestMedia(kind: LatestMediaKind, startIndex: Int, limit: Int) async throws -> MediaItemPage {
        try await items(query: MediaItemQuery(includeTypes: kind.includeTypes, startIndex: startIndex, limit: limit, isRecursive: true, sort: .recentlyAdded))
    }
}
