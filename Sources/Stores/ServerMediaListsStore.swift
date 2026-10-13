import Foundation
import Observation

/// Jellyfin owns list metadata and membership. This local, account-scoped cache
/// atomically saves offline edits before sending them; iCloud owns only Gus intent.
@MainActor
@Observable
final class ServerMediaListsStore {
    static let shared = ServerMediaListsStore()
    private(set) var revision = 0
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?

    struct PendingEdit: Identifiable, Codable, Equatable {
        enum Action: String, Codable { case create, rename, delete, add, remove, move, replace }
        enum Status: String, Codable { case queued, sending, uncertain, rejected }
        let id: UUID
        var listID: UUID
        let kind: ServerMediaListKind
        var action: Action
        var status: Status = .queued
        var name: String? = nil
        var items: [MediaItem] = []
        var entryID: UUID? = nil
        var before: UUID? = nil
        var replacementID: UUID? = nil
        var message: String? = nil
        var needsReview: Bool {
            status == .uncertain || status == .rejected
        }

        var canDuplicate: Bool {
            action == .create || action == .add || (action == .replace && replacementID == nil)
        }
    }

    struct Migration: Codable {
        var nativeID: UUID
        var completed = false
    }

    struct Cache: Codable {
        var schemaVersion = 1
        var lists: [ServerMediaList] = []
        var pending: [PendingEdit] = []
        var migrations: [String: Migration] = [:]
        var aliases: [String: UUID] = [:]
        var previousEntries: [String: [UUID]] = [:]
        var removalAncestry: [String: [UUID]] = [:]
        // New aliases use listID:entryID. Unqualified interim cache keys are
        // retained as ambiguous history, never used to redirect another list.
        var entryAliases: [String: UUID] = [:]
        var temporaryEntries: Set<UUID> = []

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, lists, pending, migrations, aliases, previousEntries, removalAncestry, entryAliases, temporaryEntries
        }

