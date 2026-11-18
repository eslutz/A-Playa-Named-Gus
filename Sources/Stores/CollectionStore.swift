import Foundation
import Observation

enum CollectionWriteExpectation {
    case contains([String])
    case excludes([String])
    case deleted
}

/// Session-owned server snapshots. Collection edits are never journaled locally.
@MainActor @Observable
final class CollectionStore {
    let session: SessionStore
    private(set) var collections: [MediaCollection] = []
    private(set) var capabilities = CollectionCapabilities()
    private(set) var state: LoadState = .idle
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?
    private(set) var isMutating = false
    private(set) var actionOutcome: ActionOutcome?
    private(set) var needsMutationReview = false
    private(set) var canKeepCurrentServerState = false
    private(set) var reviewCollectionID: String?
    private var finishedCatalogRead = false
    var hasCompleteMembershipCatalog: Bool {
        finishedCatalogRead && collections.allSatisfy { $0.membersLoaded && memberErrors[$0.id] == nil }
    }

    var canSubmitMutations: Bool {
        active && session.isActive && !isMutating && !needsMutationReview
    }

    private(set) var revision = 0
    private(set) var memberErrors: [String: String] = [:]
    private var libraryMovieIDs: [String: Set<String>] = [:]
    private(set) var libraryErrors: [String: String] = [:]
    private var staleLibraryIDs: Set<String> = []
    private var libraryTasks: [String: Task<Void, Never>] = [:]
    private var generation = 0
    private var permissionsLoaded = false
    private var permissionsTask: Task<Void, Never>?
    private var active = true
    private(set) var detailCapabilities: [String: CollectionCapabilities] = [:]
    private var loadTask: Task<Void, Never>?
    private var refreshAgain = false
    private var detailTasks: [String: Task<Void, Never>] = [:]

    init(session: SessionStore) {
        self.session = session
    }

    func collection(_ id: String) -> MediaCollection? {
        if let exact = collections.first(where: { $0.id == id }) {
            return exact
        }
        guard let uuid = ServerMediaListID.uuid(id) else { return nil }
        return collections.first { ServerMediaListID.uuid($0.id) == uuid }
    }

    func memberships(for itemID: String) -> [MediaCollection] {
        collections.filter { collection in
            ContentRatingGate.admitsStored(collection.item) && collection.members.contains { $0.id == itemID && ContentRatingGate.admitsStored($0) }
        }
    }

    func relevant(to libraryID: String?) -> [MediaCollection] {
        guard let libraryID else { return collections.filter { $0.members.contains { $0.type == .movie && ContentRatingGate.admitsStored($0) } } }
        guard let ids = libraryMovieIDs[libraryID] else { return [] }
        return collections.filter { $0.members.contains { $0.type == .movie && $0.id.map(ids.contains) == true && ContentRatingGate.admitsStored($0) } }
    }

    func hasLibraryMembership(_ libraryID: String) -> Bool {
        libraryMovieIDs[libraryID] != nil
    }

    func permissions(for id: String) -> CollectionCapabilities {
        detailCapabilities[id] ?? .init()
    }

    func clearError() {
        if !needsMutationReview {
            errorMessage = nil
        }
    }

    func loadPermissions() async {
        guard active, !permissionsLoaded else { return }
        if let permissionsTask {
            await permissionsTask.value; return
        }
        let token = generation
        let task = Task {
            let value = (try? await session.mediaProvider.collectionCapabilities(id: nil)) ?? .init()
            guard token == generation else { return }
            capabilities = value
            permissionsLoaded = true
        }
        permissionsTask = task
        await task.value
        if token == generation {
            permissionsTask = nil
        }
    }

    func invalidate() {
        active = false
        generation += 1
        actionOutcome = nil
        reviewCollectionID = nil
        finishedCatalogRead = false
        canKeepCurrentServerState = false
        loadTask?.cancel()
        detailTasks.values.forEach { $0.cancel() }
        libraryTasks.values.forEach { $0.cancel() }
        libraryTasks = [:]; staleLibraryIDs = []
        collections = []; capabilities = .init(); libraryMovieIDs = [:]
    }

    /// The last visible collection surface can stop foreground reads without
    /// deleting the last confirmed server snapshot or disabling future visits.
    func cancelForegroundLoads() {
        let interruptedRefresh = loadTask != nil
        if interruptedRefresh {
            finishedCatalogRead = false
        }
        generation += 1
        loadTask?.cancel(); loadTask = nil
        permissionsTask?.cancel(); permissionsTask = nil
        detailTasks.values.forEach { $0.cancel() }; detailTasks = [:]
        libraryTasks.values.forEach { $0.cancel() }; libraryTasks = [:]
        refreshAgain = false
        // Headers become visible before all member pages finish. Re-entering
        // the browser must resume an interrupted refresh even with cached headers.
        state = interruptedRefresh || collections.isEmpty ? .idle : .loaded
    }

