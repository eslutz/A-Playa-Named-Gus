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
        let version: UUID
        var needsSync: Bool
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

    func checkpoint(itemID: String, positionTicks: Int, scope: AccountScope, writerToken token: UUID? = nil) {
        if let token, token != writerToken(for: scope) {
            return
        }
        checkpoints[key(itemID: itemID, scope: scope)] = Checkpoint(
            serverID: scope.serverID, userID: scope.userID, itemID: itemID,
            positionTicks: max(0, positionTicks), version: UUID(), needsSync: true
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
            try await session.mediaProvider.updatePlaybackPosition(
                itemID: entry.itemID, positionTicks: entry.positionTicks
            )
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
            guard let entry = checkpoints[checkpointKey], entry.needsSync else { continue }
            do {
                try await upload(entry)
                guard !Task.isCancelled, isCurrentScope() else { return }
                guard checkpoints[checkpointKey]?.version == entry.version else { continue }
                checkpoints[checkpointKey]?.needsSync = false
                persist()
                revision += 1
            } catch {
                logger.debug("Saved offline progress remains pending")
                // An offline server would otherwise cost one timeout per item.
                return
            }
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
