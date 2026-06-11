import Foundation

/// The data contract between the tvOS app and its Top Shelf extension: a small JSON
/// snapshot of Continue Watching / Next Up, written by the app into the shared App
/// Group container whenever Home loads, and read by the extension to render posters.
///
/// The snapshot deliberately carries **no credentials**: image URLs are Jellyfin's
/// unauthenticated image endpoints and the actions are `gus://` deep links, so the
/// extension never needs Keychain access. A missing/empty snapshot (no App Group
/// container, first run, signed out) falls back to the extension's static items.
struct TopShelfSnapshot: Codable, Equatable {
    struct Item: Codable, Equatable {
        let id: String
        let title: String
        /// Wide (16:9) artwork URL from the provider's image pipeline.
        let imageURL: URL?
        /// 0...1 watched fraction for the Top Shelf progress bar.
        let playbackProgress: Double?
    }

    static let appGroupIdentifier = "group.dev.ericslutz.gus"
    private static let fileName = "topshelf-snapshot.json"

    var items: [Item]

    // MARK: - App Group persistence

    static func containerFileURL(appGroupIdentifier: String = appGroupIdentifier) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    static func load(from fileURL: URL? = containerFileURL()) -> TopShelfSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(TopShelfSnapshot.self, from: data)
    }

    func save(to fileURL: URL? = containerFileURL()) {
        guard let fileURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear(at fileURL: URL? = containerFileURL()) {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
