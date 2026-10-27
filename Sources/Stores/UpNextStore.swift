import Foundation
import Observation
import OSLog

struct UpNextEntry: Codable, Identifiable, Equatable, Sendable {
    enum Availability: String, Codable, Sendable { case unverified, available, unavailable, requiresSelection }
    let id: UUID
    var reference: MediaReference
    var availability: Availability = .unverified
    var version: UUID = UUID()
    /// Only explicit saving updates this date; legacy intents keep an unknown date.
    var activityAt: Date? = nil
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

    func loadEntries(scope: AccountScope, identityKey: String? = nil, migrateLocalData: Bool = false) throws -> [UpNextEntry] {
        let url = fileURL(for: scope, identityKey: identityKey)
        if let identityKey, !FileManager.default.fileExists(atPath: url.path) {
            let marker = directory.appendingPathComponent("\(scope.storageKey).identity-migrated")
            // The initial local load already consumed the unscoped migration.
            // Preserve its canonical IDs and order for the account that claimed
            // it, without allowing later accounts to repeat that migration.
            if migrateLocalData, identityKey != "local", FileManager.default.fileExists(atPath: fileURL(for: scope, identityKey: "local").path) {
                let local = try loadEntries(scope: scope, identityKey: "local")
                try saveEntries(local, scope: scope, identityKey: identityKey)
                try Data(identityKey.utf8).write(to: marker, options: .atomic)
                return local
            }
            if !FileManager.default.fileExists(atPath: marker.path) {
                let legacy = try loadEntries(scope: scope)
                try saveEntries(legacy, scope: scope, identityKey: identityKey)
                try Data(identityKey.utf8).write(to: marker, options: .atomic)
                return legacy
            }
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        if data.first(where: { ![9, 10, 13, 32].contains($0) }) == 91 {
            let legacy = try JSONDecoder().decode([MediaItem].self, from: data)
            let entries = legacy.map { UpNextEntry(id: UUID(), reference: MediaReference(item: $0, scope: scope)) }
            let backup = url.appendingPathExtension("legacy-backup")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try data.write(to: backup, options: .atomic)
            }
            try saveEntries(entries, scope: scope, identityKey: identityKey)
            return entries
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.schemaVersion == 1, envelope.entries.allSatisfy({ $0.reference.scope == scope }) else { throw GusError.notFound }
        return envelope.entries
    }

    func saveEntries(_ entries: [UpNextEntry], scope: AccountScope, identityKey: String? = nil) throws {
        let url = fileURL(for: scope, identityKey: identityKey)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Envelope(entries: entries)).write(to: url, options: .atomic)
    }

    private static func defaultDirectory(applicationSupportDirectory: URL = AppStorageLocation.applicationSupportDirectory()) -> URL {
        AppStorageLocation.appDirectory(applicationSupportDirectory: applicationSupportDirectory).appendingPathComponent("UpNext", isDirectory: true)
    }

