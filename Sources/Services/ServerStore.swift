import Foundation
import OSLog

/// Codable + `FileManager` persistence for the known-servers and known-users lists.
///
/// Replaces Swiftfin's CoreStore/Defaults stack with plain JSON files in Application
/// Support. Access tokens are *not* stored here — see `KeychainStore`.
struct ServerStore {

    private let logger = Logger(subsystem: "dev.ericslutz.gus", category: "ServerStore")
    private let directory: URL

    static let shared = ServerStore()

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory

        directory = base.appendingPathComponent("Gus", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var serversURL: URL { directory.appendingPathComponent("servers.json") }
    private var usersURL: URL { directory.appendingPathComponent("users.json") }

    // MARK: - Servers

    func loadServers() -> [ServerConnection] { load([ServerConnection].self, from: serversURL) ?? [] }
    func saveServers(_ servers: [ServerConnection]) { save(servers, to: serversURL) }

    // MARK: - Users

    func loadUsers() -> [StoredUser] { load([StoredUser].self, from: usersURL) ?? [] }
    func saveUsers(_ users: [StoredUser]) { save(users, to: usersURL) }

    // MARK: - Private

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("Failed to decode \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to write \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
