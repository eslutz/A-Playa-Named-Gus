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
        /// Optional for compatibility with snapshots written before dismissals existed.
        var dismissedIDs: Set<String>? = nil
        var dismissedAt: [String: Date]? = nil
    }

    func load(scope: AccountScope, identityKey: String, migrateLocalData: Bool = false) throws -> Snapshot {
        let url = fileURL(scope: scope, identityKey: identityKey)
        guard FileManager.default.fileExists(atPath: url.path) else {
            if migrateLocalData, identityKey != "local" {
                let local = try load(scope: scope, identityKey: "local")
                try save(local, scope: scope, identityKey: identityKey)
                return local
            }
            return Snapshot()
        }
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

    func isDismissed(_ id: String, scope: AccountScope) -> Bool {
        load(scope: scope)
        return snapshots[scope]?.dismissedIDs?.contains(id) == true
    }

    @discardableResult
    func setDismissed(_ id: String, dismissed: Bool, scope: AccountScope, at date: Date = Date()) -> Bool {
        load(scope: scope)
        var current = snapshots[scope] ?? .init()
        var ids = current.dismissedIDs ?? []
        if dismissed {
            ids.insert(id)
            var dates = current.dismissedAt ?? [:]
            dates[id] = date
            current.dismissedAt = dates
        } else {
            ids.remove(id)
            current.dismissedAt?.removeValue(forKey: id)
        }
        current.dismissedIDs = ids
        return commit(current, scope: scope)
    }

    func recordPlayback(item: MediaItem, scope: AccountScope, at date: Date = Date()) {
        guard let id = NextUpBuilder.mediaID(item) else { return }
        load(scope: scope)
        guard !blockedScopes.contains(scope) else { return }
        var current = snapshots[scope] ?? .init()
        current.dismissedIDs?.remove(id)
        current.dismissedAt?.removeValue(forKey: id)
        current.activity[id] = max(current.activity[id] ?? .distantPast, date)
        let series = item.type == .episode ? item.seriesID.map { MediaItem(providerKind: item.providerKind, id: $0, type: .series) } : nil
        if let series, let seriesKey = NextUpBuilder.mediaID(series) {
            current.dismissedIDs?.remove(seriesKey)
            current.dismissedAt?.removeValue(forKey: seriesKey)
            current.activity[seriesKey] = max(current.activity[seriesKey] ?? .distantPast, date)
        }
        if commit(current, scope: scope) {
            syncStore?.recordActivity(item: item, scope: scope, at: date)
            if let series {
                syncStore?.recordActivity(item: series, scope: scope, at: date)
            }
        }
    }

    @discardableResult
    func restore(_ item: MediaItem, scope: AccountScope) -> Bool {
        guard let id = NextUpBuilder.mediaID(item) else { return false }
        load(scope: scope)
        var current = snapshots[scope] ?? .init()
        current.dismissedIDs?.remove(id)
        current.dismissedAt?.removeValue(forKey: id)
        if item.type == .episode, let seriesID = item.seriesID {
            current.dismissedIDs?.remove("media:\(item.providerKind.rawValue):\(seriesID)")
            current.dismissedAt?.removeValue(forKey: "media:\(item.providerKind.rawValue):\(seriesID)")
        }
        return commit(current, scope: scope)
    }

    func isDismissed(_ item: MediaItem, scope: AccountScope) -> Bool {
        if let id = NextUpBuilder.mediaID(item), isDismissed(id, scope: scope) {
            return true
        }
        return item.type == .episode && item.seriesID.map { isDismissed("media:\(item.providerKind.rawValue):\($0)", scope: scope) } == true
    }

    /// A new server playback after removal may originate in another Jellyfin
    /// client. Cached metadata and watched/unwatched toggles cannot restore it.
    func reconcileResume(_ items: [MediaItem], scope: AccountScope) {
        load(scope: scope)
        var current = snapshots[scope] ?? .init()
        for item in items where item.userData?.isWatched != true && (item.userData?.playbackPositionTicks ?? 0) > 0 {
            guard let playedAt = item.userData?.lastPlayedAt, let id = NextUpBuilder.mediaID(item) else { continue }
            var ids = [id]
            if item.type == .episode, let seriesID = item.seriesID {
                ids.append("media:\(item.providerKind.rawValue):\(seriesID)")
            }
            for key in ids {
                if let removedAt = current.dismissedAt?[key], playedAt > removedAt {
                    current.dismissedIDs?.remove(key)
                    current.dismissedAt?.removeValue(forKey: key)
                }
            }
        }
        if current != snapshots[scope] {
            _ = commit(current, scope: scope)
        }
    }

    /// A native completion retires saved membership as well as automatic resume.
    /// Starting this item again clears the dismissal through recordPlayback.
    func recordCompletion(item: MediaItem, scope: AccountScope) {
        guard let id = NextUpBuilder.mediaID(item), setDismissed(id, dismissed: true, scope: scope), let syncStore else { return }
        syncStore.load(scope: scope)
        for intent in syncStore.savedIntents(scope: scope) where intent.queued && intent.reference.item.id == item.id && intent.reference.item.providerKind == item.providerKind {
            syncStore.setSavedIntent(id: intent.id, reference: intent.reference, queued: false, activityAt: intent.activityAt, scope: scope)
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
            if let removedAt = current.dismissedAt?[id], date > removedAt {
                current.dismissedIDs?.remove(id)
                current.dismissedAt?.removeValue(forKey: id)
            }
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
        do { snapshots[scope] = try persistence.load(scope: scope, identityKey: identityKey, migrateLocalData: syncStore?.canMigrateLocalData == true) }
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
