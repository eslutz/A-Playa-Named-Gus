import Foundation
import Observation

/// Fetches a book's original file (epub/pdf) to local storage for the in-app reader and
/// the native share sheet.
///
/// Prefers an existing offline download; otherwise streams the original into a Caches
/// subdirectory (books are small, and Caches keeps the OS free to reclaim space).
@MainActor
struct BookFileProvider {
    private let session: SessionStore
    private let downloads: OfflineDownloadStore?
    private let cachesDirectory: URL?

    init(session: SessionStore, downloads: OfflineDownloadStore? = nil, cachesDirectory: URL? = nil) {
        self.session = session
        self.downloads = downloads
        self.cachesDirectory = cachesDirectory
    }

    private var accountScope: AccountScope {
        AccountScope(serverID: session.server.id, userID: session.user.id)
    }

    /// Returns the book's file only if it is already on device (offline download or a
    /// previously cached copy) — never touches the network. Lets the UI offer Share
    /// immediately without eagerly downloading the whole book.
    private func existingLocalFile(for item: MediaItem) -> URL? {
        if let downloaded = downloads?.localFileURL(for: item, serverID: session.server.id, userID: session.user.id),
           Self.isUsableFile(downloaded)
        {
            return downloaded
        }
        guard let itemID = item.id,
              let caches = try? cachesDirectory ?? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        else { return nil }
        let directory = Self.cacheDirectory(forItemID: itemID, scope: accountScope, cachesDirectory: caches)
        let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])
        return contents?.first { Self.isUsableFile($0) }
    }

    private nonisolated static func isUsableFile(_ url: URL, fileExtension: String? = nil) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? 0) > 0,
              let file = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? file.close() }
        switch (fileExtension ?? url.pathExtension).lowercased() {
        case "epub", "cbz":
            return (try? file.read(upToCount: 4)) == Data([0x50, 0x4B, 0x03, 0x04])
        case "pdf":
            return (try? file.read(upToCount: 1024))?.range(of: Data("%PDF-".utf8)) != nil
        default:
            return true
        }
    }

    /// Returns an account-scoped original. Both Read and Share can use the cache offline.
    func localFile(for item: MediaItem) async throws -> URL {
        guard session.isActive else { throw GusError.cancelled }
        guard item.type == .book, item.id != nil else { throw GusError.notFound }
        guard item.canDownload != false else { throw GusError.forbidden }
        if let existing = existingLocalFile(for: item) {
            return existing
        }

        let current = try await session.references.currentItem(item)
        guard current.canDownload == true else { throw GusError.forbidden }
        let original = try await session.mediaProvider.downloadBook(for: current)
        defer { try? FileManager.default.removeItem(at: original.file) }
        try Task.checkCancellation()
        guard session.isActive else { throw GusError.cancelled }
        let filename = URL(fileURLWithPath: original.filename)
        guard Self.isUsableFile(original.file, fileExtension: filename.pathExtension) else {
            throw GusError.server(String(localized: "The server returned an invalid book file."))
        }
        let destination = try Self.cacheDestination(
            for: current,
            fileExtension: filename.pathExtension,
            scope: accountScope,
            cachesDirectory: cachesDirectory,
            name: filename.deletingPathExtension().lastPathComponent
        )
        if Self.isUsableFile(destination) {
            return destination
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: original.file)
        } else {
            try FileManager.default.moveItem(at: original.file, to: destination)
        }
        return destination
    }

    /// Offline downloads use an item ID on disk. Give the system share sheet a readable
    /// book name while keeping that managed download in place.
    func fileForSharing(for item: MediaItem) async throws -> URL {
        let local = try await localFile(for: item)
        guard downloads?.localFileURL(for: item, serverID: session.server.id, userID: session.user.id) == local else { return local }
        let sourceName = item.originalBookFilename.map { URL(fileURLWithPath: $0) }
        let name = sourceName?.pathExtension.caseInsensitiveCompare(local.pathExtension) == .orderedSame ? sourceName?.deletingPathExtension().lastPathComponent : nil
        let destination = try Self.cacheDestination(for: item, fileExtension: local.pathExtension, scope: accountScope, cachesDirectory: cachesDirectory, name: name)
        let manager = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString)
        defer { try? manager.removeItem(at: staging) }
        do { try manager.linkItem(at: local, to: staging) }
        catch { try manager.copyItem(at: local, to: staging) }
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try manager.moveItem(at: staging, to: destination)
        }
        return destination
    }

    /// Caches/Books/<server-user>/<item id>/<title>.<ext> — the filename feeds the share
    /// sheet, so it carries the display title while the parent path scopes private data.
    nonisolated static func cacheDestination(
        for item: MediaItem,
        fileExtension: String,
        scope: AccountScope,
        cachesDirectory: URL? = nil,
        name: String? = nil
    ) throws -> URL {
        let caches = try cachesDirectory ?? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = cacheDirectory(forItemID: item.id, scope: scope, cachesDirectory: caches)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(sanitizedFileName(name ?? item.displayTitle))
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
@Observable
final class BookProgressStore {
    static let shared = BookProgressStore()

    private let directory: URL
    private var revision = 0
    @ObservationIgnored private var cache: [String: String]?
    @ObservationIgnored private var writeTask: Task<Void, Never>?

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
        _ = revision
        return loadAll()[Self.progressKey(forItemID: itemID, scope: scope)]
    }

    func save(locatorJSON: String, forItemID itemID: String, scope: AccountScope) {
        var all = loadAll()
        all[Self.progressKey(forItemID: itemID, scope: scope)] = locatorJSON
        cache = all
        revision += 1
        scheduleWrite()
    }

    /// An explicit completion action resets just this title's precise reader position.
    func clearLocator(forItemID itemID: String, scope: AccountScope) {
        var all = loadAll()
        guard all.removeValue(forKey: Self.progressKey(forItemID: itemID, scope: scope)) != nil else { return }
        cache = all
        revision += 1
        flush()
    }

    func deleteLocators(scope: AccountScope) {
        var all = loadAll()
        let prefix = "\(scope.storageKey)__"
        all = all.filter { key, _ in !key.hasPrefix(prefix) }
        cache = all
        revision += 1
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
