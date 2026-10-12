import Foundation
import Observation
import OSLog

struct UpNextEntry: Codable, Identifiable, Equatable, Sendable {
    enum Availability: String, Codable, Sendable { case unverified, available, unavailable, requiresSelection }
    let id: UUID
    var reference: MediaReference
    var availability: Availability = .unverified
    var version: UUID = UUID()
}

struct UpNextPersistence {
    private let directory: URL
    private struct Envelope: Codable {
        var schemaVersion = 1
        var entries: [UpNextEntry]
    }

    init(directory: URL = Self.defaultDirectory()) {
        self.directory = directory
    }

    init(applicationSupportDirectory: URL) {
        self.init(directory: Self.defaultDirectory(applicationSupportDirectory: applicationSupportDirectory))
    }

    func loadEntries(scope: AccountScope) throws -> [UpNextEntry] {
        let url = fileURL(for: scope)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        if data.first(where: { ![9, 10, 13, 32].contains($0) }) == 91 {
            let legacy = try JSONDecoder().decode([MediaItem].self, from: data)
            let entries = legacy.map { UpNextEntry(id: UUID(), reference: MediaReference(item: $0, scope: scope)) }
            let backup = url.appendingPathExtension("legacy-backup")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try data.write(to: backup, options: .atomic)
            }
            try saveEntries(entries, scope: scope)
            return entries
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.schemaVersion == 1, envelope.entries.allSatisfy({ $0.reference.scope == scope }) else { throw GusError.notFound }
        return envelope.entries
    }

    func saveEntries(_ entries: [UpNextEntry], scope: AccountScope) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Envelope(entries: entries)).write(to: fileURL(for: scope), options: .atomic)
    }

    private static func defaultDirectory(applicationSupportDirectory: URL = AppStorageLocation.applicationSupportDirectory()) -> URL {
        AppStorageLocation.appDirectory(applicationSupportDirectory: applicationSupportDirectory).appendingPathComponent("UpNext", isDirectory: true)
    }

    private func fileURL(for scope: AccountScope) -> URL {
        directory.appendingPathComponent("\(scope.storageKey).json")
    }
}

@MainActor
@Observable
final class UpNextStore {
    private(set) var revision = 0
    private(set) var errorMessage: String?
    private var entriesByScope: [AccountScope: [UpNextEntry]] = [:]
    private var loadedScopes: Set<AccountScope> = []
    private var blockedScopes: Set<AccountScope> = []
    private var refreshingScopes: Set<AccountScope> = []
    private var candidatesByEntry: [UUID: [MediaItem]] = [:]
    private let persistence: UpNextPersistence
    private let logger = Logger(category: .home)

    init(persistence: UpNextPersistence = UpNextPersistence()) {
        self.persistence = persistence
    }

    func clearError() {
        errorMessage = nil
    }

    func load(serverID: String, userID: String) {
        let scope = AccountScope(serverID: serverID, userID: userID)
        guard !loadedScopes.contains(scope) else { return }
        do { entriesByScope[scope] = try persistence.loadEntries(scope: scope) }
        catch {
            blockedScopes.insert(scope)
            errorMessage = String(localized: "Your saved queue couldn't be read. It has been preserved.", comment: "Unreadable saved media queue")
        }
        loadedScopes.insert(scope)
        revision += 1
    }

    func entries(serverID: String, userID: String) -> [UpNextEntry] {
        entriesByScope[AccountScope(serverID: serverID, userID: userID)] ?? []
    }

    func items(serverID: String, userID: String) -> [MediaItem] {
        entries(serverID: serverID, userID: userID).map(\.reference.item)
    }

    func contains(_ item: MediaItem, serverID: String, userID: String) -> Bool {
        guard let id = item.id else { return false }
        return items(serverID: serverID, userID: userID).contains { $0.id == id }
    }

    func toggle(_ item: MediaItem, serverID: String, userID: String) {
        guard let id = item.id else { return }
        load(serverID: serverID, userID: userID)
        let scope = AccountScope(serverID: serverID, userID: userID)
        guard !blockedScopes.contains(scope) else { return }
        var entries = entriesByScope[scope] ?? []
        if let index = entries.firstIndex(where: { $0.reference.item.id == id }) {
            entries.remove(at: index)
        } else {
            entries.insert(UpNextEntry(id: UUID(), reference: MediaReference(item: item, scope: scope)), at: 0)
        }
        commit(entries, scope: scope)
    }

    func remove(_ entry: UpNextEntry) {
        let scope = entry.reference.scope
        commit((entriesByScope[scope] ?? []).filter { $0.id != entry.id }, scope: scope)
        candidatesByEntry.removeValue(forKey: entry.id)
    }