    func load(force: Bool = false) async {
        guard active, !Task.isCancelled else { return }
        if let loadTask {
            if force {
                refreshAgain = true
            }
            await loadTask.value
            return
        }
        guard force || state != .loaded else { return }
        let requestGeneration = generation
        let task = Task {
            repeat {
                refreshAgain = false
                staleLibraryIDs.formUnion(libraryMovieIDs.keys); libraryErrors = [:]
                await refresh()
            } while refreshAgain && active && !Task.isCancelled
        }
        loadTask = task
        await task.value
        if requestGeneration == generation {
            loadTask = nil
        }
    }

    private func refresh() async {
        let token = generation
        finishedCatalogRead = false
        state = collections.isEmpty ? .loading : state
        errorMessage = nil
        if needsMutationReview {
            canKeepCurrentServerState = false
        }
        do {
            let permissions = (try? await session.mediaProvider.collectionCapabilities(id: nil)) ?? .init()
            try Task.checkCancellation()
            guard active, token == generation else { return }
            capabilities = permissions
            permissionsLoaded = true
            let loadedHeaders = try await readCollectionPages { offset, size in
                try await self.session.mediaProvider.collectionPage(startIndex: offset, limit: size)
            }
            try Task.checkCancellation()
            guard active, token == generation else { return }
            let headers = loadedHeaders.filter { $0.id != nil && ContentRatingGate.admitsStored($0) }
            collections = headers.map { header in
                var value = collection(header.id!) ?? MediaCollection(item: header)
                value.item = header
                return value
            }
            state = .loaded
            memberErrors = [:]
            // Each batch limits server work without sharing a mutable iterator between tasks.
            let ids = collections.map(\.id)
            for start in stride(from: 0, to: ids.count, by: 4) {
                guard token == generation, !Task.isCancelled else { return }
                async let first: Void = loadIndexedDetail(ids, index: start)
                async let second: Void = loadIndexedDetail(ids, index: start + 1)
                async let third: Void = loadIndexedDetail(ids, index: start + 2)
                async let fourth: Void = loadIndexedDetail(ids, index: start + 3)
                _ = await(first, second, third, fourth)
            }
            if token == generation, !Task.isCancelled {
                finishedCatalogRead = true
                if needsMutationReview {
                    canKeepCurrentServerState = hasReviewSnapshot
                }
                if memberErrors.isEmpty {
                    statusMessage = nil
                } else {
                    errorMessage = String(localized: "Some collection memberships could not be loaded. Refresh to retry.")
                }
            }
        } catch {
            if token == generation {
                report(error); if collections.isEmpty {
                    state = .failed(errorMessage ?? "")
                }
            }
        }
    }

    private func loadIndexedDetail(_ ids: [String], index: Int) async {
        guard index < ids.count, !Task.isCancelled else { return }
        let id = ids[index]
        guard let header = collection(id)?.item else { return }
        await loadMembers(id: id, listedHeader: header, force: true)
    }

    func loadDetail(id: String, force: Bool = false) async {
        let id = collection(id)?.id ?? id
        let token = generation
        await loadMembers(id: id, listedHeader: nil, force: force)
        guard active, !Task.isCancelled, token == generation, collection(id) != nil,
              force || detailCapabilities[id] == nil else { return }
        let permissions = (try? await session.mediaProvider.collectionCapabilities(id: id)) ?? .init()
        guard active, !Task.isCancelled, token == generation, collection(id) != nil else { return }
        detailCapabilities[id] = permissions
    }

    private func loadMembers(id: String, listedHeader: MediaItem?, force: Bool) async {
        guard active, !Task.isCancelled else { return }
        if let task = detailTasks[id] {
            await task.value; return
        }
        guard force || collection(id)?.membersLoaded != true else { return }
        let requestGeneration = generation
        let task = Task { await fetchDetail(id, listedHeader: listedHeader) }
        detailTasks[id] = task
        await task.value
        if requestGeneration == generation {
            detailTasks[id] = nil
        }
    }

