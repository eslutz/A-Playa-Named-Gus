import CloudKit
import CryptoKit
import Foundation
import Observation

/// Supplemental playback intent and its upload journal share one atomic file.
/// Jellyfin owns playlist names, membership and order; iCloud replicates Gus intent.
@MainActor
@Observable
final class SavedMediaStore {
    static let shared = SavedMediaStore()
    private(set) var revision = 0
    private(set) var identityRevision = 0
    private(set) var identityKey = "local"
    /// Binds pre-sync local caches to the first verified account only, including
    /// lazy loads after relaunch. Later accounts must never claim those caches.
    private(set) var localClaimIdentityKey: String?
    var canClaimLocalData: Bool {
        localClaimIdentityKey == identityKey
    }

    private(set) var errorMessage: String?
    private(set) var syncStatus = String(localized: "Saved on this device")
    var syncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(syncEnabled, forKey: "savedMediaSyncEnabled")
            if !syncEnabled {
                stopSync()
            } else if let activeScope {
                Task { await activate(scope: activeScope) }
            }
        }
    }

    struct Envelope: Codable {
        var schemaVersion = 1
        var deviceID = UUID().uuidString
        var clock: UInt64 = 0
        var records: [String: SavedMediaRecord] = [:]
        var pending: Set<String> = []
        var engineState: CKSyncEngine.State.Serialization?
        var systemFields: [String: Data] = [:]

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, deviceID, clock, records, pending, engineState, systemFields
        }

        init() {}

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
            deviceID = try values.decode(String.self, forKey: .deviceID)
            clock = try values.decode(UInt64.self, forKey: .clock)
            records = try values.decode([String: CurrentSavedMediaRecord].self, forKey: .records).compactMapValues(\.record)
            let supported = Set(records.keys)
            pending = try values.decode(Set<String>.self, forKey: .pending).intersection(supported)
            engineState = try values.decodeIfPresent(CKSyncEngine.State.Serialization.self, forKey: .engineState)
            systemFields = try values.decode([String: Data].self, forKey: .systemFields).filter { supported.contains($0.key) }
        }

        /// CloudKit deletion is also an explicit removal of saved intent. Keep
        /// a local tombstone so a still-cached queue entry cannot migrate back
        /// into the cloud after its server record disappears.
        mutating func applyExternalDeletion(recordIDs: Set<String>) throws {
            for id in recordIDs.sorted() {
                if var record = records[id], record.kind == .intent {
                    clock = max(clock, record.fields.values.map(\.revision.counter).max() ?? 0) + 1
                    try record.set("queued", value: false, revision: SavedMediaRevision(counter: clock, device: deviceID))
                    records[id] = record
                } else {
                    records.removeValue(forKey: id)
                }
                pending.remove(id)
                systemFields.removeValue(forKey: id)
            }
        }

        mutating func applyExternalZoneReset() throws {
            try applyExternalDeletion(recordIDs: Set(records.keys))
            pending.removeAll()
            systemFields.removeAll()
        }
    }

    private(set) var envelope = Envelope()
    private let directory: URL
    private var loaded = false
    private var blocked = false
    private var activeScope: AccountScope?
    private var activation = UUID()
    private var transport: SavedMediaSyncEngine?
    @ObservationIgnored private nonisolated(unsafe) var accountObserver: NSObjectProtocol?

    init(directory: URL = SavedMediaStore.defaultDirectory(), syncEnabled: Bool = UserDefaults.standard.object(forKey: "savedMediaSyncEnabled") as? Bool ?? true) {
        self.directory = directory
        self.syncEnabled = syncEnabled
        // Keep the last account's data local while offline, but never upload it
        // until CloudKit verifies that exact identity again.
        if let data = try? Data(contentsOf: directory.appendingPathComponent("identity.json")),
           let identity = try? JSONDecoder().decode(String.self, from: data)
        {
            identityKey = identity
        }
        if let data = try? Data(contentsOf: localClaimIdentityURL()),
           let identity = try? JSONDecoder().decode(String.self, from: data)
        {
            localClaimIdentityKey = identity
        }
        accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.cloudAccountNotification() }
        }
    }

    deinit {
        if let accountObserver {
            NotificationCenter.default.removeObserver(accountObserver)
        }
    }

    static func defaultDirectory() -> URL {
        AppStorageLocation.appDirectory(applicationSupportDirectory: AppStorageLocation.applicationSupportDirectory())
            .appendingPathComponent("SavedMedia", isDirectory: true)
    }

    func clearError() {
        errorMessage = nil
    }

    func load(scope _: AccountScope) {
        guard !loaded else { return }
        do {
            let url = fileURL()
            if FileManager.default.fileExists(atPath: url.path) {
                let restored = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
                guard restored.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
                envelope = restored
            }
            loaded = true
        } catch {
            blocked = true
            loaded = true
            errorMessage = String(localized: "Your saved playlists couldn't be read. The original file has been preserved.")
        }
    }

    /// Server lists synchronize only Gus playback intent. Jellyfin remains the
    /// sole authority for names, membership and ordering.
    @discardableResult
    func registerServerPlaylist(id: UUID, scope: AccountScope) -> Bool {
        load(scope: scope)
        let key = serverPlaylistKey(id: id, scope: scope)
        if envelope.records[key]?.scope == scope {
            return true
        }
        return mutate(scope: scope) { state, stamp in
            var record = SavedMediaRecord(id: key, scope: scope, kind: .playlist)
            try record.set("serverBacked", value: true, revision: stamp)
            try record.set("queued", value: false, revision: stamp)
            Self.put(record, in: &state)
        }
    }

    func serverPlaylistState(id: UUID, scope: AccountScope) -> (cursor: PlaylistCursor?, queued: Bool, activityAt: Date?) {
        load(scope: scope)
        let key = serverPlaylistKey(id: id, scope: scope)
        guard let record = envelope.records[key], record.scope == scope else { return (nil, false, nil) }
        return (envelope.records["cursor-" + key]?.value("cursor"), record.value("queued") ?? false, record.value("activity"))
    }

    /// Atomically stores native-list playback intent without inventing activity.
    @discardableResult
    func setServerPlaylistState(id: UUID, cursor: PlaylistCursor?, queued: Bool, activityAt: Date?, scope: AccountScope) -> Bool {
        load(scope: scope)
        let key = serverPlaylistKey(id: id, scope: scope)
        return mutate(scope: scope) { state, stamp in
            var record = state.records[key] ?? SavedMediaRecord(id: key, scope: scope, kind: .playlist)
            guard record.scope == scope else { return }
            try record.set("serverBacked", value: true, revision: stamp)
            try record.set("queued", value: queued, revision: stamp)
            try record.set("activity", value: activityAt, revision: stamp)
            Self.put(record, in: &state)
            var progress = state.records["cursor-" + key] ?? SavedMediaRecord(id: "cursor-" + key, scope: scope, kind: .cursor)
            try progress.set("cursor", value: cursor, revision: stamp)
            Self.put(progress, in: &state)
        }
    }

    /// A local offline draft is assigned a Jellyfin identity after reconnecting.
    /// Copy only its Gus intent; names and entries are never written here.
    @discardableResult
    func remapServerPlaylistState(from oldID: UUID, to newID: UUID, scope: AccountScope) -> Bool {
        guard oldID != newID else { return true }
        load(scope: scope)
        let oldKey = serverPlaylistKey(id: oldID, scope: scope)
        let newKey = serverPlaylistKey(id: newID, scope: scope)
        guard let old = envelope.records[oldKey], old.scope == scope else { return true }
        if let destination = envelope.records[newKey], destination.value("migratedFrom", as: UUID.self) != nil || destination.value("queued", as: Bool.self) == true || destination.value("activity", as: Date.self) != nil || envelope.records["cursor-" + newKey] != nil {
            return true
        }
        return mutate(scope: scope) { state, stamp in
            var new = state.records[newKey] ?? SavedMediaRecord(id: newKey, scope: scope, kind: .playlist)
            try new.set("migratedFrom", value: oldID, revision: stamp)
            for key in ["serverBacked", "queued", "activity"] {
                if let field = old.fields[key] {
                    // Reconciliation expresses this intent under its native identity;
                    // a delayed registration default must not undo the copy.
                    new.fields[key] = SavedMediaField(revision: stamp, data: field.data)
                }
            }
            Self.put(new, in: &state)
            if let cursor: PlaylistCursor = state.records["cursor-" + oldKey]?.value("cursor") {
                var record = SavedMediaRecord(id: "cursor-" + newKey, scope: scope, kind: .cursor)
                try record.set("cursor", value: cursor, revision: stamp)
                Self.put(record, in: &state)
            }
        }
    }

    private func serverPlaylistKey(id: UUID, scope: AccountScope) -> String {
        "server-" + Self.digest(scope.serverID + "\u{0}" + scope.userID) + "-" + id.uuidString
    }

    func playlist(id: UUID, scope: AccountScope) -> VideoPlaylist? {
        load(scope: scope)
        guard envelope.records[serverPlaylistKey(id: id, scope: scope)]?.scope == scope else { return nil }
        let state = serverPlaylistState(id: id, scope: scope)
        return VideoPlaylist(id: id, name: "", scope: scope, entries: [], cursor: state.cursor, queued: state.queued, activityAt: state.activityAt)
    }

    func setQueued(id: UUID, queued: Bool, scope: AccountScope) {
        load(scope: scope)
        guard playlist(id: id, scope: scope) != nil else { return }
        let playlistKey = serverPlaylistKey(id: id, scope: scope)
        guard envelope.records[playlistKey]?.scope == scope else { return }
        _ = mutate(scope: scope) { state, stamp in
            guard var record = state.records[playlistKey] else { return }
            try record.set("queued", value: queued, revision: stamp)
            if queued {
                try record.set("activity", value: Date(), revision: stamp)
                let cursorKey = "cursor-" + playlistKey
                if var cursor = state.records[cursorKey], cursor.value("cursor", as: PlaylistCursor.self)?.finished == true {
                    try cursor.set("cursor", value: PlaylistCursor(entryID: nil, positionTicks: 0, finished: false), revision: stamp)
                    Self.put(cursor, in: &state)
                }
            }
            Self.put(record, in: &state)
        }
    }

    /// Verify durable storage before preparation without changing the saved cursor.
    func canSavePlaybackState() -> Bool {
        saveSyncState { _ in }
    }

    @discardableResult
    func setCursor(id: UUID, entryID: UUID?, positionTicks: Int?, finished: Bool, scope: AccountScope, activity: Bool = true) -> Bool {
        guard playlist(id: id, scope: scope) != nil else { return false }
        return mutate(scope: scope) { state, stamp in
            let playlistKey = serverPlaylistKey(id: id, scope: scope)
            let key = "cursor-" + playlistKey
            var record = state.records[key] ?? SavedMediaRecord(id: key, scope: scope, kind: .cursor)
            try record.set("cursor", value: PlaylistCursor(entryID: entryID, positionTicks: positionTicks.map { max(0, $0) }, finished: finished), revision: stamp)
            Self.put(record, in: &state)
            if var playlist = state.records[playlistKey] {
                if finished {
                    try playlist.set("queued", value: false, revision: stamp)
                }
                if activity {
                    try playlist.set("activity", value: Date(), revision: stamp)
                }
                Self.put(playlist, in: &state)
            }
        }
    }

    static func canonicalIntentID(reference: MediaReference) -> UUID {
        let key = [reference.scope.serverID, reference.scope.userID, reference.item.providerKind.rawValue, reference.item.id ?? ""].joined(separator: "\u{0}")
        let hex = Array(digest(key).prefix(32))
        let string = String(hex[0 ..< 8]) + "-" + String(hex[8 ..< 12]) + "-" + String(hex[12 ..< 16]) + "-" + String(hex[16 ..< 20]) + "-" + String(hex[20 ..< 32])
        // All characters came from SHA-256 hexadecimal output.
        return UUID(uuidString: string)!
    }

    func savedIntents(scope: AccountScope) -> [SavedMediaIntent] {
        envelope.records.values.filter { $0.kind == .intent && $0.scope == scope }.sorted { $0.id < $1.id }.compactMap { record in
            guard let id = record.value("id", as: UUID.self), let ref = record.value("reference", as: SavedMediaReference.self), ref.scope == scope else { return nil }
            return SavedMediaIntent(id: id, reference: ref.reference, queued: record.value("queued") ?? false, activityAt: record.value("activity"))
        }
    }

    func setSavedIntent(id requestedID: UUID, reference: MediaReference, queued: Bool, activityAt: Date?, scope: AccountScope) {
        guard reference.scope == scope, reference.item.id != nil else { return }
        load(scope: scope)
        let existing = envelope.records["intent-\(requestedID)"]
        let id = existing?.scope == scope && existing?.kind == .intent ? requestedID : Self.canonicalIntentID(reference: reference)
        mutate(scope: scope) { state, stamp in
            let key = "intent-\(id)"
            var record = state.records[key] ?? SavedMediaRecord(id: key, scope: scope, kind: .intent)
            try record.set("id", value: id, revision: stamp)
            try record.set("reference", value: SavedMediaReference(reference), revision: stamp)
            try record.set("queued", value: queued, revision: stamp)
            if let activityAt {
                try record.set("activity", value: max(activityAt, record.value("activity") ?? .distantPast), revision: stamp)
            }
            Self.put(record, in: &state)
        }
    }

    /// A metadata refresh does not express an add, re-add or playback event.
    func updateSavedIntentReference(id: UUID, reference: MediaReference, scope: AccountScope) {
        guard reference.scope == scope, reference.item.id != nil else { return }
        load(scope: scope)
        let key = "intent-\(id)"
        let value = SavedMediaReference(reference)
        guard let current = envelope.records[key], current.scope == scope, current.kind == .intent, current.value("reference", as: SavedMediaReference.self) != value else { return }
        mutate(scope: scope) { state, stamp in
            guard var record = state.records[key] else { return }
            try record.set("reference", value: value, revision: stamp)
            Self.put(record, in: &state)
        }
    }

    /// A repaired locator keeps its durable intent ID. Membership is untouched,
    /// so an unseen concurrent removal still wins after reference-only repair.
    /// Any duplicate intents removed by the local merge are tombstoned atomically.
    @discardableResult
    func replaceSavedIntent(id: UUID, reference: MediaReference, removingIDs: [UUID], activityAt _: Date?, scope: AccountScope) -> Bool {
        guard reference.scope == scope, reference.item.id != nil else { return false }
        load(scope: scope)
        let key = "intent-\(id)"
        guard let current = envelope.records[key], current.scope == scope, current.kind == .intent else { return false }
        return mutate(scope: scope) { state, stamp in
            var replacement = current
            let value = SavedMediaReference(reference)
            if replacement.value("reference", as: SavedMediaReference.self) != value {
                try replacement.set("reference", value: value, revision: stamp)
                Self.put(replacement, in: &state)
            }
            for duplicate in removingIDs where duplicate != id {
                let duplicateKey = "intent-\(duplicate)"
                guard var retired = state.records[duplicateKey], retired.scope == scope, retired.kind == .intent else { continue }
                try retired.set("queued", value: false, revision: stamp)
                Self.put(retired, in: &state)
            }
        }
    }

    func activitySnapshot(scope: AccountScope) -> [String: Date] {
        var result: [String: Date] = [:]
        for record in envelope.records.values where record.scope == scope && record.kind == .activity {
            if let key = record.value("key", as: String.self), let date = record.value("activity", as: Date.self) {
                result[key] = date
            }
        }
        return result
    }

    func recordActivity(item: MediaItem, scope: AccountScope, at date: Date = Date()) {
        guard let id = item.id else { return }
        let key = "\(item.providerKind.rawValue):\(id)"
        mutate(scope: scope) { state, stamp in
            let recordID = "activity-" + Self.digest(scope.serverID + "\u{0}" + scope.userID + "\u{0}" + key)
            var record = state.records[recordID] ?? SavedMediaRecord(id: recordID, scope: scope, kind: .activity)
            try record.set("key", value: key, revision: stamp)
            try record.set("activity", value: max(date, record.value("activity") ?? .distantPast), revision: stamp)
            Self.put(record, in: &state)
        }
    }

    func activate(scope: AccountScope) async {
        activeScope = scope
        load(scope: scope)
        stopSync()
        guard syncEnabled, !blocked else { return }
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--gus-disable-cloud-sync") {
                return
            }
        #endif
        // A unit-test/preview command-line host has no CloudKit entitlement.
        // CloudKit must never be initialized there (it can raise an exception).
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.bundleIdentifier == "dev.ericslutz.gus",
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        else {
            syncStatus = String(localized: "iCloud unavailable · saved on this device")
            return
        }
        let generation = UUID()
        activation = generation
        do {
            let container = CKContainer(identifier: "iCloud.dev.ericslutz.gus")
            let status = try await container.accountStatus()
            guard status == .available else {
                guard activation == generation else { return }
                if status == .noAccount, identityKey != "local", !identityKey.hasPrefix("signed-out-") {
                    isolateAccount()
                }
                syncStatus = String(localized: "iCloud unavailable · saved on this device")
                return
            }
            let userID = try await container.userRecordID()
            guard activation == generation, activeScope == scope else { return }
            try selectIdentity(Self.digest(userID.recordName), scope: scope)
            guard !blocked else { return }
            let transport = SavedMediaSyncEngine(owner: self, container: container)
            self.transport = transport
            syncStatus = String(localized: "Syncing with iCloud")
            await transport.start()
        } catch {
            guard activation == generation else { return }
            syncStatus = String(localized: "iCloud unavailable · changes waiting to sync")
        }
    }

    func deactivate() {
        activeScope = nil; stopSync()
    }

    func owns(_ engine: SavedMediaSyncEngine) -> Bool {
        transport === engine
    }

    func accountChanged(_ engine: SavedMediaSyncEngine) {
        guard syncEnabled, owns(engine) else { return }
        isolateAccount()
        if let activeScope {
            Task { await activate(scope: activeScope) }
        }
    }

    private func cloudAccountNotification() {
        guard syncEnabled else { return }
        isolateAccount()
        if let activeScope {
            Task { await activate(scope: activeScope) }
        }
    }

    private func isolateAccount() {
        stopSync()
        // Clear visible state synchronously before awaiting a new identity.
        envelope = Envelope(); loaded = false; blocked = false
        identityKey = "signed-out-" + UUID().uuidString
        identityRevision += 1; revision += 1
        try? persistIdentity()
    }

    func syncFailed() {
        syncStatus = String(localized: "Changes waiting to sync")
    }

    func syncFinished() {
        syncStatus = envelope.pending.isEmpty ? String(localized: "Synced with iCloud") : String(localized: "Changes waiting to sync")
    }

    @discardableResult
    func saveSyncState(_ change: (inout Envelope) throws -> Void) -> Bool {
        guard !blocked else { return false }
        var state = envelope
        do { try change(&state); try persist(state); envelope = state; revision += 1; return true }
        catch { errorMessage = String(localized: "Your changes couldn't be saved. Try again."); return false }
    }

    func selectIdentity(_ key: String, scope: AccountScope) throws {
        guard identityKey != key else { return }
        let local = identityKey == "local" ? envelope : nil
        identityKey = key
        envelope = Envelope(); loaded = false; blocked = false
        load(scope: scope)
        if let local, !blocked {
            var merged = envelope
            for record in local.records.values {
                merged.records[record.id] = merged.records[record.id]?.merging(record) ?? record
                merged.pending.insert(record.id)
            }
            merged.clock = max(merged.clock, local.clock)
            try persist(merged)
            envelope = merged
            if localClaimIdentityKey == nil {
                try JSONEncoder().encode(key).write(to: localClaimIdentityURL(), options: .atomic)
                localClaimIdentityKey = key
            }
        }
        try persistIdentity()
        identityRevision += 1; revision += 1
    }

    private func stopSync() {
        activation = UUID()
        let previous = transport
        transport = nil
        previous?.stop()
        syncStatus = String(localized: "Saved on this device")
    }

    @discardableResult
    private func mutate(scope: AccountScope, _ change: (inout Envelope, SavedMediaRevision) throws -> Void) -> Bool {
        load(scope: scope)
        let success = saveSyncState { state in
            state.clock += 1
            let stamp = SavedMediaRevision(counter: state.clock, device: state.deviceID)
            try change(&state, stamp)
        }
        if success {
            transport?.enqueuePending()
        }
        return success
    }

    private static func put(_ record: SavedMediaRecord, in state: inout Envelope) {
        state.records[record.id] = record
        state.pending.insert(record.id)
    }

    private func persist(_ state: Envelope) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: fileURL(), options: .atomic)
    }

    private func persistIdentity() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(identityKey).write(to: directory.appendingPathComponent("identity.json"), options: .atomic)
    }

    /// This is the current identity-ownership marker, not a format importer.
    private func localClaimIdentityURL() -> URL {
        directory.appendingPathComponent("local-migration-identity.json")
    }

    private func fileURL() -> URL {
        directory.appendingPathComponent(identityKey + ".json")
    }

    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
