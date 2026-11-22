import CryptoKit
import Foundation

struct BrowseSnapshot<Value: Codable>: Codable {
    let savedAt: Date
    let value: Value
}

/// Small display-only snapshots. The modification date tracks use for eviction,
/// while the immutable timestamp in the payload governs freshness.
@MainActor
final class BrowseSnapshotCache {
    static let lifetime: TimeInterval = 24 * 60 * 60
    let directory: URL
    let now: () -> Date

    init(scope: AccountScope, root: URL = URL.cachesDirectory, now: @escaping () -> Date = Date.init) {
        directory = Self.directory(scope, root: root)
        self.now = now
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func directory(_ scope: AccountScope, root: URL) -> URL {
        let account = "\(scope.serverID.utf8.count):\(scope.serverID)\(scope.userID)"
        return root.appending(path: "GusBrowse.noindex/v1/" + digest(account), directoryHint: .isDirectory)
    }

    static var restriction: String {
        ContentRatingGate.storedPolicy().revision
    }

    private func file(_ key: String) -> URL {
        let prefix = key.hasPrefix("grid:") ? "grid-" : "home-"
        return directory.appending(path: prefix + Self.digest(key) + "." + Self.restriction)
    }

    func read<Value: Codable>(_ key: String, as _: Value.Type) -> BrowseSnapshot<Value>? {
        let url = file(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let entry = try? JSONDecoder().decode(BrowseSnapshot<Value>.self, from: data),
              (0 ..< Self.lifetime).contains(now().timeIntervalSince(entry.savedAt))
        else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        if key.hasPrefix("grid:") {
            try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
        }
        return entry
    }

    func write<Value: Codable>(_ value: Value, key: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let entry = BrowseSnapshot(savedAt: now(), value: value)
            try JSONEncoder().encode(entry).write(to: file(key), options: .atomic)
            if key.hasPrefix("grid:") {
                let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
                let grids = urls.filter { $0.lastPathComponent.hasPrefix("grid-") }.sorted {
                    ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
                        ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                }
                for url in grids.dropFirst(6) {
                    try FileManager.default.removeItem(at: url)
                }
            }
        } catch {
            // The cache directory is purgeable. A successful provider read is still usable.
        }
    }

    func remove(_ key: String) {
        let base = file(key).deletingPathExtension().lastPathComponent
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.deletingPathExtension().lastPathComponent == base {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func purge() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func delete(scope: AccountScope) {
        try? FileManager.default.removeItem(at: directory(scope, root: .cachesDirectory))
    }
}

extension MediaItem {
    var browseSnapshotItem: MediaItem {
        MediaItem(
            providerKind: providerKind,
            album: album,
            albumArtist: albumArtist,
            albumID: albumID,
            albumPrimaryImageTag: albumPrimaryImageTag,
            artists: artists,
            backdropImageTags: backdropImageTags,
            canDownload: canDownload,
            collectionType: collectionType,
            communityRating: communityRating,
            container: container,
            criticRating: criticRating,
            currentProgramName: currentProgramName,
            genres: genres,
            id: id,
            imageTags: imageTags,
            indexNumber: indexNumber,
            name: name,
            officialRating: officialRating,
            parentBackdropImageTags: parentBackdropImageTags,
            parentBackdropItemID: parentBackdropItemID,
            parentID: parentID,
            parentIndexNumber: parentIndexNumber,
            primaryImageAspectRatio: primaryImageAspectRatio,
            premiereDate: premiereDate,
            productionYear: productionYear,
            runTimeTicks: runTimeTicks,
            seriesID: seriesID,
            seriesName: seriesName,
            seriesPrimaryImageTag: seriesPrimaryImageTag,
            type: type,
            userData: userData,
            video3DFormat: video3DFormat
        )
    }
}

extension GusError {
    var invalidatesBrowseSnapshot: Bool {
        self == .forbidden || self == .notFound || self == .unauthorized
    }
}
