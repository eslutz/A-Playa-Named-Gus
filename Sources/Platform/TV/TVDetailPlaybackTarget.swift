import Foundation

/// Resolves a series action to an episode, never a container playback request.
enum TVDetailPlaybackTarget {
    static func resolve(item: MediaItem, nextUp: [NextUpEntry], episodes: [MediaItem]) -> MediaItem? {
        if item.type == .series {
            guard let seriesID = item.id else { return nil }
            if let next = nextUp.filter({ $0.playlist == nil }).compactMap(\.item).first(where: { $0.type == .episode && $0.seriesID == seriesID }) {
                return next
            }
            let matching = episodes.filter { $0.type == .episode && $0.seriesID == seriesID }
            return matching.first(where: { $0.userData?.isWatched != true }) ?? matching.first
        }
        guard item.type != .boxSet, item.type != .book, item.type != .season else { return nil }
        return item
    }
}

extension MediaItem {
    func gusTVPlaybackTarget(nextUp: [NextUpEntry], episodes: [MediaItem]) -> MediaItem? {
        #if os(tvOS)
            TVDetailPlaybackTarget.resolve(item: self, nextUp: nextUp, episodes: episodes)
        #else
            self
        #endif
    }
}