    func candidates(for entry: UpNextEntry) -> [MediaItem] {
        candidatesByEntry[entry.id] ?? []
    }

    func replace(_ entry: UpNextEntry, with candidate: MediaItem, session: SessionStore) async -> Bool {
        guard entry.reference.scope == session.references.scope else { return false }
        do {
            let item = try await session.references.selectedReplacement(candidate)
            try Task.checkCancellation()
            guard session.references.isActive else { return false }
            if item.id != entry.reference.item.id {
                OfflinePlaybackProgressStore.shared.offerTransfer(from: entry.reference.item.id, to: item, scope: entry.reference.scope)
            }
            let saved = update(entry, item: item, availability: .available)
            if saved {
                session.references.recordReplacement(from: entry.reference, to: item)
            }
            return saved
        } catch { errorMessage = GusError(from: error).localizedDescription; return false }
    }

    /// Refresh four at a time. Entry versions prevent late responses from restoring
    /// removed entries or overwriting a user's replacement choice.
    func refresh(session: SessionStore, force: Bool = false) async {
        let scope = session.references.scope
        load(serverID: scope.serverID, userID: scope.userID)
        guard !blockedScopes.contains(scope), refreshingScopes.insert(scope).inserted else { return }
        defer { refreshingScopes.remove(scope) }
        if force {
            session.references.beginRefresh()
        }
        let snapshots = entriesByScope[scope] ?? []
        for start in stride(from: 0, to: snapshots.count, by: 4) {
            guard !Task.isCancelled else { return }
            let chunk = Array(snapshots[start ..< min(start + 4, snapshots.count)])
            await withTaskGroup(of: (UpNextEntry, Result<MediaReferenceResolution, GusError>).self) { group in
                for entry in chunk {
                    group.addTask {
                        do {
                            let resolved = try await session.references.resolve(entry.reference, forceRefresh: force)
                            return (entry, .success(resolved))
                        } catch { return (entry, .failure(GusError(from: error))) }
                    }
                }
                for await(entry, result) in group {
                    guard !Task.isCancelled, session.references.isActive else { group.cancelAll(); return }
                    switch result {
                    case let .success(.resolved(item)):
                        if item.id != entry.reference.item.id {
                            OfflinePlaybackProgressStore.shared.offerTransfer(from: entry.reference.item.id, to: item, scope: scope)
                        }
                        update(entry, item: item, availability: .available)
                    case .success(.unavailable): update(entry, availability: .unavailable)
                    case let .success(.requiresSelection(candidates)):
                        candidatesByEntry[entry.id] = candidates
                        update(entry, availability: .requiresSelection)
                    case let .failure(error):
                        if error == .unauthorized {
                            session.onUnauthorized()
                        }
                        // Keep snapshots and prior availability on retryable failures.
                    }
                }
            }
        }
    }

    func mergedItems(remote: [MediaItem], serverID: String, userID: String) -> [MediaItem] {
        let pinned = entries(serverID: serverID, userID: userID).filter { $0.availability == .available || $0.availability == .unverified }
        let remoteByID = Dictionary(remote.compactMap { item in item.id.map { ($0, item) } }, uniquingKeysWith: { _, new in new })
        let manual = pinned.map { entry in entry.reference.item.id.flatMap { remoteByID[$0] } ?? entry.reference.item }
        let manualIDs = Set(manual.compactMap(\.id))
        return manual + remote.filter { $0.id.map { !manualIDs.contains($0) } ?? true }
    }

    @discardableResult
    private func update(_ snapshot: UpNextEntry, item: MediaItem? = nil, availability: UpNextEntry.Availability) -> Bool {
        let scope = snapshot.reference.scope
        var entries = entriesByScope[scope] ?? []
        guard let index = entries.firstIndex(where: { $0.id == snapshot.id && $0.version == snapshot.version }) else { return false }
        if let item {
            entries[index].reference.item = item
        }
        entries[index].availability = availability
        entries[index].version = UUID()
        if let itemID = item?.id {
            entries.removeAll { $0.id != snapshot.id && $0.reference.item.id == itemID }
        }
        return commit(entries, scope: scope)
    }

    @discardableResult
    private func commit(_ entries: [UpNextEntry], scope: AccountScope) -> Bool {
        guard !blockedScopes.contains(scope) else { return false }
        do {
            try persistence.saveEntries(entries, scope: scope)
            entriesByScope[scope] = entries
            revision += 1
            return true
        } catch {
            logger.error("Saved queue update failed")
            errorMessage = String(localized: "Your queue change couldn't be saved. Try again.", comment: "Queue persistence failure")
            return false
        }
    }
}
