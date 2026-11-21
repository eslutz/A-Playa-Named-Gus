import Foundation
import Observation

/// The shelf refreshes independently of Home's playback and discovery rails.
@MainActor @Observable
final class ForYouShelfState {
    struct Context: Equatable {
        let cloudEnabled: Bool
        let recommendationsEnabled: Bool
        let limit: String
        let hideUnrated: Bool
        let activityRevision: Int
        let tasteRevision: Int
        var forYouSyncEnabled = false
    }

    private(set) var picks: [GusLibraryPick] = []
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var context: Context?
    private var generation = UUID()

    func load(_ context: Context, session: SessionStore, refresh: Bool = false) async {
        let previous = self.context
        let token = UUID()
        generation = token
        self.context = context
        error = nil
        if previous != context {
            picks = []
        }
        guard session.isActive, context.recommendationsEnabled else {
            picks = []
            isLoading = false
            return
        }
        isLoading = true
        defer {
            if generation == token {
                isLoading = false
            }
        }
        do {
            #if os(tvOS)
                let result = try await loadSyncedPicks(session: session)
                try Task.checkCancellation()
                guard session.isActive, generation == token, session.intelligencePreferences.forYouSyncEnabled else { return }
                picks = result
            #else
                let result = try await session.libraryIntelligence.recommendations(refresh: refresh)
                try Task.checkCancellation()
                guard session.isActive, generation == token, session.intelligencePreferences.recommendationsEnabled else { return }
                picks = result.filter { ContentRatingGate.admitsStored($0.item) }
                #if os(iOS)
                    session.shareForYouPicks(picks)
                #endif
            #endif
        } catch {
            guard session.isActive, !Task.isCancelled, generation == token else { return }
            let failure = GusError(from: error)
            failure.handleIfUnauthorized(session: session)
            if !failure.isCancellation {
                picks = []
                #if !os(tvOS)
                    self.error = error.localizedDescription
                #endif
            }
        }
    }

    #if os(tvOS)
        func clearSyncedPicks() {
            generation = UUID()
            picks = []
            isLoading = false
        }

        private func loadSyncedPicks(session: SessionStore) async throws -> [GusLibraryPick] {
            guard let snapshot = try await session.forYouSnapshotSync.fetch(), !snapshot.itemIDs.isEmpty else { return [] }
            try Task.checkCancellation()
            guard session.isActive else { return [] }
            var query = MediaItemQuery(
                includeTypes: GusLibraryMatching.types,
                startIndex: 0,
                limit: snapshot.itemIDs.count,
                isRecursive: true
            )
            query.metadataOnly = true
            query.itemIDs = snapshot.itemIDs
            let page = try await session.mediaProvider.items(query: query)
            return Self.syncedPicks(snapshot, from: page.items, admits: { ContentRatingGate.admitsStored($0) })
        }
    #endif

    #if os(iOS) || os(tvOS)
        static func syncedPicks(
            _ snapshot: ForYouSnapshot,
            from items: [MediaItem],
            now: Date = .now,
            admits: (MediaItem) -> Bool
        ) -> [GusLibraryPick] {
            guard snapshot.isFresh(at: now) else { return [] }
            let valid = items.filter {
                $0.providerKind == .jellyfin && $0.type.map(GusLibraryMatching.types.contains) == true &&
                    $0.type != .book && admits($0)
            }
            // Jellyfin controls current access and metadata. Preserve the phone's rank.
            return snapshot.itemIDs.compactMap { id in
                valid.first { $0.id == id }.map { GusLibraryPick(item: $0, reason: "") }
            }
        }
    #endif
}
