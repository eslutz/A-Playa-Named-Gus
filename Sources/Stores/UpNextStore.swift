import Foundation
import Observation
import OSLog

struct UpNextPersistence {
    private let directory: URL
    private let logger = Logger(category: .home)

    init(directory: URL = Self.defaultDirectory()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    init(applicationSupportDirectory: URL) {
        self.init(directory: Self.defaultDirectory(applicationSupportDirectory: applicationSupportDirectory))
    }

    func load(scope: AccountScope) -> [MediaItem] {
        let url = fileURL(for: scope)
        guard let data = try? Data(contentsOf: url) else { return [] }

        do {
            return try JSONDecoder().decode([MediaItem].self, from: data)
        } catch {
            logger.error("Failed to decode Up Next items: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ items: [MediaItem], scope: AccountScope) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: fileURL(for: scope), options: .atomic)
        } catch {
            logger.error("Failed to save Up Next items: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func defaultDirectory(
        applicationSupportDirectory: URL = AppStorageLocation.applicationSupportDirectory()
    ) -> URL {
        AppStorageLocation.appDirectory(applicationSupportDirectory: applicationSupportDirectory)
            .appendingPathComponent("UpNext", isDirectory: true)
    }

    private func fileURL(for scope: AccountScope) -> URL {
        directory.appendingPathComponent("\(scope.storageKey).json")
    }
}

@MainActor
@Observable
final class UpNextStore {
    private(set) var revision = 0

    private var itemsByScope: [AccountScope: [MediaItem]] = [:]
    private var loadedScopes: Set<AccountScope> = []
    private let persistence: UpNextPersistence

    init(persistence: UpNextPersistence = UpNextPersistence()) {
        self.persistence = persistence
    }

    func load(serverID: String, userID: String) {
        let scope = AccountScope(serverID: serverID, userID: userID)
        guard !loadedScopes.contains(scope) else { return }

        itemsByScope[scope] = persistence.load(scope: scope)
        loadedScopes.insert(scope)
        revision += 1
    }

    func items(serverID: String, userID: String) -> [MediaItem] {
        itemsByScope[AccountScope(serverID: serverID, userID: userID)] ?? []
    }

    func contains(_ item: MediaItem, serverID: String, userID: String) -> Bool {
        guard let itemID = item.id else { return false }
        return items(serverID: serverID, userID: userID).contains { $0.id == itemID }
    }

    func toggle(_ item: MediaItem, serverID: String, userID: String) {
        guard let itemID = item.id else { return }

        let scope = AccountScope(serverID: serverID, userID: userID)
        var scopedItems = itemsByScope[scope] ?? []

        if let index = scopedItems.firstIndex(where: { $0.id == itemID }) {
            scopedItems.remove(at: index)
        } else {
            scopedItems.insert(item, at: 0)
        }

        itemsByScope[scope] = scopedItems
        loadedScopes.insert(scope)
        persistence.save(scopedItems, scope: scope)
        revision += 1
    }

    func mergedItems(remote: [MediaItem], serverID: String, userID: String) -> [MediaItem] {
        let manualItems = items(serverID: serverID, userID: userID)
        let manualIDs = Set(manualItems.compactMap(\.id))
        return manualItems + remote.filter { item in
            guard let itemID = item.id else { return true }
            return !manualIDs.contains(itemID)
        }
    }
}
