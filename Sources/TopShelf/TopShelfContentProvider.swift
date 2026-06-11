import Foundation
import TVServices

/// Content-aware Top Shelf: renders the Continue Watching / Next Up snapshot the app
/// writes into the shared App Group container (`TopShelfSnapshot`) — posters, progress
/// bars, and `gus://` play/detail actions. Falls back to static app entry points when
/// no snapshot exists (first run, signed out, or App Group unavailable).
///
/// The extension holds no credentials: snapshot image URLs are unauthenticated Jellyfin
/// image endpoints and every action is a deep link handled by the app.
final class TopShelfContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        if let snapshot = TopShelfSnapshot.load(), !snapshot.items.isEmpty {
            completionHandler(TVTopShelfSectionedContent(sections: [makeContinueSection(snapshot)]))
        } else {
            completionHandler(TVTopShelfSectionedContent(sections: [makeStaticSection()]))
        }
    }

    // MARK: - Continue Watching (snapshot-driven)

    private func makeContinueSection(_ snapshot: TopShelfSnapshot) -> TVTopShelfItemCollection<TVTopShelfSectionedItem> {
        let items = snapshot.items.map { entry -> TVTopShelfSectionedItem in
            let item = TVTopShelfSectionedItem(identifier: entry.id)
            item.title = entry.title
            item.imageShape = .hdtv
            item.setImageURL(entry.imageURL, for: [.screenScale1x, .screenScale2x])
            if let progress = entry.playbackProgress {
                item.playbackProgress = progress
            }
            item.playAction = URL(string: "gus://play/\(entry.id)").map(TVTopShelfAction.init(url:))
            item.displayAction = URL(string: "gus://item/\(entry.id)").map(TVTopShelfAction.init(url:))
            return item
        }

        let section = TVTopShelfItemCollection<TVTopShelfSectionedItem>(items: items)
        section.title = String(localized: "Continue Watching", comment: "Top Shelf section of in-progress and next-up items")
        return section
    }

    // MARK: - Static fallback

    private func makeStaticSection() -> TVTopShelfItemCollection<TVTopShelfSectionedItem> {
        let items = [
            makeStaticItem(identifier: "home", title: String(localized: "Open A Playa Named Gus", comment: "Top Shelf action that opens the app home screen"), route: "home"),
            makeStaticItem(identifier: "search", title: String(localized: "Search Library", comment: "Search prompt and empty-state title"), route: "search"),
            makeStaticItem(identifier: "settings", title: String(localized: "Settings", comment: "Settings navigation label"), route: "settings"),
        ]

        let section = TVTopShelfItemCollection<TVTopShelfSectionedItem>(items: items)
        section.title = String(localized: "A Playa Named Gus", comment: "App name")
        return section
    }

    private func makeStaticItem(identifier: String, title: String, route: String) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: identifier)
        item.title = title
        item.imageShape = .hdtv
        item.displayAction = URL(string: "gus://\(route)").map(TVTopShelfAction.init(url:))
        return item
    }
}
