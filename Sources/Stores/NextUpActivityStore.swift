import Foundation
import Observation

struct NextUpActivityPersistence {
    let directory: URL
    init(directory: URL = AppStorageLocation.appDirectory().appendingPathComponent("NextUpActivity", isDirectory: true)) {
        self.directory = directory
    }

    struct Snapshot: Codable, Equatable {
        var activity: [String: Date] = [:]
        var firstSeenIDs: [String] = []
    }

    func load(scope: AccountScope, identityKey: String) throws -> Snapshot {
        let url = fileURL(scope: scope, identityKey: identityKey)
        guard FileManager.default.fileExists(atPath: url.path) else { return Snapshot() }
        return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
    }

    func save(_ snapshot: Snapshot, scope: AccountScope, identityKey: String) throws {
        let url = fileURL(scope: scope, identityKey: identityKey)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }

    private func fileURL(scope: AccountScope, identityKey: String) -> URL {
        directory.appendingPathComponent(identityKey, isDirectory: true).appendingPathComponent("\(scope.storageKey).json")
    }
}

/// Playback events belong here, independently of server metadata snapshots.
/// Do not call recordPlayback from periodic progress reports or metadata refresh.
@MainActor
@Observable
final class NextUpActivityStore {
    static let shared = NextUpActivityStore(syncStore: .shared)
    private(set) var revision = 0
    private(set) var errorMessage: String?
    private var snapshots: [AccountScope: NextUpActivityPersistence.Snapshot] = [:]
    private var blockedScopes = Set<AccountScope>()
    private var identityKey = "local"
    private let persistence: NextUpActivityPersistence
    private let syncStore: VideoPlaylistsStore?

    init(persistence: NextUpActivityPersistence = NextUpActivityPersistence(), syncStore: VideoPlaylistsStore? = nil) {
        self.persistence = persistence
        self.syncStore = syncStore
    }

    func clearError() {
        errorMessage = nil
    }

    func snapshot(scope: AccountScope) -> [String: Date] {
        load(scope: scope)
        return snapshots[scope]?.activity ?? [:]
    }

    func firstSeenIDs(scope: AccountScope) -> [String] {
        load(scope: scope)
        return snapshots[scope]?.firstSeenIDs ?? []
    }

    func recordPlayback(item: MediaItem, scope: AccountScope, at date: Date = Date()) {
        guard let id = NextUpBuilder.mediaID(item) else { return }
        load(scope: scope)
        guard !blockedScopes.contains(scope) else { return }
        var current = snapshots[scope] ?? .init()
        current.activity[id] = max(current.activity[id] ?? .distantPast, date)
        let series = item.type == .episode ? item.seriesID.map { MediaItem(providerKind: item.providerKind, id: $0, type: .series) } : nil
        if let series, let seriesKey = NextUpBuilder.mediaID(series) {
            current.activity[seriesKey] = max(current.activity[seriesKey] ?? .distantPast, date)
        }
        if commit(current, scope: scope) {
            syncStore?.recordActivity(item: item, scope: scope, at: date)
            if let series {
                syncStore?.recordActivity(item: series, scope: scope, at: date)
            }
        }
    }

    /// Registers discovery order once. Refreshing content can add new IDs but
    /// cannot change the rank of an already encountered, undated card.
    func remember(_ ids: [String], scope: AccountScope) {
        load(scope: scope)
        var current = snapshots[scope] ?? .init()
        var seen = Set(current.firstSeenIDs)
        for id in ids where seen.insert(id).inserted {
            current.firstSeenIDs.append(id)
        }
        guard current != snapshots[scope] else { return }
        _ = commit(current, scope: scope)
    }

    func reconcile(scope: AccountScope) {
        load(scope: scope)
        guard let syncStore else { return }
        syncStore.load(scope: scope)
        let normalized = Dictionary(syncStore.activitySnapshot(scope: scope).map { ("media:" + $0.key, $0.value) }, uniquingKeysWith: max)
        _ = applySyncedSnapshot(normalized, scope: scope)
    }

    @discardableResult
    func applySyncedSnapshot(_ activity: [String: Date], scope: AccountScope) -> Bool {
        load(scope: scope)
        var current = snapshots[scope] ?? .init()
        for (id, date) in activity {
            current.activity[id] = max(current.activity[id] ?? .distantPast, date)
        }
        guard current != snapshots[scope] else { return true }
        return commit(current, scope: scope)
    }

    private func load(scope: AccountScope) {
        let currentIdentity = syncStore?.identityKey ?? "local"
        if currentIdentity != identityKey {
            identityKey = currentIdentity
            snapshots.removeAll()
            blockedScopes.removeAll()
            revision += 1
        }
        guard snapshots[scope] == nil, !blockedScopes.contains(scope) else { return }
        do { snapshots[scope] = try persistence.load(scope: scope, identityKey: identityKey) }
        catch {
            blockedScopes.insert(scope)
            errorMessage = String(localized: "Recent activity couldn't be read. It has been preserved.", comment: "Next Up activity read failure")
        }
    }

    private func commit(_ snapshot: NextUpActivityPersistence.Snapshot, scope: AccountScope) -> Bool {
        guard !blockedScopes.contains(scope) else { return false }
        do {
            try persistence.save(snapshot, scope: scope, identityKey: identityKey)
            snapshots[scope] = snapshot
            revision += 1
            return true
        } catch {
            errorMessage = String(localized: "Recent activity couldn't be saved.", comment: "Next Up activity write failure")
            return false
        }
    }
}