    private func fetchDetail(_ id: String, listedHeader: MediaItem?) async {
        guard active, !Task.isCancelled else { return }
        let token = generation
        do {
            let item: MediaItem
            if let listedHeader {
                item = listedHeader
            } else {
                item = try await session.mediaProvider.collectionItem(id: id)
            }
            let loadedMembers = try await readCollectionPages { offset, size in
                try await self.session.mediaProvider.collectionMembers(id: id, startIndex: offset, limit: size)
            }
            try Task.checkCancellation()
            guard active, token == generation else { return }
            let value = MediaCollection(item: item, members: loadedMembers, membersLoaded: true)
            if let index = collections.firstIndex(where: { $0.id == value.id }) {
                collections[index] = value
            } else if ContentRatingGate.admitsStored(item) {
                collections.append(value)
            }
            memberErrors[id] = nil
            revision += 1
        } catch {
            if token == generation {
                let failure = GusError(from: error)
                if failure == .notFound, listedHeader == nil {
                    collections.removeAll { $0.id == id }; detailCapabilities[id] = nil
                }
                memberErrors[id] = failure.localizedDescription; report(error)
            }
        }
    }

    /// Overlapping pages can conceal skipped members. A snapshot used to verify
    /// a removal must contain a distinct identity for every row Jellyfin returned.
    private func readCollectionPages(_ page: (Int, Int) async throws -> MediaItemPage) async throws -> [MediaItem] {
        var seen = Set<String>()
        var expectedTotal: Int?
        return try await MediaPageLoader.collect { offset, size in
            let result = try await page(offset, size)
            if let total = result.totalRecordCount {
                guard total >= offset + result.items.count, expectedTotal == nil || total == expectedTotal else {
                    throw GusError.server(String(localized: "The server returned an incomplete collection. Try again."))
                }
                expectedTotal = total
            }
            for item in result.items {
                guard let id = item.id, !id.isEmpty, seen.insert(Self.identity(id)).inserted else {
                    throw GusError.server(String(localized: "The server returned an incomplete collection. Try again."))
                }
            }
            return result
        }
    }

    private static func identity(_ id: String) -> String {
        ServerMediaListID.uuid(id).map(ServerMediaListID.string) ?? id
    }

    func loadLibrary(_ id: String?) async {
        guard active, !Task.isCancelled else { return }
        await load()
        guard active, !Task.isCancelled, let id else { return }
        if let task = libraryTasks[id] {
            await task.value; return
        }
        guard libraryMovieIDs[id] == nil || staleLibraryIDs.contains(id) else { return }
        let requestGeneration = generation
        let task = Task { await fetchLibrary(id) }
        libraryTasks[id] = task
        await task.value
        if requestGeneration == generation {
            libraryTasks[id] = nil
        }
    }

    private func fetchLibrary(_ id: String) async {
        let token = generation
        do {
            let items = try await session.mediaProvider.allItems(query: .init(parentID: id, includeTypes: [.movie], startIndex: 0, limit: 200, isRecursive: true))
            try Task.checkCancellation()
            guard active, token == generation else { return }
            libraryMovieIDs[id] = Set(ContentRatingGate.filter(items).compactMap(\.id))
            staleLibraryIDs.remove(id)
            libraryErrors[id] = nil
        } catch {
            guard active, token == generation else { return }
            let failure = GusError(from: error)
            if !failure.isCancellation {
                libraryErrors[id] = failure.localizedDescription
            }
        }
    }

    func saveMetadata(id: String, name: String?, expectedName: String, overview: String?, expectedOverview: String) async -> Bool {
        guard capabilities.editMetadata else { return false }
        return await mutate(collectionID: id) {
            try await session.mediaProvider.editMediaListMetadata(
                .collection(id),
                name: name,
                expectedName: expectedName,
                overview: overview,
                expectedOverview: expectedOverview
            )
            return id
        }
    }

    func saveCover(id: String, change: MediaListCoverEdit, expectedTag: String?) async -> Bool {
        guard capabilities.editArtwork else { return false }
        return await mutate(collectionID: id) {
            try await session.mediaProvider.editMediaListCover(.collection(id), change: change, expectedTag: expectedTag)
            return id
        }
    }