        init() {}

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            lists = try values.decodeIfPresent([ServerMediaList].self, forKey: .lists) ?? []
            pending = try values.decodeIfPresent([PendingEdit].self, forKey: .pending) ?? []
            migrations = try values.decodeIfPresent([String: Migration].self, forKey: .migrations) ?? [:]
            aliases = try values.decodeIfPresent([String: UUID].self, forKey: .aliases) ?? [:]
            previousEntries = try values.decodeIfPresent([String: [UUID]].self, forKey: .previousEntries) ?? [:]
            removalAncestry = try values.decodeIfPresent([String: [UUID]].self, forKey: .removalAncestry) ?? [:]
            entryAliases = try values.decodeIfPresent([String: UUID].self, forKey: .entryAliases) ?? [:]
            temporaryEntries = try values.decodeIfPresent(Set<UUID>.self, forKey: .temporaryEntries) ?? []
        }
    }

    private let directory: URL
    private var caches: [AccountScope: Cache] = [:]
    private var blocked: Set<AccountScope> = []
    private var activeScope: AccountScope?
    private var generation = UUID()
    private var deactivated = false
    private var busy = false
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    init(directory: URL = ServerMediaListsStore.defaultDirectory()) {
        self.directory = directory
    }

    static func defaultDirectory() -> URL {
        AppStorageLocation.appDirectory(applicationSupportDirectory: AppStorageLocation.applicationSupportDirectory())
            .appendingPathComponent("ServerMediaLists", isDirectory: true)
    }

    func clearError() {
        errorMessage = nil
    }

    /// Invalidate session work while retaining each account's cache and journal.
    /// A confirmed in-flight outcome is still persisted by replay before it exits.
    func deactivate() {
        activeScope = nil
        generation = UUID()
        deactivated = true
        errorMessage = nil
        statusMessage = nil
        revision += 1
    }

    func load(scope: AccountScope) {
        deactivated = false
        if activeScope != scope {
            activeScope = scope
            generation = UUID()
            errorMessage = nil
            statusMessage = nil
            revision += 1
        }
        guard caches[scope] == nil, !blocked.contains(scope) else { return }
        do {
            let url = fileURL(scope: scope)
            var cache = Cache()
            if FileManager.default.fileExists(atPath: url.path) {
                cache = try JSONDecoder().decode(Cache.self, from: Data(contentsOf: url))
                guard cache.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
                // A crash during transmission has the same uncertainty as a lost response.
                for index in cache.pending.indices where cache.pending[index].status == .sending {
                    cache.pending[index].status = cache.pending[index].canDuplicate ? .uncertain : .queued
                }
            }
            caches[scope] = cache
        } catch {
            blocked.insert(scope)
            errorMessage = String(localized: "The cached server lists couldn't be read. The original file has been preserved.")
        }
        updateStatus(scope: scope)
    }

    func lists(kind: ServerMediaListKind, scope: AccountScope) -> [ServerMediaList] {
        projected(scope: scope).filter { $0.kind == kind }.sorted {
            $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func list(id: UUID, kind: ServerMediaListKind, scope: AccountScope) -> ServerMediaList? {
        let canonical = resolvedID(id, scope: scope)
        return projected(scope: scope).first { $0.id == canonical && $0.kind == kind }
    }

    func resolvedID(_ id: UUID, scope: AccountScope) -> UUID {
        caches[scope]?.aliases[id.uuidString] ?? id
    }

    func resolvedEntryID(_ id: UUID, inList listID: UUID, scope: AccountScope) -> UUID {
        let canonical = resolvedID(listID, scope: scope)
        var resolved = id
        var seen: Set<UUID> = []
        // Unqualified aliases from interim caches cannot be attributed to a list.
        while seen.insert(resolved).inserted, let next = caches[scope]?.entryAliases[Self.listEntryKey(listID: canonical, entryID: resolved)] {
            resolved = next
        }
        return resolved
    }

    func legacyImportID(for id: UUID, scope: AccountScope) -> UUID? {
        guard let marker = caches[scope]?.migrations["legacy-" + id.uuidString], marker.completed else { return nil }
        return marker.nativeID
    }

    func pendingEdits(scope: AccountScope) -> [PendingEdit] {
        caches[scope]?.pending ?? []
    }

    func videoPlaylists(scope: AccountScope, supplemental: VideoPlaylistsStore) -> [VideoPlaylist] {
        lists(kind: .playlist, scope: scope).compactMap { videoPlaylist(id: $0.id, scope: scope, supplemental: supplemental) }
    }

    func videoPlaylist(id: UUID, scope: AccountScope, supplemental: VideoPlaylistsStore) -> VideoPlaylist? {
        guard let list = list(id: id, kind: .playlist, scope: scope) else { return nil }
        let canonical = list.id
        supplemental.migrateServerPlaylistState(from: id, to: canonical, scope: scope)
        for (old, native) in caches[scope]?.aliases ?? [:] where native == canonical {
            if let original = UUID(uuidString: old) {
                supplemental.migrateServerPlaylistState(from: original, to: canonical, scope: scope)
            }
        }
        let state = supplemental.serverPlaylistState(id: canonical, scope: scope)
        var cursor = state.cursor
        if let entryID = cursor?.entryID {
            cursor?.entryID = resolvedEntryID(entryID, inList: canonical, scope: scope)
        }
        if let cursor, cursor != state.cursor {
            // Proven native identities must travel with the CloudKit cursor;
            // another device does not have this device's draft alias cache.
            supplemental.setCursor(id: canonical, entryID: cursor.entryID, positionTicks: cursor.positionTicks, finished: cursor.finished, scope: scope, activity: false)
        }
        // An old unqualified alias cannot establish removal history for this list.
        if list.entriesLoaded, let current = cursor?.entryID, !list.entries.contains(where: { $0.id == current }), caches[scope]?.temporaryEntries.contains(current) != true,
           caches[scope]?.entryAliases[current.uuidString] == nil
        {
            let rawIDs = caches[scope]?.lists.first(where: { $0.id == canonical })?.entries.map(\.id) ?? []
            let observed = caches[scope]?.removalAncestry[Self.listEntryKey(listID: canonical, entryID: current)]
            let oldIDs = observed ?? (rawIDs.contains(current) ? rawIDs : caches[scope]?.previousEntries[canonical.uuidString] ?? [])
            // A fresh device may receive a cursor after its occurrence vanished.
            // Only an observed removal has enough history to choose a neighbor.
            if let index = oldIDs.firstIndex(of: current) {
                let survivors = Set(list.entries.map(\.id))
                let replacement = oldIDs.dropFirst(index + 1).first(where: { survivors.contains($0) })
                    ?? oldIDs.prefix(index).last(where: { survivors.contains($0) })
                cursor = replacement.map { PlaylistCursor(entryID: $0, positionTicks: 0, finished: false) }
            }
        }
        return VideoPlaylist(
            id: list.id,
            name: list.name,
            scope: scope,
            entries: list.entries.map { VideoPlaylistEntry(id: $0.id, reference: MediaReference(item: $0.item, scope: scope)) },
            cursor: cursor,
            queued: state.queued,
            activityAt: state.activityAt
        )
    }

    func refresh(session: SessionStore) async {
        let scope = session.references.scope
        guard prepare(scope: scope) else { return }
        let token = generation
        await acquire()
        defer { release() }
        guard current(scope, token) else { return }
        for kind in ServerMediaListKind.allCases {
            do {
                let remote = try await session.mediaProvider.mediaLists(kind: kind)
                guard current(scope, token) else { return }
                guard save(scope: scope, { cache in
                    let old = cache.lists
                    var refreshed: [ServerMediaList] = []
                    for var list in remote {
                        Self.retireAliasesForCurrentMembership(in: list, cache: &cache)
                        if let previous = old.first(where: { $0.id == list.id && $0.kind == kind }) {
                            if !list.entriesLoaded {
                                list.entries = previous.entries
                                list.entriesLoaded = previous.entriesLoaded
                            } else {
                                Self.rememberRemovals(previous: previous, current: list, cache: &cache)
                            }
                        }
                        refreshed.append(list)
                    }
                    cache.lists.removeAll { $0.kind == kind }
                    cache.lists += refreshed
                }) else { return }
                // Listing is cheap; entry pages load when a list is opened or queued.
                for list in remote {
                    do { try await fetch(id: list.id, kind: kind, session: session, token: token) }
                    catch {
                        if current(scope, token) {
                            report(error, session: session)
                        }
                    }
                    guard current(scope, token) else { return }
                }
            } catch {
                guard current(scope, token) else { return }
                report(error, session: session)
            }
        }
        await replay(session: session, token: token)
    }

    func refresh(id: UUID, kind: ServerMediaListKind, session: SessionStore) async {
        let scope = session.references.scope
        guard prepare(scope: scope) else { return }
        let token = generation
        await acquire()
        defer { release() }
        guard current(scope, token) else { return }
        do { try await fetch(id: resolvedID(id, scope: scope), kind: kind, session: session, token: token) }
        catch {
            if current(scope, token) {
                report(error, session: session)
            }
        }
        await replay(session: session, token: token)
    }

    @discardableResult
    func create(name: String, kind: ServerMediaListKind, session: SessionStore, itemIDs: [String] = [], items: [MediaItem] = []) async -> UUID? {
        guard prepare(scope: session.references.scope) else { return nil }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        guard items.allSatisfy({ $0.id != nil }) else { return nil }
        let snapshots: [MediaItem]
        if itemIDs.isEmpty {
            snapshots = items
        } else {
            snapshots = itemIDs.map { itemID in items.first(where: { $0.id == itemID }) ?? MediaItem(id: itemID) }
        }
        if kind == .playlist, Self.hasRepeatedMediaIDs(snapshots.compactMap(\.id)) {
            errorMessage = String(localized: "Jellyfin playlists cannot contain the same item more than once. This playlist has not been created.")
            return nil
        }
        let id = UUID()
        let edit = PendingEdit(
            id: UUID(),
            listID: id,
            kind: kind,
            action: .create,
            name: name,
            items: snapshots
        )
        guard await enqueue(edit, session: session) else { return nil }
        // The server-assigned identity is saved with the original local edit ID.
        return caches[session.references.scope]?.migrations[edit.id.uuidString]?.nativeID ?? id
    }

    @discardableResult
    func rename(id: UUID, kind: ServerMediaListKind, name: String, session: SessionStore) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return await enqueue(PendingEdit(id: UUID(), listID: id, kind: kind, action: .rename, name: name), session: session)
    }

    @discardableResult
    func delete(id: UUID, kind: ServerMediaListKind, session: SessionStore) async -> Bool {
        await enqueue(PendingEdit(id: UUID(), listID: id, kind: kind, action: .delete), session: session)
    }

    @discardableResult
    func add(item: MediaItem, to id: UUID, kind: ServerMediaListKind, session: SessionStore) async -> Bool {
        guard let itemID = item.id, prepare(scope: session.references.scope) else { return false }
        if list(id: id, kind: kind, scope: session.references.scope)?.entries.contains(where: { $0.item.id.map(Self.mediaIdentity) == Self.mediaIdentity(itemID) }) == true {
            errorMessage = kind == .playlist ? String(localized: "This item is already in this Jellyfin playlist. Repeated items are not supported.") : String(localized: "This item is already in this collection.")
            return false
        }
        return await enqueue(PendingEdit(id: UUID(), listID: id, kind: kind, action: .add, items: [item]), session: session)
    }

    @discardableResult
    func remove(entryID: UUID, from id: UUID, kind: ServerMediaListKind, session: SessionStore) async -> Bool {
        await enqueue(PendingEdit(id: UUID(), listID: id, kind: kind, action: .remove, entryID: entryID), session: session)
    }

    @discardableResult
    func move(entryID: UUID, in id: UUID, before: UUID?, session: SessionStore) async -> Bool {
        guard entryID != before else { return false }
        return await enqueue(PendingEdit(id: UUID(), listID: id, kind: .playlist, action: .move, entryID: entryID, before: before), session: session)
    }

    @discardableResult
    func replace(entryID: UUID, in id: UUID, with item: MediaItem, session: SessionStore) async -> Bool {
        guard let itemID = item.id, prepare(scope: session.references.scope) else { return false }
        if list(id: id, kind: .playlist, scope: session.references.scope)?.entries.contains(where: { $0.item.id.map(Self.mediaIdentity) == Self.mediaIdentity(itemID) }) == true {
            errorMessage = String(localized: "This item is already in this Jellyfin playlist. Repeated items are not supported.")
            return false
        }
        return await enqueue(PendingEdit(id: UUID(), listID: id, kind: .playlist, action: .replace, items: [item], entryID: entryID), session: session)
    }

    /// Explicit recovery: discard the local intent after inspecting Jellyfin. No
    /// network request occurs here, so an unknown add/create can never repeat.
    @discardableResult
    func discardPendingEdit(id: UUID, scope: AccountScope) -> Bool {
        save(scope: scope) { cache in
            if let create = cache.pending.first(where: { $0.id == id && $0.action == .create }) {
                cache.pending.removeAll { $0.listID == create.listID }
                for key in Array(cache.migrations.keys) where cache.migrations[key]?.nativeID == create.listID && cache.migrations[key]?.completed != true {
                    cache.migrations.removeValue(forKey: key)
                }
            } else {
                cache.pending.removeAll { $0.id == id }
            }
        }
    }

    /// Call only after the user verifies the operation did not reach Jellyfin.
    func retryPendingEdit(id: UUID, session: SessionStore) async {
        let scope = session.references.scope
        guard prepare(scope: scope) else { return }
        guard save(scope: scope, { cache in
            guard let index = cache.pending.firstIndex(where: { $0.id == id }) else { return }
            cache.pending[index].status = .queued
            cache.pending[index].message = nil
        }) else { return }
        await refresh(session: session)
    }

    /// Import is explicit and preserves the source order of unique entries. A durable marker prevents a
    /// second create after a interrupted import; the original is never modified.
    func importLegacy(_ legacy: VideoPlaylist, session: SessionStore, supplemental: VideoPlaylistsStore = .shared) async -> UUID? {
        let scope = session.references.scope
        guard prepare(scope: scope) else { return nil }
        guard legacy.scope == scope, legacy.entries.allSatisfy({ $0.reference.scope == scope && $0.reference.item.providerKind == .jellyfin && $0.reference.item.id != nil }) else {
            errorMessage = String(localized: "This playlist contains entries that cannot be imported into this Jellyfin account.")
            return nil
        }
        guard !Self.hasRepeatedMediaIDs(legacy.entries.compactMap(\.reference.item.id)) else {
            errorMessage = String(localized: "This Gus playlist contains repeated items. Jellyfin playlists require unique items, so the original Gus playlist has been kept for editing.")
            return nil
        }
        let key = "legacy-" + legacy.id.uuidString
        var nativeID: UUID
        if let marker = caches[scope]?.migrations[key] {
            nativeID = marker.nativeID
            if marker.completed {
                return nativeID
            }
        } else {
            let localID = UUID(), editID = UUID()
            let edit = PendingEdit(
                id: editID,
                listID: localID,
                kind: .playlist,
                action: .create,
                name: legacy.name,
                items: legacy.entries.map(\.reference.item)
            )
            guard save(scope: scope, { cache in
                cache.migrations[key] = Migration(nativeID: localID)
                cache.pending.append(edit)
            }) else { return nil }
            await refresh(session: session)
            nativeID = caches[scope]?.migrations[key]?.nativeID ?? localID
        }
        guard caches[scope]?.pending.contains(where: { $0.listID == nativeID }) != true else { return nil }
        await refresh(id: nativeID, kind: .playlist, session: session)
        guard activeScope == scope, let list = list(id: nativeID, kind: .playlist, scope: scope), list.entriesLoaded,
              list.entries.map(\.item.id) == legacy.entries.map(\.reference.item.id),
              supplemental.registerServerPlaylist(id: nativeID, scope: scope) else { return nil }
        if let cursor = legacy.cursor {
            let index = legacy.entries.firstIndex { $0.id == cursor.entryID }
            let imported = PlaylistCursor(entryID: index.map { list.entries[$0].id }, positionTicks: cursor.positionTicks, finished: cursor.finished)
            guard supplemental.setServerPlaylistState(id: nativeID, cursor: imported, queued: legacy.queued, activityAt: legacy.activityAt, scope: scope) else { return nil }
        }
        if legacy.cursor == nil {
            guard supplemental.setServerPlaylistState(id: nativeID, cursor: nil, queued: legacy.queued, activityAt: legacy.activityAt, scope: scope) else { return nil }
        }
        guard save(scope: scope, { $0.migrations[key]?.completed = true }) else { return nil }
        return nativeID
    }

    private func enqueue(_ edit: PendingEdit, session: SessionStore) async -> Bool {
        let scope = session.references.scope
        guard prepare(scope: scope) else { return false }
        var edit = edit
        edit.listID = resolvedID(edit.listID, scope: scope)
        if let entryID = edit.entryID {
            edit.entryID = resolvedEntryID(entryID, inList: edit.listID, scope: scope)
        }
        if let before = edit.before {
            edit.before = resolvedEntryID(before, inList: edit.listID, scope: scope)
        }
        if edit.action != .create {
            guard let list = list(id: edit.listID, kind: edit.kind, scope: scope), list.canEdit else {
                errorMessage = String(localized: "You do not have permission to edit this server list.")
                return false
            }
            if [.remove, .move, .replace].contains(edit.action), !list.entries.contains(where: { $0.id == edit.entryID }) {
                return false
            }
            if let before = edit.before, !list.entries.contains(where: { $0.id == before }) {
                return false
            }
        }
        guard save(scope: scope, { cache in
            cache.pending.append(edit)
            if edit.action == .replace {
                cache.temporaryEntries.insert(edit.id)
            }
        }) else { return false }
        let token = generation
        await acquire()
        defer { release() }
        await replay(session: session, token: token)
        return true // Durable local intent may still await connection or review.
    }

    private func replay(session: SessionStore, token: UUID) async {
        let scope = session.references.scope
        guard current(scope, token) else { return }
        let ids = caches[scope]?.pending.map(\.id) ?? []
        var paused: Set<UUID> = []
        for editID in ids {
            guard current(scope, token), var edit = caches[scope]?.pending.first(where: { $0.id == editID }) else { return }
            if paused.contains(edit.listID) {
                continue
            }
            guard edit.status == .queued else { paused.insert(edit.listID); continue }
            if edit.action != .create {
                edit.listID = resolvedID(edit.listID, scope: scope)
            }
            // Probe before any transmission. Failure here is definitely unsent,
            // including a create while offline, and remains safe to replay.
            do {
                if edit.action == .create {
                    _ = try await session.mediaProvider.mediaLists(kind: edit.kind)
                } else {
                    try await fetch(id: edit.listID, kind: edit.kind, session: session, token: token)
                    guard let fresh = caches[scope]?.lists.first(where: { $0.id == edit.listID && $0.kind == edit.kind }), fresh.canEdit else {
                        throw GusError.server(String(localized: "You do not have permission to edit this server list."))
                    }
                }
            } catch {
                guard current(scope, token) else { return }
                let unresolvedRemoval = edit.action == .remove && edit.entryID.map {
                    let resolved = resolvedEntryID($0, inList: edit.listID, scope: scope)
                    return caches[scope]?.temporaryEntries.contains(resolved) == true || caches[scope]?.entryAliases[resolved.uuidString] != nil
                } == true
                if GusError(from: error) == .notFound, edit.action == .delete || (edit.action == .remove && !unresolvedRemoval) {
                    finish(edit: edit, scope: scope)
                } else {
                    let failure = GusError(from: error)
                    if failure == .unauthorized || failure == .notFound || failure == .server(String(localized: "You do not have permission to edit this server list.")) {
                        edit.status = .rejected
                        edit.message = failure.localizedDescription
                        _ = update(edit, scope: scope)
                    }
                    report(error, session: session)
                    paused.insert(edit.listID)
                }
                continue
            }
            guard current(scope, token) else { return }
            // Earlier edits and this preflight fetch may have published native
            // occurrence IDs. Resolve both endpoints immediately before applying
            // the dependent intent, then persist that normalized operation.
            if let entryID = edit.entryID {
                edit.entryID = resolvedEntryID(entryID, inList: edit.listID, scope: scope)
            }
            if let before = edit.before {
                edit.before = resolvedEntryID(before, inList: edit.listID, scope: scope)
            }
            let referencedIDs = [edit.entryID, edit.before].compactMap { $0 }
            let nativeIDs = Set(caches[scope]?.lists.first(where: { $0.id == edit.listID && $0.kind == edit.kind })?.entries.map(\.id) ?? [])
            if referencedIDs.contains(where: {
                !nativeIDs.contains($0) && (caches[scope]?.temporaryEntries.contains($0) == true || caches[scope]?.entryAliases[$0.uuidString] != nil)
            }) {
                edit.status = .rejected
                edit.message = String(localized: "This edit refers to a saved occurrence that could not be identified on the server. Review the playlist and select the intended entry.")
                _ = update(edit, scope: scope)
                errorMessage = edit.message
                paused.insert(edit.listID)
                continue
            }
            guard update(edit, scope: scope) else { return }
            if edit.action == .remove, let list = caches[scope]?.lists.first(where: { $0.id == edit.listID }), !list.entries.contains(where: { $0.id == edit.entryID }) {
                finish(edit: edit, scope: scope)
                continue
            }
            if edit.action == .replace, let replacement = edit.replacementID,
               let fresh = caches[scope]?.lists.first(where: { $0.id == edit.listID }),
               !fresh.entries.contains(where: { $0.id == edit.entryID }), fresh.entries.contains(where: { $0.id == replacement })
            {
                finish(edit: edit, scope: scope)
                continue
            }
            edit.status = .sending
            guard update(edit, scope: scope) else { return }
            do {
                try await transmit(&edit, session: session, token: token)
                // Persist the outcome in its original account even if the user
                // switched during the request; never apply it to the new account.
                finish(edit: edit, scope: scope)
                guard current(scope, token) else { return }
                if edit.action != .delete {
                    do { try await fetch(id: edit.listID, kind: edit.kind, session: session, token: token) }
                    catch {
                        if current(scope, token) {
                            report(error, session: session)
                        }
                    }
                }
            } catch {
                edit.status = edit.canDuplicate ? .uncertain : .queued
                let failure = GusError(from: error)
                if failure == .unauthorized || failure == .notFound || failure == .server(String(localized: "You do not have permission to edit this server list.")) {
                    edit.status = .rejected
                }
                edit.message = failure.localizedDescription
                _ = update(edit, scope: scope)
                if current(scope, token) {
                    report(error, session: session)
                }
                paused.insert(edit.listID)
            }
        }
        if current(scope, token) {
            updateStatus(scope: scope)
        }
    }

    private func transmit(_ edit: inout PendingEdit, session: SessionStore, token: UUID) async throws {
        let provider = session.mediaProvider, scope = session.references.scope
        switch edit.action {
        case .create:
            let originalID = edit.listID
            let nativeID = try await provider.createMediaList(name: edit.name ?? "", kind: edit.kind, itemIDs: edit.items.compactMap(\.id))
            // Save server identity before a follow-up read can fail.
            edit.listID = nativeID
            guard save(scope: scope, { cache in
                cache.migrations[edit.id.uuidString] = Migration(nativeID: nativeID, completed: true)
                cache.aliases[originalID.uuidString] = nativeID
                for key in Array(cache.migrations.keys) where cache.migrations[key]?.nativeID == originalID {
                    cache.migrations[key]?.nativeID = nativeID
                }
                for index in cache.pending.indices where cache.pending[index].listID == originalID {
                    cache.pending[index].listID = nativeID
                }
                let entries = edit.items.enumerated().map { index, item in
                    ServerMediaListEntry(id: Self.occurrenceID(editID: edit.id, index: index), item: item)
                }
                cache.temporaryEntries.formUnion(entries.map(\.id))
                cache.lists.append(ServerMediaList(
                    id: nativeID,
                    name: edit.name ?? "",
                    kind: edit.kind,
                    entries: entries,
                    canEdit: true,
                    entriesLoaded: false
                ))
            }) else { throw CocoaError(.fileWriteUnknown) }
        case .rename:
            try await provider.renameMediaList(id: edit.listID, kind: edit.kind, name: edit.name ?? "")
        case .delete:
            try await provider.deleteMediaList(id: edit.listID, kind: edit.kind)
        case .add:
            try await provider.addToMediaList(id: edit.listID, kind: edit.kind, itemIDs: edit.items.compactMap(\.id))
        case .remove:
            if let entryID = edit.entryID {
                try await provider.removeFromMediaList(id: edit.listID, kind: edit.kind, entryIDs: [entryID])
            }
        case .move:
            guard let entryID = edit.entryID, let list = caches[scope]?.lists.first(where: { $0.id == edit.listID }),
                  list.entries.contains(where: { $0.id == entryID }) else { throw GusError.notFound }
            let rest = list.entries.filter { $0.id != entryID }
            let position: Int
            if let before = edit.before {
                guard let index = rest.firstIndex(where: { $0.id == before }) else { throw GusError.notFound }
                position = index
            } else {
                position = rest.count
            }
            try await provider.moveMediaListEntry(id: edit.listID, entryID: entryID, to: position)
        case .replace:
            guard let old = edit.entryID, let list = caches[scope]?.lists.first(where: { $0.id == edit.listID }),
                  let position = list.entries.firstIndex(where: { $0.id == old }) else { throw GusError.notFound }
            if edit.replacementID == nil {
                try await provider.addToMediaList(id: edit.listID, kind: .playlist, itemIDs: edit.items.compactMap(\.id))
                let fresh = try await provider.mediaList(id: edit.listID, kind: .playlist)
                let oldIDs = Set(list.entries.map(\.id))
                let candidates = fresh.entries.filter { !oldIDs.contains($0.id) && $0.item.id == edit.items.first?.id }
                guard candidates.count == 1 else { throw GusError.server(String(localized: "The replacement was added, but its server entry could not be identified. Refresh and review this list.")) }
                edit.replacementID = candidates[0].id
                guard update(edit, scope: scope) else { throw CocoaError(.fileWriteUnknown) }
            }
            guard current(scope, token), let replacement = edit.replacementID else { throw CancellationError() }
            try await provider.moveMediaListEntry(id: edit.listID, entryID: replacement, to: position)
            guard current(scope, token) else { throw CancellationError() }
            try await provider.removeFromMediaList(id: edit.listID, kind: .playlist, entryIDs: [old])
        }
    }

    private func fetch(id: UUID, kind: ServerMediaListKind, session: SessionStore, token: UUID) async throws {
        let remote = try await session.mediaProvider.mediaList(id: id, kind: kind)
        let scope = session.references.scope
        guard current(scope, token) else { return }
        _ = save(scope: scope) { cache in
            Self.retireAliasesForCurrentMembership(in: remote, cache: &cache)
            cache.temporaryEntries.subtract(remote.entries.map(\.id))
            if let previous = cache.lists.first(where: { $0.id == id && $0.kind == kind }), previous.entries.map(\.id) != remote.entries.map(\.id) {
                Self.rememberRemovals(previous: previous, current: remote, cache: &cache)
                cache.previousEntries[id.uuidString] = previous.entries.map(\.id)
                let knownIDs = Set(previous.entries.filter { !cache.temporaryEntries.contains($0.id) }.map(\.id))
                let temporary = previous.entries.filter { cache.temporaryEntries.contains($0.id) }
                let introduced = remote.entries.filter { !knownIDs.contains($0.id) }
                for itemID in Set(temporary.compactMap(\.item.id)) {
                    let local = temporary.filter { $0.item.id == itemID }
                    let native = introduced.filter { $0.item.id == itemID }
                    // An unrelated concurrent add/reorder cannot invalidate an
                    // occurrence match. Another add of the same media makes the
                    // outcome ambiguous, so retain its provisional ID for review.
                    guard local.count == native.count else { continue }
                    for (old, entry) in zip(local, native) {
                        cache.entryAliases[Self.listEntryKey(listID: id, entryID: old.id)] = entry.id
                        cache.temporaryEntries.remove(old.id)
                    }
                }
            }
            cache.lists.removeAll { $0.id == id && $0.kind == kind }
            cache.lists.append(remote)
        }
    }

    private func projected(scope: AccountScope) -> [ServerMediaList] {
        guard let cache = caches[scope] else { return [] }
        var lists = cache.lists
        for pending in cache.pending {
            var edit = pending
            edit.listID = resolvedID(edit.listID, scope: scope)
            if let entryID = edit.entryID {
                edit.entryID = resolvedEntryID(entryID, inList: edit.listID, scope: scope)
            }
            if let before = edit.before {
                edit.before = resolvedEntryID(before, inList: edit.listID, scope: scope)
            }
            Self.apply(edit, to: &lists)
        }
        return lists
    }

    private static func apply(_ edit: PendingEdit, to lists: inout [ServerMediaList]) {
        if edit.action == .create {
            if !lists.contains(where: { $0.id == edit.listID && $0.kind == edit.kind }) {
                lists.append(ServerMediaList(
                    id: edit.listID,
                    name: edit.name ?? "",
                    kind: edit.kind,
                    entries: edit.items.enumerated().map { index, item in
                        ServerMediaListEntry(id: occurrenceID(editID: edit.id, index: index), item: item)
                    },
                    canEdit: true,
                    entriesLoaded: true
                ))
            }
            return
        }
        guard let index = lists.firstIndex(where: { $0.id == edit.listID && $0.kind == edit.kind }) else { return }
        switch edit.action {
        case .rename: lists[index].name = edit.name ?? lists[index].name
        case .delete: lists.remove(at: index)
        case .add:
            for (offset, item) in edit.items.enumerated() {
                if edit.kind == .collection, lists[index].entries.contains(where: { $0.item.id == item.id }) {
                    continue
                }
                let id = edit.kind == .collection ? item.id.flatMap(ServerMediaListID.uuid) ?? occurrenceID(editID: edit.id, index: offset) : occurrenceID(editID: edit.id, index: offset)
                lists[index].entries.append(ServerMediaListEntry(id: id, item: item))
            }
        case .remove: lists[index].entries.removeAll { $0.id == edit.entryID }
        case .move:
            guard let entry = lists[index].entries.first(where: { $0.id == edit.entryID }) else { return }
            var entries = lists[index].entries.filter { $0.id != edit.entryID }
            if let before = edit.before {
                guard let destination = entries.firstIndex(where: { $0.id == before }) else { return }
                entries.insert(entry, at: destination)
            } else {
                entries.append(entry)
            }
            lists[index].entries = entries
        case .replace:
            if let replacement = edit.replacementID {
                lists[index].entries.removeAll { $0.id == replacement }
            }
            if let position = lists[index].entries.firstIndex(where: { $0.id == edit.entryID }), let item = edit.items.first {
                lists[index].entries[position] = ServerMediaListEntry(id: edit.replacementID ?? edit.id, item: item)
            }
        case .create: break
        }
    }

    private static func mediaIdentity(_ id: String) -> String {
        ServerMediaListID.uuid(id)?.uuidString ?? id
    }

    private static func hasRepeatedMediaIDs(_ ids: [String]) -> Bool {
        Set(ids.map(mediaIdentity)).count != ids.count
    }

    private static func listEntryKey(listID: UUID, entryID: UUID) -> String {
        listID.uuidString + ":" + entryID.uuidString
    }

    /// Jellyfin reuses a media GUID when an item is added again. Its confirmed
    /// membership supersedes an alias from an earlier replacement of that item.
    private static func retireAliasesForCurrentMembership(in list: ServerMediaList, cache: inout Cache) {
        guard list.entriesLoaded else { return }
        for entry in list.entries {
            cache.entryAliases.removeValue(forKey: listEntryKey(listID: list.id, entryID: entry.id))
        }
    }

    /// Retain the order at the first observed deletion. Later reordering/adds
    /// cannot turn an acknowledged removal into an unknown cursor or change its
    /// intended successor. Provisional identities are never deletion evidence.
    private static func rememberRemovals(previous: ServerMediaList, current: ServerMediaList, cache: inout Cache) {
        let survivors = Set(current.entries.map(\.id))
        let order = previous.entries.map(\.id)
        for entryID in order where !survivors.contains(entryID) && !cache.temporaryEntries.contains(entryID) {
            let key = listEntryKey(listID: previous.id, entryID: entryID)
            if cache.removalAncestry[key] == nil {
                cache.removalAncestry[key] = order
            }
        }
    }

    private static func occurrenceID(editID: UUID, index: Int) -> UUID {
        ServerMediaListID.uuid(String(VideoPlaylistsStore.digest(editID.uuidString + ":" + String(index)).prefix(32)))!
    }

    private func finish(edit: PendingEdit, scope: AccountScope) {
        _ = save(scope: scope) { cache in
            if edit.action == .remove, let previous = cache.lists.first(where: { $0.id == edit.listID && $0.kind == edit.kind }) {
                var removed = previous
                removed.entries.removeAll { $0.id == edit.entryID }
                Self.rememberRemovals(previous: previous, current: removed, cache: &cache)
            }
            if edit.action != .create {
                Self.apply(edit, to: &cache.lists)
                if edit.action == .add {
                    for index in edit.items.indices {
                        cache.temporaryEntries.insert(Self.occurrenceID(editID: edit.id, index: index))
                    }
                }
            }
            if edit.action == .replace, let old = edit.entryID, let replacement = edit.replacementID {
                cache.entryAliases[Self.listEntryKey(listID: edit.listID, entryID: old)] = replacement
            }
            cache.pending.removeAll { $0.id == edit.id }
        }
    }

    @discardableResult
    private func update(_ edit: PendingEdit, scope: AccountScope) -> Bool {
        save(scope: scope) { cache in
            if let index = cache.pending.firstIndex(where: { $0.id == edit.id }) {
                cache.pending[index] = edit
                if edit.action == .replace, let replacement = edit.replacementID {
                    cache.entryAliases[Self.listEntryKey(listID: edit.listID, entryID: edit.id)] = replacement
                    cache.temporaryEntries.remove(edit.id)
                }
            }
        }
    }

    @discardableResult
    private func save(scope: AccountScope, _ change: (inout Cache) -> Void) -> Bool {
        guard !blocked.contains(scope), var cache = caches[scope] else { return false }
        change(&cache)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: fileURL(scope: scope), options: .atomic)
            caches[scope] = cache
            if activeScope == scope {
                revision += 1; updateStatus(scope: scope)
            }
            return true
        } catch {
            if activeScope == scope {
                errorMessage = String(localized: "The server list changes couldn't be saved on this device.")
            }
            return false
        }
    }

    private func updateStatus(scope: AccountScope) {
        guard activeScope == scope else { return }
        let pending = caches[scope]?.pending ?? []
        if pending.contains(where: \.needsReview) {
            statusMessage = String(localized: "A server edit needs review. Refresh and inspect Jellyfin before retrying to avoid duplicates.")
        } else if !pending.isEmpty {
            statusMessage = String(localized: "Changes saved on this device · waiting for the server")
        } else {
            statusMessage = nil
        }
    }

    private func report(_ error: Error, session: SessionStore) {
        let failure = GusError(from: error)
        errorMessage = failure.localizedDescription
        failure.handleIfUnauthorized(session: session)
    }

    private func fileURL(scope: AccountScope) -> URL {
        directory.appendingPathComponent(VideoPlaylistsStore.digest(scope.serverID + "\u{0}" + scope.userID) + ".json")
    }

    private func prepare(scope: AccountScope) -> Bool {
        guard !deactivated, activeScope == nil || activeScope == scope else { return false }
        load(scope: scope)
        return !blocked.contains(scope)
    }

    private func current(_ scope: AccountScope, _ token: UUID) -> Bool {
        activeScope == scope && generation == token
    }

    private func acquire() async {
        if !busy {
            busy = true; return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
