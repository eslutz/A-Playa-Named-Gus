import Foundation
import TVServices

final class TopShelfContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        completionHandler(TVTopShelfSectionedContent(sections: [makeSection()]))
    }

    private func makeSection() -> TVTopShelfItemCollection<TVTopShelfSectionedItem> {
        let items = [
            makeItem(identifier: "home", title: String(localized: "Open A Playa Named Gus", comment: "Top Shelf action that opens the app home screen"), route: "home"),
            makeItem(identifier: "search", title: String(localized: "Search Jellyfin", comment: "Search prompt and empty-state title"), route: "search"),
            makeItem(identifier: "settings", title: String(localized: "Settings", comment: "Settings navigation label"), route: "settings"),
        ]

        let section = TVTopShelfItemCollection<TVTopShelfSectionedItem>(items: items)
        section.title = String(localized: "A Playa Named Gus", comment: "App name")
        return section
    }

    private func makeItem(identifier: String, title: String, route: String) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: identifier)
        item.title = title
        item.imageShape = .hdtv
        item.displayAction = URL(string: "gus://\(route)").map(TVTopShelfAction.init(url:))
        return item
    }
}
