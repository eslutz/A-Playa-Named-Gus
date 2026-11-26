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
        var ageCeiling: ContentRatingGate.Limit = .off
        let activityRevision: Int
        let tasteRevision: Int
        var forYouSyncEnabled = false

        @MainActor static func current(session: SessionStore, policy: ContentRatingGate.Policy, activityRevision: Int) -> Self {
            let preferences = session.intelligencePreferences
            #if os(tvOS)
                return .init(
                    cloudEnabled: false, recommendationsEnabled: preferences.forYouSyncEnabled,
                    limit: policy.limit.rawValue, hideUnrated: policy.hideUnrated, ageCeiling: policy.ageCeiling,
                    activityRevision: activityRevision, tasteRevision: 0
                )
            #else
                return .init(
                    cloudEnabled: preferences.cloudEnabled, recommendationsEnabled: preferences.recommendationsEnabled,
                    limit: policy.limit.rawValue, hideUnrated: policy.hideUnrated, ageCeiling: policy.ageCeiling,
                    activityRevision: activityRevision, tasteRevision: session.libraryIntelligence.tasteRevision,
                    forYouSyncEnabled: preferences.forYouSyncEnabled
                )
            #endif
        }

        @MainActor var currentRestrictions: Bool {
            let policy = ContentRatingGate.storedPolicy()
            return !policy.awaitingRequiredRange && limit == policy.limit.rawValue && hideUnrated == policy.hideUnrated && ageCeiling == policy.ageCeiling
        }
    }

    private static let freshness: TimeInterval = 6 * 60 * 60
    private(set) var picks: [GusLibraryPick] = []
    private(set) var error: String?
    private(set) var isLoading = false
    private var context: Context?
    private var successfulContext: Context?
    private var savedAt: Date?
    private var scope: AccountScope?
    private var generation = UUID()
    @ObservationIgnored private var pending: (context: Context, refresh: Bool, task: Task<Void, Never>)?

    init(session: SessionStore) {
        #if !os(tvOS)
            restore(.current(session: session, policy: ContentRatingGate.storedPolicy(), activityRevision: 0), session: session)
        #endif
    }

    func canDisplay(_ requested: Context, session: SessionStore) -> Bool {
        guard session.isActive, requested.recommendationsEnabled, requested.currentRestrictions, scope == session.references.scope,
              context?.limit == requested.limit, context?.hideUnrated == requested.hideUnrated, context?.ageCeiling == requested.ageCeiling else { return false }
        return savedAt.map { (0 ..< BrowseSnapshotCache.lifetime).contains(session.browseCache.now().timeIntervalSince($0)) } ?? true
    }

    func needsPlaceholder(_ requested: Context, session: SessionStore) -> Bool {
        !canDisplay(requested, session: session) || (isLoading && savedAt == nil)
    }

    func clear() {
        generation = UUID()
        pending?.task.cancel()
        pending = nil
        picks = []
        context = nil
        successfulContext = nil
        savedAt = nil
        scope = nil
        isLoading = false
        error = nil
    }

    #if !os(tvOS)
        private func restore(_ requested: Context, session: SessionStore) {
            guard session.isActive, requested.recommendationsEnabled,
                  let snapshot = session.browseCache.read("for-you", as: [GusLibraryPick].self) else { return }
            // Older payloads may contain episode IDs. They must be reranked as titles.
            picks = snapshot.value.filter { pick in
                pick.item.type.map(GusLibraryMatching.recommendationTypes.contains) == true && ContentRatingGate.admitsStored(pick.item)
            }
            scope = session.references.scope
            context = requested
            savedAt = snapshot.savedAt
            if picks.count == snapshot.value.count {
                successfulContext = requested
            }
        }
    #endif

    func load(_ requested: Context, session: SessionStore, refresh: Bool = false) async {
        guard !Task.isCancelled, requested.currentRestrictions else { return }
        guard session.isActive, requested.recommendationsEnabled else {
            clear()
            return
        }
        if let pending, pending.context == requested, !refresh || pending.refresh {
            await pending.task.value
            return
        }
        if !canDisplay(requested, session: session) {
            clear()
            #if !os(tvOS)
                restore(requested, session: session)
            #endif
        }
        #if !os(tvOS)
            if !refresh, successfulContext == requested, let savedAt,
               savedAt >= (session.intelligencePreferences.tasteChangedAt ?? .distantPast),
               session.browseCache.now().timeIntervalSince(savedAt) < Self.freshness
            {
                return
            }
        #endif

        pending?.task.cancel()
        let token = UUID()
        generation = token
        scope = session.references.scope
        context = requested
        error = nil
        isLoading = true
        let task = Task { await fetch(requested, session: session, refresh: refresh, generation: token) }
        pending = (requested, refresh, task)
        await task.value
        if generation == token {
            isLoading = false
            pending = nil
        }
    }

    private func fetch(_ requested: Context, session: SessionStore, refresh: Bool, generation token: UUID) async {
        do {
            #if os(tvOS)
                let result = try await loadSyncedPicks(session: session)
                try Task.checkCancellation()
                guard session.isActive, requested.currentRestrictions, generation == token, session.intelligencePreferences.forYouSyncEnabled else { return }
                picks = result
            #else
                let result = try await session.libraryIntelligence.recommendations(refresh: refresh)
                try Task.checkCancellation()
                guard session.isActive, requested.currentRestrictions, generation == token, session.intelligencePreferences.recommendationsEnabled else { return }
                picks = result.filter { ContentRatingGate.admitsStored($0.item) }
                let snapshot = picks.map { GusLibraryPick(item: $0.item.browseSnapshotItem, reason: $0.reason) }
                session.browseCache.write(snapshot, key: "for-you")
                #if os(iOS)
                    session.shareForYouPicks(picks)
                #endif
            #endif
            savedAt = session.browseCache.now()
            successfulContext = requested
        } catch {
            guard session.isActive, requested.currentRestrictions, !Task.isCancelled, generation == token else { return }
            let failure = GusError(from: error)
            guard !failure.isCancellation else { return }
            #if os(tvOS)
                // A failed iCloud or Jellyfin identity check cannot confirm this shelf.
                picks = []
            #else
                if failure == .forbidden || failure == .notFound || failure == .unauthorized {
                    session.browseCache.remove("for-you")
                    picks = []
                    savedAt = nil
                    successfulContext = nil
                } else if !canDisplay(requested, session: session) {
                    picks = []
                    savedAt = nil
                }
            #endif
            if picks.isEmpty {
                self.error = failure.localizedDescription
            }
            failure.handleIfUnauthorized(session: session)
        }
    }

    #if os(tvOS)
        private(set) var iCloudAccountRevision = 0

        func iCloudAccountChanged() {
            clear()
            iCloudAccountRevision += 1
        }

        private func loadSyncedPicks(session: SessionStore) async throws -> [GusLibraryPick] {
            let shared: ForYouSnapshot?
            do {
                shared = try await session.forYouSnapshotSync.fetch()
            } catch {
                try Task.checkCancellation()
                throw GusError.server(String(localized: "Couldn’t load recommendations from iCloud. Try again."))
            }
            guard let snapshot = shared, !snapshot.itemIDs.isEmpty else { return [] }
            try Task.checkCancellation()
            guard session.isActive else { return [] }
            var query = MediaItemQuery(
                includeTypes: GusLibraryMatching.recommendationTypes,
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
                $0.providerKind == .jellyfin && $0.type.map(GusLibraryMatching.recommendationTypes.contains) == true &&
                    $0.type != .book && admits($0)
            }
            // Jellyfin controls current access and metadata. Preserve the phone's rank.
            return snapshot.itemIDs.compactMap { id in
                valid.first { $0.id == id }.map { GusLibraryPick(item: $0, reason: "") }
            }
        }
    #endif
}
