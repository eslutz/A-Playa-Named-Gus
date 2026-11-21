#if os(iOS) || os(tvOS)
    import CloudKit
    import CryptoKit
    import Foundation

    /// Recommendations are ranked Jellyfin IDs. The receiving device resolves its own
    /// metadata and permissions before displaying a pick.
    struct ForYouSnapshot: Codable, Equatable, Sendable {
        static let maximumPicks = 12
        static let lifetime: TimeInterval = 7 * 24 * 60 * 60
        private static let clockTolerance: TimeInterval = 5 * 60

        // SavedMediaSyncEngine versions that fetch all private zones intentionally
        // ignore unsupported kinds stored in the shared CloudKit record type.
        private static let recordKind = "forYouSnapshot-v1"
        private let kind = recordKind

        let itemIDs: [String]
        let createdAt: Date

        init(itemIDs: [String], createdAt: Date = .now) {
            var seen = Set<String>()
            var ranked: [String] = []
            for id in itemIDs {
                guard Self.isJellyfinID(id), seen.insert(id).inserted else { continue }
                ranked.append(id)
                if ranked.count == Self.maximumPicks {
                    break
                }
            }
            self.itemIDs = ranked
            self.createdAt = createdAt
        }

        private static func isJellyfinID(_ id: String) -> Bool {
            !id.isEmpty && id.utf8.count <= 128 && id.utf8.allSatisfy { byte in
                switch byte {
                case 45, 48 ... 57, 65 ... 90, 95, 97 ... 122: true
                default: false
                }
            }
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            guard try values.decode(String.self, forKey: .kind) == Self.recordKind else {
                throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unsupported For You snapshot")
            }
            try self.init(
                itemIDs: values.decode([String].self, forKey: .itemIDs),
                createdAt: values.decode(Date.self, forKey: .createdAt)
            )
        }

        func isFresh(at date: Date = .now) -> Bool {
            let age = date.timeIntervalSince(createdAt)
            return !itemIDs.isEmpty && age >= -Self.clockTolerance && age < Self.lifetime
        }
    }

    /// The existing CloudKit schema already carries opaque Data payloads. A dedicated
    /// private zone isolates recommendation snapshots from the saved-media sync engine.
    @MainActor
    final class ForYouSnapshotSync {
        private struct Access {
            let database: CKDatabase
            let userID: CKRecord.ID
            let recordID: CKRecord.ID
        }

        private enum SyncError: Error {
            case accountUnavailable, accountChanged, missingSaveResult
        }

        private let scope: AccountScope
        private static let recordType = "SavedMediaRecord"
        private static let refreshInterval: TimeInterval = 24 * 60 * 60

        private lazy var container: CKContainer? = {
            guard Bundle.main.bundleURL.pathExtension == "app",
                  Bundle.main.bundleIdentifier == "dev.ericslutz.gus",
                  ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            else { return nil }
            #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                guard !arguments.contains("--gus-disable-cloud-sync"),
                      !arguments.contains("--gus-demo-server"),
                      !arguments.contains("--gus-debug-preview-session")
                else { return nil }
            #endif
            return CKContainer(identifier: "iCloud.dev.ericslutz.gus")
        }()

        init(scope: AccountScope) {
            self.scope = scope
        }

        func fetch() async throws -> ForYouSnapshot? {
            guard let access = try await access() else { return nil }
            do {
                let record = try await access.database.record(for: access.recordID)
                try await verifyIdentity(access.userID)
                guard let snapshot = Self.snapshot(from: record), snapshot.isFresh() else { return nil }
                return snapshot
            } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem || error.code == .userDeletedZone {
                return nil
            }
        }

        /// The caller persists this hash with the user's explicit sync consent.
        func currentPublishingIdentity() async throws -> String? {
            try await access().map { Self.digest($0.userID.recordName) }
        }

        func publish(itemIDs: [String], createdAt: Date = .now, identity: String) async throws {
            try await write(
                ForYouSnapshot(itemIDs: itemIDs, createdAt: createdAt),
                isRevocation: false,
                identity: identity
            )
        }

        func revoke(createdAt: Date = .now, identity: String) async throws {
            // A dated empty record prevents a concurrent, older upload from
            // restoring picks after this device has withdrawn them.
            try await write(ForYouSnapshot(itemIDs: [], createdAt: createdAt), isRevocation: true, identity: identity)
        }

        private func write(_ snapshot: ForYouSnapshot, isRevocation: Bool, identity: String) async throws {
            guard let access = try await access() else { return }
            guard Self.digest(access.userID.recordName) == identity else { throw SyncError.accountChanged }
            for attempt in 0 ..< 3 {
                do {
                    let record: CKRecord
                    do {
                        record = try await access.database.record(for: access.recordID)
                    } catch let error as CKError where error.code == .unknownItem {
                        guard isRevocation || !snapshot.itemIDs.isEmpty else { return }
                        record = CKRecord(recordType: Self.recordType, recordID: access.recordID)
                    }
                    try await verifyIdentity(access.userID)
                    if let existing = Self.snapshot(from: record) {
                        guard existing.createdAt < snapshot.createdAt else { return }
                        let age = Date.now.timeIntervalSince(existing.createdAt)
                        if !isRevocation, existing.itemIDs == snapshot.itemIDs, age >= 0, age < Self.refreshInterval {
                            return
                        }
                    }
                    record["payload"] = try JSONEncoder().encode(snapshot) as CKRecordValue
                    let result = try await access.database.modifyRecords(
                        saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged
                    )
                    guard let saved = result.saveResults[access.recordID] else { throw SyncError.missingSaveResult }
                    _ = try saved.get()
                    return
                } catch let error as CKError {
                    let code = (error.partialErrorsByItemID?[access.recordID] as? CKError)?.code ?? error.code
                    guard attempt < 2 else { throw error }
                    switch code {
                    case .zoneNotFound, .userDeletedZone:
                        guard isRevocation || !snapshot.itemIDs.isEmpty else { return }
                        try await verifyIdentity(access.userID)
                        _ = try await access.database.save(CKRecordZone(zoneID: access.recordID.zoneID))
                    case .serverRecordChanged, .unknownItem:
                        continue
                    default:
                        throw error
                    }
                }
            }
        }

        private func access() async throws -> Access? {
            try Task.checkCancellation()
            guard let container else { return nil }
            guard try await container.accountStatus() == .available else { throw SyncError.accountUnavailable }
            let userID = try await container.userRecordID()
            try Task.checkCancellation()
            // Length-prefixed components preserve account boundaries without exposing
            // the IDs as CloudKit record names. An explicit zone owner also prevents
            // an in-flight request from silently following a newly active account.
            let key = [scope.serverID, scope.userID, userID.recordName].map { "\($0.utf8.count):\($0)" }.joined()
            let zoneID = CKRecordZone.ID(zoneName: "ForYou-v1", ownerName: userID.recordName)
            let recordID = CKRecord.ID(recordName: Self.digest(key), zoneID: zoneID)
            return Access(database: container.privateCloudDatabase, userID: userID, recordID: recordID)
        }

        private func verifyIdentity(_ expected: CKRecord.ID) async throws {
            try Task.checkCancellation()
            guard let container, try await container.userRecordID() == expected else { throw SyncError.accountChanged }
            try Task.checkCancellation()
        }

        private static func digest(_ value: String) -> String {
            SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        private static func snapshot(from record: CKRecord) -> ForYouSnapshot? {
            guard record.recordType == recordType,
                  let data = record["payload"] as? Data, data.count <= 4096
            else { return nil }
            return try? JSONDecoder().decode(ForYouSnapshot.self, from: data)
        }
    }
#endif
