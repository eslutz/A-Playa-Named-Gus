import Foundation
import Observation
import OSLog

/// Keeps the newest local checkpoint per account/item. A successful upload clears
/// only that version's pending flag, so playback during an upload cannot lose progress.
@MainActor
@Observable
final class OfflinePlaybackProgressStore {
    static let shared = OfflinePlaybackProgressStore()

    struct Checkpoint: Codable, Equatable {
        let serverID: String
        let userID: String
        let itemID: String
        let positionTicks: Int
        var version: UUID
        var needsSync: Bool
        var reference: MediaReference? = nil
        var replacement: MediaItem? = nil
        var blockedReason: String? = nil
    }

    private(set) var revision = 0
    private var checkpoints: [String: Checkpoint] = [:]
    private var syncingScopes: Set<AccountScope> = []
    private var writerTokens: [AccountScope: UUID] = [:]
    private let fileURL: URL
    private let logger = Logger(category: .playback)

    init(directory: URL = AppStorageLocation.appDirectory()) {
        fileURL = directory.appendingPathComponent("offline-playback-progress.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: Checkpoint].self, from: data)
        {
            checkpoints = saved
        }
    }

    func positionTicks(forItemID itemID: String, scope: AccountScope) -> Int? {
        checkpoints[key(itemID: itemID, scope: scope)]?.positionTicks
    }

    /// A player captures this token when it opens. Purging an account rotates it so
    /// teardown from a dismissed old player cannot recreate that account's progress.
    func writerToken(for scope: AccountScope) -> UUID {
        if let token = writerTokens[scope] {
            return token
        }
        let token = UUID()
        writerTokens[scope] = token
        return token
    }

    func checkpoint(itemID: String, positionTicks: Int, scope: AccountScope, writerToken token: UUID? = nil, item: MediaItem? = nil) {
        if let token, token != writerToken(for: scope) {
            return
        }
        checkpoints[key(itemID: itemID, scope: scope)] = Checkpoint(
            serverID: scope.serverID, userID: scope.userID, itemID: itemID,
            positionTicks: max(0, positionTicks), version: UUID(), needsSync: true,
            reference: item.map { MediaReference(item: $0, scope: scope) }
        )
        persist()
        revision += 1
    }

    func pendingCheckpoints(scope: AccountScope) -> [Checkpoint] {
        checkpoints.values.filter {
            $0.serverID == scope.serverID && $0.userID == scope.userID && $0.needsSync
        }.sorted { $0.itemID < $1.itemID }
    }

    /// Recheck the active account before and after every upload. Failures remain pending
    /// and never sign out the account or disturb local playback.
    func sync(session: SessionStore, isCurrentScope: @escaping () -> Bool) async {
        let scope = AccountScope(serverID: session.server.id, userID: session.user.id)
        await sync(scope: scope, isCurrentScope: isCurrentScope) { entry in
            let reference = entry.reference ?? MediaReference(item: MediaItem(id: entry.itemID), scope: scope)
            let result = try await session.references.resolve(reference, forceRefresh: true)
            try Task.checkCancellation()
            guard isCurrentScope(), session.references.isActive,
                  self.checkpoints[self.key(itemID: entry.itemID, scope: scope)]?.version == entry.version else { throw GusError.cancelled }
            guard case let .resolved(current) = result, let currentID = current.id else { throw GusError.notFound }
            guard currentID == entry.itemID else {
                self.offerTransfer(from: entry.itemID, to: current, scope: scope)
                throw GusError.notFound
            }
            try await session.mediaProvider.updatePlaybackPosition(itemID: currentID, positionTicks: entry.positionTicks)
        }
    }

    /// Injectable upload operation keeps replacement races and account changes testable.
    func sync(
        scope: AccountScope,
        isCurrentScope: () -> Bool,
        upload: (Checkpoint) async throws -> Void
    ) async {
        guard isCurrentScope(), !syncingScopes.contains(scope) else { return }
        syncingScopes.insert(scope)
        defer { syncingScopes.remove(scope) }
        for snapshot in pendingCheckpoints(scope: scope) {
            guard !Task.isCancelled, isCurrentScope() else { return }
            let checkpointKey = key(itemID: snapshot.itemID, scope: scope)
            // A checkpoint may have changed while another item was being uploaded.
            guard let entry = checkpoints[checkpointKey], entry.needsSync, entry.blockedReason == nil else { continue }
            do {
                try await upload(entry)
                guard !Task.isCancelled, isCurrentScope() else { return }
                guard checkpoints[checkpointKey]?.version == entry.version else { continue }
                checkpoints[checkpointKey]?.needsSync = false
                persist()
                revision += 1
            } catch {
                if GusError(from: error) == .notFound {
                    guard checkpoints[checkpointKey]?.version == entry.version else { continue }
                    checkpoints[checkpointKey]?.blockedReason = "unavailable"
                    persist()
                    revision += 1
                    continue
                }
                logger.debug("Saved offline progress remains pending")
                // An offline server would otherwise cost one timeout per item.
                return
            }
        }
    }

    func offerTransfer(from itemID: String?, to replacement: MediaItem, scope: AccountScope) {
        guard let itemID, replacement.id != itemID else { return }
        let sourceKey = key(itemID: itemID, scope: scope)
        guard var checkpoint = checkpoints[sourceKey], checkpoint.needsSync else { return }
        if checkpoint.replacement?.id == replacement.id {
            return
        }
        checkpoint.version = UUID()
        checkpoint.replacement = replacement
        checkpoint.blockedReason = "confirmation"
        checkpoints[sourceKey] = checkpoint
        persist()
        revision += 1
    }

    func unavailableCheckpoints(scope: AccountScope) -> [Checkpoint] {
        pendingCheckpoints(scope: scope).filter { $0.blockedReason == "unavailable" && $0.replacement == nil }
    }

    func selectReplacement(_ snapshot: Checkpoint, candidate: MediaItem, session: SessionStore) async -> Bool {
        let scope = session.references.scope
        guard snapshot.serverID == scope.serverID, snapshot.userID == scope.userID else { return false }
        do {
            let current = try await session.references.selectedReplacement(candidate)
            guard checkpoints[key(itemID: snapshot.itemID, scope: scope)]?.version == snapshot.version else { return false }
            offerTransfer(from: snapshot.itemID, to: current, scope: scope)
            return true
        } catch { return false }
    }

    func retry(_ snapshot: Checkpoint, scope: AccountScope) {
        guard snapshot.serverID == scope.serverID, snapshot.userID == scope.userID else { return }
        let sourceKey = key(itemID: snapshot.itemID, scope: scope)
        guard checkpoints[sourceKey]?.version == snapshot.version else { return }
        checkpoints[sourceKey]?.blockedReason = nil
        persist()
        revision += 1
    }

    func transfers(scope: AccountScope) -> [Checkpoint] {
        checkpoints.values.filter { $0.serverID == scope.serverID && $0.userID == scope.userID && $0.replacement != nil && $0.needsSync }
            .sorted { $0.itemID < $1.itemID }
    }

    /// Retain original local positions and file-specific book locators. Only a
    /// confirmed transfer creates a checkpoint for the current remote identity.
    func confirmTransfer(_ snapshot: Checkpoint, session: SessionStore) async throws {
        let scope = session.references.scope
        guard snapshot.serverID == scope.serverID, snapshot.userID == scope.userID,
              let replacement = snapshot.replacement else { throw GusError.notFound }
        let current = try await session.references.currentItem(replacement)
        try Task.checkCancellation()
        let sourceKey = key(itemID: snapshot.itemID, scope: scope)
        guard var source = checkpoints[sourceKey], source.version == snapshot.version,
              let currentID = current.id, currentID == replacement.id else { throw GusError.notFound }
        let destinationKey = key(itemID: currentID, scope: scope)
        // Never replace newer locally recorded destination progress.
        guard checkpoints[destinationKey] == nil else { throw GusError.server(String(localized: "This item already has local progress.", comment: "Progress transfer conflict")) }
        var ticks = source.positionTicks
        if let runtime = current.runTimeTicks, runtime > 0 {
            ticks = min(ticks, max(0, runtime - 1))
        }
        checkpoints[destinationKey] = Checkpoint(
            serverID: scope.serverID,
            userID: scope.userID,
            itemID: currentID,
            positionTicks: ticks,
            version: UUID(),
            needsSync: true,
            reference: MediaReference(item: current, scope: scope)
        )
        source.needsSync = false
        source.replacement = nil
        source.blockedReason = "keptLocal"
        checkpoints[sourceKey] = source
        persist()
        revision += 1
    }

    func keepTransferLocal(_ snapshot: Checkpoint, scope: AccountScope) {
        guard snapshot.serverID == scope.serverID, snapshot.userID == scope.userID else { return }
        let sourceKey = key(itemID: snapshot.itemID, scope: scope)
        guard var source = checkpoints[sourceKey], source.version == snapshot.version else { return }
        source.needsSync = false
        source.replacement = nil
        source.blockedReason = "keptLocal"
        checkpoints[sourceKey] = source
        persist()
        revision += 1
    }

    func retryUnavailable(scope: AccountScope) {
        for (key, entry) in checkpoints where entry.serverID == scope.serverID && entry.userID == scope.userID && entry.blockedReason == "unavailable" && entry.replacement == nil {
            checkpoints[key]?.blockedReason = nil
        }
    }

    func deleteCheckpoints(scope: AccountScope) {
        writerTokens[scope] = UUID()
        checkpoints = checkpoints.filter { _, value in
            value.serverID != scope.serverID || value.userID != scope.userID
        }
        persist()
        revision += 1
    }

    /// Length-prefixed raw identities prevent aliases from filesystem sanitization.
    private func key(itemID: String, scope: AccountScope) -> String {
        [scope.serverID, scope.userID, itemID].map { "\($0.utf8.count):\($0)" }.joined()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(checkpoints)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not save offline playback progress: \(error.localizedDescription, privacy: .private)")
        }
    }
}