    @discardableResult
    func mutate(collectionID: String? = nil, verifying expectation: CollectionWriteExpectation? = nil, _ operation: () async throws -> String?) async -> Bool {
        guard canSubmitMutations, !Task.isCancelled else { return false }
        isMutating = true; errorMessage = nil; statusMessage = nil
        actionOutcome = .pending
        reviewCollectionID = collectionID
        canKeepCurrentServerState = false
        defer { isMutating = false }
        do {
            let returnedID = try await operation()
            // Visibility supersedes reads, but a transmitted write still belongs
            // to this immutable session and must retain its accepted/unknown result.
            guard active, session.isActive else { actionOutcome = nil; return false }
            reviewCollectionID = collectionID ?? returnedID
            guard !Task.isCancelled else {
                requireMutationReview(cancelled: true)
                return false
            }
            libraryMovieIDs = [:]
            if expectation != nil {
                // A detail request started before the write cannot confirm it, even
                // when its response arrives after Jellyfin acknowledges the edit.
                cancelForegroundLoads()
            }
            await load(force: true)
            guard active, session.isActive else { actionOutcome = nil; return false }
            guard !Task.isCancelled else {
                requireMutationReview(cancelled: true)
                return false
            }
            if let expectation {
                let confirmed = await confirms(expectation)
                guard active, session.isActive else { actionOutcome = nil; return false }
                guard !Task.isCancelled else {
                    requireMutationReview(cancelled: true)
                    return false
                }
                guard confirmed else {
                    requireMutationReview(cancelled: false, afterReadback: true)
                    return false
                }
            } else if errorMessage != nil {
                needsMutationReview = true
                statusMessage = String(localized: "Saved; refresh unavailable. Pull to refresh before making another change.")
            }
            actionOutcome = expectation == nil ? .accepted : .confirmed
            if !needsMutationReview {
                reviewCollectionID = nil
            }
            revision += 1
            return true
        } catch {
            guard active, session.isActive else { actionOutcome = nil; return false }
            let failure = GusError(from: error)
            if failure.isCancellation || Task.isCancelled {
                requireMutationReview(cancelled: true)
                return false
            }
            report(error)
            guard active, session.isActive else { actionOutcome = nil; return false }
            switch failure {
            case .timeout, .offline, .network:
                requireMutationReview(cancelled: false)
            case .unknown where expectation != nil && error is DecodingError:
                requireMutationReview(cancelled: false)
            default:
                actionOutcome = .failed(failure)
                reviewCollectionID = nil
            }
            // Authorization can change while a sheet is open. Never retry a write.
            let permissions = (try? await session.mediaProvider.collectionCapabilities(id: nil)) ?? .init()
            guard active, session.isActive, !Task.isCancelled else { return false }
            capabilities = permissions
            return false
        }
    }

    var reviewedCollection: MediaCollection? {
        guard let reviewCollectionID else { return nil }
        return collection(reviewCollectionID)
    }

    private var hasReviewSnapshot: Bool {
        guard finishedCatalogRead else { return false }
        guard reviewCollectionID != nil else { return hasCompleteMembershipCatalog }
        guard let collection = reviewedCollection else { return true }
        return collection.membersLoaded && memberErrors[collection.id] == nil
    }

    private func confirms(_ expectation: CollectionWriteExpectation) async -> Bool {
        guard let reviewCollectionID, hasReviewSnapshot else { return false }
        let members = reviewedCollection.map { Set($0.members.compactMap(\.id).map(Self.identity)) }
        switch expectation {
        case let .contains(added): return members?.isSuperset(of: added.map(Self.identity)) == true
        case let .excludes(removed): return members?.isDisjoint(with: removed.map(Self.identity)) == true
        case .deleted:
            // A collection may disappear from a filtered catalog while the object
            // still exists. Confirm absence with the current user's item endpoint.
            guard members == nil else { return false }
            do {
                _ = try await session.mediaProvider.item(id: reviewCollectionID)
                return false
            } catch {
                let failure = GusError(from: error)
                failure.handleIfUnauthorized(session: session)
                return failure == .notFound
            }
        }
    }

    private func requireMutationReview(cancelled: Bool, afterReadback: Bool = false) {
        if !afterReadback {
            cancelForegroundLoads()
            finishedCatalogRead = false
        }
        needsMutationReview = true
        canKeepCurrentServerState = hasReviewSnapshot
        actionOutcome = cancelled ? nil : .uncertain
        errorMessage = String(localized: "The collection change was not confirmed. Refresh and review the server state before making another change.")
    }

    /// Readback never repeats a mutation. The user explicitly accepts the freshly
    /// loaded server snapshot before a duplicate-capable action can be submitted again.
    func keepCurrentServerState() {
        guard canKeepCurrentServerState, !isMutating else { return }
        needsMutationReview = false
        canKeepCurrentServerState = false
        reviewCollectionID = nil
        actionOutcome = nil
        errorMessage = nil
        statusMessage = nil
    }

    private func report(_ error: any Error) {
        let failure = GusError(from: error)
        guard !failure.isCancellation else { return }
        errorMessage = failure.localizedDescription
        failure.handleIfUnauthorized(session: session)
    }
}
