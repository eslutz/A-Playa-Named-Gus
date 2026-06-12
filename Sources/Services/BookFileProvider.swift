import Foundation
import OSLog

/// Fetches a book's original file (epub/pdf) to local storage for the in-app reader and
/// the "Open in Books" share sheet.
///
/// Prefers an existing offline download; otherwise streams the original into a Caches
/// subdirectory (books are small, and Caches keeps the OS free to reclaim space).
@MainActor
struct BookFileProvider {
    private let session: SessionStore
    private let downloads: OfflineDownloadStore?
    private let logger = Logger(category: .downloads)

    init(session: SessionStore, downloads: OfflineDownloadStore? = nil) {
        self.session = session
        self.downloads = downloads
    }

    private var accountScope: AccountScope {
        AccountScope(serverID: session.server.id, userID: session.user.id)
    }

    /// Returns the book's file only if it is already on device (offline download or a
    /// previously cached copy) — never touches the network. Lets the UI offer Share
    /// immediately without eagerly downloading the whole book.
    func existingLocalFile(for item: MediaItem) -> URL? {
        if let downloaded = downloads?.localFileURL(for: item, serverID: session.server.id, userID: session.user.id) {
            return downloaded
        }
        guard let itemID = item.id,
              let caches = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        else { return nil }
        let directory = Self.cacheDirectory(forItemID: itemID, scope: accountScope, cachesDirectory: caches)
        let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return contents?.first
    }

    /// Returns a local file URL for the book, fetching it if needed.
    func localFile(for item: MediaItem) async throws -> URL {
        if let downloaded = downloads?.localFileURL(for: item, serverID: session.server.id, userID: session.user.id) {
            return downloaded
        }

        let source = try await session.mediaProvider.downloadSource(for: item)
        let destination = try Self.cacheDestination(
            for: item,
            fileExtension: source.fileExtension,
            scope: accountScope
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        let (temporaryURL, response) = try await URLSession.shared.download(from: source.url)
        if let httpResponse = response as? HTTPURLResponse, !(200 ... 299).contains(httpResponse.statusCode) {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw GusError.server(String(localized: "The server could not provide this book.", comment: "Book fetch error"))
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        logger.info("Cached book file (\(source.fileExtension, privacy: .public))")
        return destination
    }

    /// Caches/Books/<server-user>/<item id>/<title>.<ext> — the filename feeds the share
    /// sheet, so it carries the display title while the parent path scopes private data.
    nonisolated static func cacheDestination(
        for item: MediaItem,
        fileExtension: String,
        scope: AccountScope,
        cachesDirectory: URL? = nil
    ) throws -> URL {
        let caches = try cachesDirectory ?? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = cacheDirectory(forItemID: item.id, scope: scope, cachesDirectory: caches)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(sanitizedFileName(item.displayTitle))
            .appendingPathExtension(fileExtension)
    }

    nonisolated static func purgeCachedFiles(scope: AccountScope, cachesDirectory: URL? = nil) {
        guard let caches = try? cachesDirectory ?? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }
        let directory = caches
            .appendingPathComponent("Books", isDirectory: true)
            .appendingPathComponent(scope.storageKey, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    private nonisolated static func cacheDirectory(
        forItemID itemID: String?,
        scope: AccountScope,
        cachesDirectory: URL
    ) -> URL {
        cachesDirectory
            .appendingPathComponent("Books", isDirectory: true)
            .appendingPathComponent(scope.storageKey, isDirectory: true)
            .appendingPathComponent(storageComponent(itemID ?? "unknown"), isDirectory: true)
    }

    private nonisolated static func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Book" : cleaned
    }

    private nonisolated static func storageComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        .joined()
        return cleaned.isEmpty ? "unknown" : cleaned
    }
}

/// Persists the reader's exact last position per account/book as a Readium `Locator`
/// JSON in Application Support. This is the precise, same-device resume layer; a coarse
/// 0...1 fraction also syncs to Jellyfin for cross-device/Continue (see
/// `JellyfinBookProgress`), and the reader restores from it when no scoped local locator
/// exists.
///
/// Saves arrive on every page turn, so positions are cached in memory and flushed to
/// disk on a short debounce (and explicitly when the reader closes) instead of
/// rewriting the file per turn.
@MainActor
final class BookProgressStore {
    static let shared = BookProgressStore()

    private let directory: URL
    private var cache: [String: String]?
    private var writeTask: Task<Void, Never>?

    init(directory: URL = AppStorageLocation.appDirectory()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var fileURL: URL {
        directory.appendingPathComponent("book-progress.json")
    }

    private func loadAll() -> [String: String] {
        if let cache {
            return cache
        }
        let loaded: [String: String]
        if let data = try? Data(contentsOf: fileURL) {
            loaded = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        } else {
            loaded = [:]
        }
        cache = loaded
        return loaded
    }

    func locatorJSON(forItemID itemID: String, scope: AccountScope) -> String? {
        loadAll()[Self.progressKey(forItemID: itemID, scope: scope)]
    }

    func save(locatorJSON: String, forItemID itemID: String, scope: AccountScope) {
        var all = loadAll()
        all[Self.progressKey(forItemID: itemID, scope: scope)] = locatorJSON
        cache = all
        scheduleWrite()
    }

    func deleteLocators(scope: AccountScope) {
        var all = loadAll()
        let prefix = "\(scope.storageKey)__"
        all = all.filter { key, _ in !key.hasPrefix(prefix) }
        cache = all
        scheduleWrite()
    }

    /// Writes any pending positions immediately — call when the reader closes.
    func flush() {
        writeTask?.cancel()
        writeTask = nil
        persist()
    }

    private func scheduleWrite() {
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    private func persist() {
        guard let cache, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    nonisolated static func progressKey(forItemID itemID: String, scope: AccountScope) -> String {
        "\(scope.storageKey)__\(storageComponent(itemID))"
    }

    private nonisolated static func storageComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        .joined()
        return cleaned.isEmpty ? "unknown" : cleaned
    }
}
