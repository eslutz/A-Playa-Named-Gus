import CloudKit
import Foundation

/// CKSyncEngine owns scheduling, push subscriptions and retry/backoff. The app
/// retains its own durable outbox, so a crash between a local edit and engine
/// state serialization cannot lose an upload.
@MainActor
final class SavedMediaSyncEngine: CKSyncEngineDelegate {
    private weak var owner: VideoPlaylistsStore?
    private let container: CKContainer
    private var engine: CKSyncEngine?
    private let zoneID = CKRecordZone.ID(zoneName: "SavedMedia-v1", ownerName: CKCurrentUserDefaultName)

    init(owner: VideoPlaylistsStore, container: CKContainer) {
        self.owner = owner
        self.container = container
    }

    func start() async {
        guard let owner, owner.owns(self) else { return }
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: owner.envelope.engineState,
            delegate: self
        )
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        enqueuePending()
        do {
            // Ensure the custom zone exists on a first launch. Conflicting saved
            // records merge with the server copy before being retried.
            try await engine.sendChanges()
            guard owner.owns(self) else { return }
            try await engine.fetchChanges()
            guard owner.owns(self) else { return }
            try await engine.sendChanges()
            guard owner.owns(self) else { return }
            owner.syncFinished()
        } catch {
            if owner.owns(self) {
                owner.syncFailed()
            }
        }
    }

    func stop() {
        let previous = engine
        engine = nil
        Task { await previous?.cancelOperations() }
    }

    func enqueuePending() {
        guard let owner, owner.owns(self), let engine else { return }
        let obsolete = engine.state.pendingRecordZoneChanges.filter { change in
            switch change {
            case let .saveRecord(id): return !owner.envelope.pending.contains(id.recordName)
            case .deleteRecord: return true
            @unknown default: return false
            }
        }
        engine.state.remove(pendingRecordZoneChanges: obsolete)
        engine.state.add(pendingRecordZoneChanges: owner.envelope.pending.sorted().map {
            .saveRecord(CKRecord.ID(recordName: $0, zoneID: zoneID))
        })
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard let owner, owner.owns(self), engine === syncEngine else { return }
        switch event {
        case let .stateUpdate(update):
            if !owner.saveSyncState({ $0.engineState = update.stateSerialization }) {
                stop()
            }
        case let .accountChange(change):
            switch change.changeType {
            case let .signIn(currentUser):
                if VideoPlaylistsStore.digest(currentUser.recordName) != owner.identityKey {
                    owner.accountChanged(self)
                }
            case .signOut, .switchAccounts:
                owner.accountChanged(self)
            @unknown default: owner.accountChanged(self)
            }
        case let .fetchedRecordZoneChanges(changes):
            let success = owner.saveSyncState { state in
                for change in changes.modifications {
                    try Self.merge(change.record, into: &state)
                }
                // Retain local intent tombstones, otherwise the queue cache
                // could interpret a deleted record as an unmigrated local item.
                try state.applyExternalDeletion(recordIDs: Set(changes.deletions.map { $0.recordID.recordName }))
            }
            if success {
                enqueuePending()
            } else {
                stop()
            }
        case let .sentRecordZoneChanges(changes):
            let success = owner.saveSyncState { state in
                for record in changes.savedRecords {
                    let id = record.recordID.recordName
                    state.systemFields[id] = Self.systemFields(record)
                    // An edit made while this upload was in flight must remain
                    // pending; acknowledge the exact payload, never just its ID.
                    if let data = record["payload"] as? Data,
                       let uploaded = try? JSONDecoder().decode(SavedMediaRecord.self, from: data),
                       state.records[id] == uploaded
                    {
                        state.pending.remove(id)
                    }
                }
                for failure in changes.failedRecordSaves {
                    if let server = failure.error.serverRecord {
                        try Self.merge(server, into: &state)
                    } else if failure.error.code == .unknownItem || failure.error.code == .zoneNotFound {
                        state.systemFields.removeValue(forKey: failure.record.recordID.recordName)
                    }
                    state.pending.insert(failure.record.recordID.recordName)
                }
            }
            guard success else { stop(); return }
            if changes.failedRecordSaves.contains(where: { $0.error.code == .zoneNotFound }) {
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            }
            enqueuePending()
            if changes.failedRecordSaves.isEmpty {
                owner.syncFinished()
            } else {
                owner.syncFailed()
            }
        case let .fetchedDatabaseChanges(changes):
            if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                // A deleted private zone is a deliberate reset, not an excuse to
                // republish this device's cached collection to the server.
                if owner.saveSyncState({ state in
                    try state.applyExternalZoneReset()
                }) {
                    enqueuePending()
                } else {
                    stop()
                }
            }
        case let .sentDatabaseChanges(changes):
            if !changes.failedZoneSaves.isEmpty {
                owner.syncFailed()
            }
        case .didSendChanges:
            owner.syncFinished()
        default: break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard let owner, owner.owns(self), engine === syncEngine else { return nil }
        var records: [CKRecord] = []
        for id in owner.envelope.pending.sorted() {
            let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
            guard context.options.scope.contains(recordID), let value = owner.envelope.records[id],
                  let payload = try? JSONEncoder().encode(value) else { continue }
            let record: CKRecord
            if let data = owner.envelope.systemFields[id], let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) {
                unarchiver.requiresSecureCoding = true
                record = CKRecord(coder: unarchiver) ?? CKRecord(recordType: "SavedMediaRecord", recordID: recordID)
                unarchiver.finishDecoding()
            } else {
                record = CKRecord(recordType: "SavedMediaRecord", recordID: recordID)
            }
            record["payload"] = payload as CKRecordValue
            records.append(record)
            if records.count == 200 {
                break
            }
        }
        return records.isEmpty ? nil : CKSyncEngine.RecordZoneChangeBatch(recordsToSave: records)
    }

    private static func merge(_ cloud: CKRecord, into state: inout VideoPlaylistsStore.Envelope) throws {
        guard cloud.recordType == "SavedMediaRecord", let payload = cloud["payload"] as? Data else { return }
        let incoming = try JSONDecoder().decode(SavedMediaRecord.self, from: payload)
        guard incoming.id == cloud.recordID.recordName else { throw CocoaError(.coderReadCorrupt) }
        if let current = state.records[incoming.id], current.scope != incoming.scope || current.kind != incoming.kind {
            throw CocoaError(.coderReadCorrupt)
        }
        let merged = state.records[incoming.id]?.merging(incoming) ?? incoming
        state.records[incoming.id] = merged
        state.systemFields[incoming.id] = systemFields(cloud)
        state.clock = max(state.clock, incoming.fields.values.map(\.revision.counter).max() ?? 0)
        if merged != incoming {
            state.pending.insert(incoming.id)
        } else {
            state.pending.remove(incoming.id)
        }
    }

    private static func systemFields(_ record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }
}
