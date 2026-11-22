import Foundation

/// The optional data contract between the tvOS app and its Top Shelf extension: a
/// small JSON snapshot of Continue Watching / Next Up. It is only active when the app
/// and extension are signed with a shared App Group entitlement.
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
        var contentURL: URL? = nil
    }

    static let appGroupIdentifier = "group.dev.ericslutz.gus"
    private static let fileName = "topshelf-snapshot.json"

    var items: [Item]
    var serverID: String? = nil
    var userID: String? = nil
    /// Snapshots from before account consent have no publication ID.
    var publicationID: UUID? = UUID()
    var restrictionRevision: String? = nil

    func actionURL(for itemID: String, play: Bool) -> URL? {
        guard let publicationID, serverID != nil, userID != nil else { return nil }
        var parts = URLComponents()
        parts.scheme = "gus"
        parts.host = "top-shelf"
        parts.path = "/" + publicationID.uuidString + (play ? "/play" : "/item")
        parts.queryItems = [URLQueryItem(name: "item", value: itemID)]
        return parts.url
    }

    func selection(for url: URL) -> (id: String, play: Bool, serverID: String, userID: String)? {
        let path = url.pathComponents.filter { $0 != "/" }
        guard url.scheme == "gus", url.host == "top-shelf", path.count == 2,
              let publicationID, path[0] == publicationID.uuidString, ["play", "item"].contains(path[1]),
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              query.count == 1, query[0].name == "item", let id = query[0].value,
              items.contains(where: { $0.id == id }), let serverID, let userID else { return nil }
        return (id, path[1] == "play", serverID, userID)
    }

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
        guard let fileURL else { return }
        var snapshot = self
        if let prior = Self.load(from: fileURL), prior.serverID == serverID, prior.userID == userID, let token = prior.publicationID {
            snapshot.publicationID = token
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear(at fileURL: URL? = containerFileURL()) {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