    private func fileURL(for scope: AccountScope, identityKey: String? = nil) -> URL {
        let base = identityKey.map { directory.appendingPathComponent($0, isDirectory: true) } ?? directory
        return base.appendingPathComponent("\(scope.storageKey).json")
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
    private let syncStore: VideoPlaylistsStore?
    private let progressStore: OfflinePlaybackProgressStore
    private var identityKey: String?
    private let logger = Logger(category: .home)

    init(persistence: UpNextPersistence = UpNextPersistence(), syncStore: VideoPlaylistsStore? = nil, progressStore: OfflinePlaybackProgressStore = .shared) {
        self.persistence = persistence
        self.syncStore = syncStore
        self.progressStore = progressStore
    }

    func clearError() {
        errorMessage = nil
    }

    func load(serverID: String, userID: String) {
        let scope = AccountScope(serverID: serverID, userID: userID)
        updateIdentity()
        guard !loadedScopes.contains(scope) else { return }
        do {
            let restored = try persistence.loadEntries(scope: scope, identityKey: identityKey, migrateLocalData: syncStore?.canMigrateLocalData == true)
            let entries = canonicalEntries(restored)
            entriesByScope[scope] = entries
            if entries != restored {
                try persistence.saveEntries(entries, scope: scope, identityKey: identityKey)
            }
        } catch {
            blockedScopes.insert(scope)
            errorMessage = String(localized: "Your saved queue couldn't be read. It has been preserved.", comment: "Unreadable saved media queue")
        }
        loadedScopes.insert(scope)
        revision += 1
        reconcileSyncedIntents(scope: scope)
    }

    func entries(serverID: String, userID: String) -> [UpNextEntry] {
        load(serverID: serverID, userID: userID)
        return entriesByScope[AccountScope(serverID: serverID, userID: userID)] ?? []
    }

    func items(serverID: String, userID: String) -> [MediaItem] {
        entries(serverID: serverID, userID: userID).map(\.reference.item)
    }

    func contains(_ item: MediaItem, serverID: String, userID: String) -> Bool {
        guard let id = item.id else { return false }
        return items(serverID: serverID, userID: userID).contains { $0.id == id && $0.providerKind == item.providerKind }
    }

    func toggle(_ item: MediaItem, serverID: String, userID: String) {
        guard let id = item.id else { return }
        load(serverID: serverID, userID: userID)
        let scope = AccountScope(serverID: serverID, userID: userID)
        guard !blockedScopes.contains(scope) else { return }
        var entries = entriesByScope[scope] ?? []
        if entries.contains(where: { $0.reference.item.id == id && $0.reference.item.providerKind == item.providerKind }) {
            entries.removeAll { $0.reference.item.id == id && $0.reference.item.providerKind == item.providerKind }
        } else {
            let reference = MediaReference(item: item, scope: scope)
            let existingID = syncStore?.savedIntents(scope: scope).first { $0.reference.item.id == id && $0.reference.item.providerKind == item.providerKind }?.id
            let entryID = existingID ?? (syncStore == nil ? UUID() : VideoPlaylistsStore.canonicalIntentID(reference: reference))
            entries.insert(UpNextEntry(id: entryID, reference: reference, activityAt: Date()), at: 0)
        }
        let old = entriesByScope[scope] ?? []
        if commit(entries, scope: scope) {
            publishChanges(from: old, to: entries, scope: scope)
        }
    }

    func remove(_ entry: UpNextEntry) {
        let scope = entry.reference.scope
        let old = entriesByScope[scope] ?? []
        let entries = old.filter { $0.id != entry.id && !($0.reference.item.id == entry.reference.item.id && $0.reference.item.providerKind == entry.reference.item.providerKind) }
        if commit(entries, scope: scope) {
            publishChanges(from: old, to: entries, scope: scope)
        }
        candidatesByEntry.removeValue(forKey: entry.id)
    }

    /// Removing a resume card also clears Jellyfin Continue Watching. Zero is an
    /// explicit, idempotent position reset; watched history is left unchanged.
    func removeFromNextUp(_ item: MediaItem, session: SessionStore, activity: NextUpActivityStore = .shared, progress: OfflinePlaybackProgressStore = .shared) async throws {
        guard let id = item.id, item.providerKind == session.mediaProvider.providerKind else { throw GusError.notFound }
        do {
            try await session.mediaProvider.updatePlaybackPosition(itemID: id, positionTicks: 0)
        } catch {
            // A confirmed missing item has no server resume entry to clear.
            guard GusError(from: error) == .notFound else { throw error }
        }
        progress.resetCheckpoint(itemID: id, scope: session.references.scope)
        try dismissLocally(item, scope: session.references.scope, activity: activity)
    }

    /// Shared by removal and Mark Watched, so a later Mark Unwatched cannot
    /// restore a stale saved intent. Add or a new playback clears the dismissal.
    func dismissLocally(_ item: MediaItem, scope: AccountScope, activity: NextUpActivityStore = .shared) throws {
        load(serverID: scope.serverID, userID: scope.userID)
        guard let key = NextUpBuilder.mediaID(item), activity.setDismissed(key, dismissed: true, scope: scope) else {
            throw GusError.server(activity.errorMessage ?? String(localized: "Your queue change couldn't be saved. Try again."))
        }
        let old = entriesByScope[scope] ?? []
        let entries = old.filter { $0.reference.item.id != item.id || $0.reference.item.providerKind != item.providerKind }
        guard commit(entries, scope: scope) else {
            throw GusError.server(errorMessage ?? String(localized: "Your queue change couldn't be saved. Try again."))
        }
        publishChanges(from: old, to: entries, scope: scope)
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
            let saved = update(entry, item: item, availability: .available)
            if saved {
                if item.id != entry.reference.item.id {
                    progressStore.offerTransfer(from: entry.reference.item.id, to: item, scope: entry.reference.scope)
                }
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
                        if update(entry, item: item, availability: .available), item.id != entry.reference.item.id {
                            progressStore.offerTransfer(from: entry.reference.item.id, to: item, scope: scope)
                        }
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
        let previous = entries[index]
        var reference = previous.reference
        if let item {
            reference.item = item
        }
        // Existing intent UUIDs are durable. Changing a server locator updates
        // only the reference register, so a concurrent removal still targets the
        // same membership register even after automatic or explicit recovery.
        let updated = UpNextEntry(id: previous.id, reference: reference, availability: availability, version: UUID(), activityAt: previous.activityAt)
        entries[index] = updated
        var mergedIDs: [UUID] = []
        if let itemID = item?.id {
            mergedIDs = entries.filter { $0.id != previous.id && $0.reference.item.id == itemID && $0.reference.item.providerKind == reference.item.providerKind }.map(\.id)
            entries.removeAll { mergedIDs.contains($0.id) }
        }
        if let syncStore {
            if previous.reference.item.id != reference.item.id || !mergedIDs.isEmpty {
                guard syncStore.replaceSavedIntent(id: previous.id, reference: reference, removingIDs: mergedIDs, activityAt: previous.activityAt, scope: scope) else {
                    errorMessage = syncStore.errorMessage
                    return false
                }
            } else if SavedMediaReference(previous.reference) != SavedMediaReference(reference) {
                syncStore.updateSavedIntentReference(id: previous.id, reference: reference, scope: scope)
            }
        }
        return commit(entries, scope: scope)
    }

    /// Imports field-merged saved intents, including deletion tombstones. Only
    /// missing IDs are exported on first migration; known tombstones always win.
    func reconcileSyncedIntents(scope: AccountScope) {
        updateIdentity()
        guard let syncStore else { return }
        if !loadedScopes.contains(scope) {
            load(serverID: scope.serverID, userID: scope.userID); return
        }
        guard !blockedScopes.contains(scope) else { return }
        syncStore.load(scope: scope)
        let intents = syncStore.savedIntents(scope: scope)
        let old = entriesByScope[scope] ?? []
        let remoteByID = Dictionary(intents.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for entry in old where remoteByID[entry.id] == nil {
            syncStore.setSavedIntent(id: entry.id, reference: entry.reference, queued: true, activityAt: entry.activityAt, scope: scope)
        }
        var entries: [UpNextEntry] = []
        for entry in old {
            guard let remote = remoteByID[entry.id] else { entries.append(entry); continue }
            guard remote.queued else { continue }
            var merged = entry
            if SavedMediaReference(merged.reference) != SavedMediaReference(remote.reference) {
                merged.reference = remote.reference; merged.availability = .unverified; merged.version = UUID()
            }
            merged.activityAt = remote.activityAt
            entries.append(merged)
        }
        let localIDs = Set(old.map(\.id))
        for remote in intents where remote.queued && !localIDs.contains(remote.id) {
            guard remote.reference.scope == scope else { continue }
            entries.append(UpNextEntry(id: remote.id, reference: remote.reference, activityAt: remote.activityAt))
        }
        guard entries != old else { return }
        _ = commit(entries, scope: scope)
    }

    private func canonicalEntries(_ entries: [UpNextEntry]) -> [UpNextEntry] {
        guard let syncStore else { return entries }
        if let scope = entries.first?.reference.scope {
            syncStore.load(scope: scope)
        }
        let knownIDs = Set(entries.first.map { syncStore.savedIntents(scope: $0.reference.scope).map(\.id) } ?? [])
        var seen = Set<UUID>()
        return entries.compactMap { entry in
            let id = knownIDs.contains(entry.id) ? entry.id : VideoPlaylistsStore.canonicalIntentID(reference: entry.reference)
            guard seen.insert(id).inserted else { return nil }
            return UpNextEntry(id: id, reference: entry.reference, availability: entry.availability, version: entry.version, activityAt: entry.activityAt)
        }
    }

    private func updateIdentity() {
        let current = syncStore?.identityKey
        guard current != identityKey else { return }
        identityKey = current
        loadedScopes.removeAll()
        blockedScopes.removeAll()
        entriesByScope.removeAll()
        candidatesByEntry.removeAll()
        revision += 1
    }

    private func publishChanges(from old: [UpNextEntry], to entries: [UpNextEntry], scope: AccountScope) {
        guard let syncStore else { return }
        let newIDs = Set(entries.map(\.id))
        for entry in old where !newIDs.contains(entry.id) {
            syncStore.setSavedIntent(id: entry.id, reference: entry.reference, queued: false, activityAt: entry.activityAt, scope: scope)
        }
        for entry in entries where !old.contains(where: { $0.id == entry.id && SavedMediaReference($0.reference) == SavedMediaReference(entry.reference) && $0.activityAt == entry.activityAt }) {
            syncStore.setSavedIntent(id: entry.id, reference: entry.reference, queued: true, activityAt: entry.activityAt, scope: scope)
        }
    }

    @discardableResult
    private func commit(_ entries: [UpNextEntry], scope: AccountScope) -> Bool {
        guard !blockedScopes.contains(scope) else { return false }
        do {
            try persistence.saveEntries(entries, scope: scope, identityKey: identityKey)
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
