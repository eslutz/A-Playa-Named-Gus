import CryptoKit
import Foundation
import SQLite3

/// A replaceable full-text snapshot. Each scan writes its own staging database so interrupted
/// scans and concurrent readers never expose a partially rebuilt catalog.
actor GusLibraryCatalog {
    nonisolated let directory: URL
    nonisolated var snapshot: URL {
        directory.appending(path: "catalog.sqlite")
    }

    init(directory: URL) {
        self.directory = directory
    }

    nonisolated static func directory(for scope: AccountScope) -> URL {
        // Length-prefix the server so punctuation or repeated separators cannot alias accounts.
        let identity = "\(scope.serverID.utf8.count):\(scope.serverID)\(scope.userID)"
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return URL.cachesDirectory.appending(path: "GusLibraryCatalog.noindex/v1/\(digest)", directoryHint: .isDirectory)
    }

    func isFresh(restriction: String) -> Bool {
        guard let date = try? snapshot.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              Date().timeIntervalSince(date) < 86400 else { return false }
        return (try? withDB(snapshot) { db in
            try statement("SELECT restriction FROM metadata", db) { query in
                guard sqlite3_step(query) == SQLITE_ROW else { return false }
                return String(cString: sqlite3_column_text(query, 0)) == restriction
            }
        }) == true
    }

    func prepare(_ file: URL, restriction: String) throws {
        try Task.checkCancellation()
        try withDB(file, flags: SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE) { db in
            try execute("CREATE VIRTUAL TABLE records USING fts5(title, credits, description, payload UNINDEXED); CREATE TABLE metadata(restriction TEXT NOT NULL)", db)
            try statement("INSERT INTO metadata VALUES (?)", db) { stmt in
                try bind(restriction, at: 1, to: stmt)
                try done(stmt)
            }
        }
    }

    func append(_ items: [MediaItem], to file: URL) throws {
        try Task.checkCancellation()
        try withDB(file, flags: SQLITE_OPEN_READWRITE) { db in
            try execute("BEGIN TRANSACTION", db)
            try statement("INSERT INTO records VALUES (?, ?, ?, ?)", db) { stmt in
                for item in items {
                    try Task.checkCancellation()
                    sqlite3_reset(stmt)
                    // Keep only catalog metadata. Playback sources can contain access-bearing URLs.
                    let record = MediaItem(
                        album: item.album, albumArtist: item.albumArtist, artists: item.artists, genres: item.genres, id: item.id,
                        name: item.name, officialRating: item.officialRating, overview: item.overview, people: item.people,
                        productionYear: item.productionYear, runTimeTicks: item.runTimeTicks, seriesName: item.seriesName,
                        taglines: item.taglines, type: item.type, userData: item.userData
                    )
                    try bind(item.name ?? "", at: 1, to: stmt)
                    try bind((GusLibraryMatching.creators(item) + item.people.compactMap(\.role)).joined(separator: " "), at: 2, to: stmt)
                    try bind(GusLibraryMatching.description(item), at: 3, to: stmt)
                    let payload = try JSONEncoder().encode(record)
                    let result = payload.withUnsafeBytes {
                        sqlite3_bind_blob(stmt, 4, $0.baseAddress, Int32($0.count), transient)
                    }
                    guard result == SQLITE_OK else { throw CatalogError.unavailable }
                    try done(stmt)
                }
            }
            try execute("COMMIT", db)
        }
    }

    /// Keep reading until enough admitted records match, including for filter-only searches.
    func matching(terms: [String], limit: Int, accepts: @Sendable (MediaItem) -> Bool) throws -> [MediaItem] {
        let words = terms.flatMap { $0.split { !$0.isLetter && !$0.isNumber }.map(String.init) }.prefix(40)
        let expression = words.map { "\"\($0)\"*" }.joined(separator: " OR ")
        let sql = expression.isEmpty
            ? "SELECT payload FROM records ORDER BY rowid"
            : "SELECT payload FROM records WHERE records MATCH ? ORDER BY bm25(records, 4, 3, 1, 0), rowid"
        return try withDB(snapshot) { db in
            try statement(sql, db) { stmt in
                if !expression.isEmpty {
                    try bind(expression, at: 1, to: stmt)
                }
                let decoder = JSONDecoder()
                var result: [MediaItem] = []
                while result.count < limit {
                    try Task.checkCancellation()
                    let step = sqlite3_step(stmt)
                    if step == SQLITE_DONE {
                        break
                    }
                    guard step == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 0) else { throw CatalogError.unavailable }
                    let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))
                    let item = try decoder.decode(MediaItem.self, from: data)
                    if accepts(item) {
                        result.append(item)
                    }
                }
                return result
            }
        }
    }

    private enum CatalogError: LocalizedError {
        case unavailable
        var errorDescription: String? {
            String(localized: "The search catalog could not be opened or updated. Try again.")
        }
    }

    private var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private func withDB<T>(_ file: URL, flags: Int32 = SQLITE_OPEN_READONLY, _ body: (OpaquePointer) throws -> T) throws -> T {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(file.path, &handle, flags, nil)
        defer { sqlite3_close(handle) }
        guard result == SQLITE_OK, let handle else { throw CatalogError.unavailable }
        return try body(handle)
    }

    private func execute(_ sql: String, _ db: OpaquePointer) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CatalogError.unavailable }
    }

    private func statement<T>(_ sql: String, _ db: OpaquePointer, _ body: (OpaquePointer) throws -> T) throws -> T {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw CatalogError.unavailable }
        defer { sqlite3_finalize(stmt) }
        return try body(stmt)
    }

    private func bind(_ text: String, at index: Int32, to stmt: OpaquePointer) throws {
        guard sqlite3_bind_text(stmt, index, text, -1, transient) == SQLITE_OK else { throw CatalogError.unavailable }
    }

    private func done(_ stmt: OpaquePointer) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw CatalogError.unavailable }
    }
}
