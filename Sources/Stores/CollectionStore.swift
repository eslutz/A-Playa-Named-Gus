import Foundation
import Observation

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
    var canSubmitMutations: Bool {
        active && session.isActive && !isMutating && !needsMutationReview
    }

    private(set) var revision = 0
    private(set) var memberErrors: [String: String] = [:]
    private var libraryMovieIDs: [String: Set<String>] = [:]
    private var libraryErrors: [String: String] = [:]
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
        collections.first { $0.id == id }
    }

    func memberships(for movieID: String) -> [MediaCollection] {
        collections.filter { $0.members.contains { $0.id == movieID && ContentRatingGate.admitsStored($0) } }
    }

    func relevant(to libraryID: String?) -> [MediaCollection] {
        guard let libraryID else { return collections.filter { $0.members.contains { $0.type == .movie && ContentRatingGate.admitsStored($0) } } }
        guard let ids = libraryMovieIDs[libraryID] else { return [] }
        return collections.filter { $0.members.contains { $0.type == .movie && $0.id.map(ids.contains) == true && ContentRatingGate.admitsStored($0) } }
    }

    func discoveryError(libraryID: String?) -> String? {
        libraryID.flatMap { libraryErrors[$0] } ?? errorMessage
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
        generation += 1
        loadTask?.cancel(); loadTask = nil
        permissionsTask?.cancel(); permissionsTask = nil
        detailTasks.values.forEach { $0.cancel() }; detailTasks = [:]
        libraryTasks.values.forEach { $0.cancel() }; libraryTasks = [:]
        refreshAgain = false
        state = collections.isEmpty ? .idle : .loaded
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
            let loadedHeaders = try await MediaPageLoader.collect { offset, size in
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
            if token == generation {
                if memberErrors.isEmpty {
                    statusMessage = nil
                    if needsMutationReview {
                        canKeepCurrentServerState = true
                    }
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
        await loadDetail(id: ids[index], force: true)
    }

    func loadDetail(id: String, force: Bool = false) async {
        guard active, !Task.isCancelled else { return }
        if let task = detailTasks[id] {
            await task.value; return
        }
        guard force || collection(id)?.membersLoaded != true else { return }
        let requestGeneration = generation
        let task = Task { await fetchDetail(id) }
        detailTasks[id] = task
        await task.value
        if requestGeneration == generation {
            detailTasks[id] = nil
        }
    }

    private func fetchDetail(_ id: String) async {
        guard active, !Task.isCancelled else { return }
        let token = generation
        do {
            let item = try await session.mediaProvider.collectionItem(id: id)
            let permissions = (try? await session.mediaProvider.collectionCapabilities(id: id)) ?? .init()
            let loadedMembers = try await MediaPageLoader.collect { offset, size in
                try await self.session.mediaProvider.collectionMembers(id: id, startIndex: offset, limit: size)
            }
            try Task.checkCancellation()
            guard active, token == generation else { return }
            let members = loadedMembers.filter { $0.id != nil }
            detailCapabilities[id] = permissions
            let value = MediaCollection(item: item, members: members, membersLoaded: true)
            if let index = collections.firstIndex(where: { $0.id == id }) {
                collections[index] = value
            } else if ContentRatingGate.admitsStored(item) {
                collections.append(value)
            }
            memberErrors[id] = nil
            revision += 1
        } catch {
            if token == generation {
                let failure = GusError(from: error)
                if failure == .notFound {
                    collections.removeAll { $0.id == id }; detailCapabilities[id] = nil
                }
                memberErrors[id] = failure.localizedDescription; report(error)
            }
        }
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

    /// Metadata and artwork use separate server endpoints. Reconcile a confirmed
    /// metadata save even if the following artwork request fails or is uncertain.
    func saveEdits(id: String, name: String, overview: String, artwork: Data?) async -> Bool {
        guard canSubmitMutations, capabilities.permitsEdit(artworkIncluded: artwork != nil) else { return false }
        let permissions = capabilities
        var metadataSaved = false
        let saved = await mutate {
            if permissions.editMetadata {
                try await session.mediaProvider.updateCollection(id: id, name: name, overview: overview)
                metadataSaved = true
            }
            try Task.checkCancellation()
            guard active, session.isActive else { throw GusError.cancelled }
            if let artwork {
                try await session.mediaProvider.setCollectionArtwork(id: id, jpeg: artwork)
            }
            return id
        }
        if !saved, metadataSaved, active, session.isActive, !Task.isCancelled {
            let failure = errorMessage
            needsMutationReview = true
            actionOutcome = .uncertain
            await load(force: true)
            guard active, session.isActive, !Task.isCancelled else { return false }
            errorMessage = failure
            statusMessage = String(localized: "Name and description saved. Check artwork in Jellyfin before retrying.")
        }
        return saved
    }

    @discardableResult
    func mutate(_ operation: () async throws -> String?) async -> Bool {
        guard canSubmitMutations, !Task.isCancelled else { return false }
        isMutating = true; errorMessage = nil; statusMessage = nil
        actionOutcome = .pending
        canKeepCurrentServerState = false
        defer { isMutating = false }
        do {
            _ = try await operation()
            // Visibility supersedes reads, but a transmitted write still belongs
            // to this immutable session and must retain its accepted/unknown result.
            guard active, session.isActive else { actionOutcome = nil; return false }
            guard !Task.isCancelled else {
                requireMutationReview(cancelled: true)
                return false
            }
            actionOutcome = .accepted
            libraryMovieIDs = [:]
            await load(force: true)
            guard active, session.isActive, !Task.isCancelled else { return false }
            if errorMessage != nil {
                needsMutationReview = true
                statusMessage = String(localized: "Saved; refresh unavailable. Pull to refresh before making another change.")
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
            default:
                actionOutcome = .failed(failure)
            }
            // Authorization can change while a sheet is open. Never retry a write.
            let permissions = (try? await session.mediaProvider.collectionCapabilities(id: nil)) ?? .init()
            guard active, session.isActive, !Task.isCancelled else { return false }
            capabilities = permissions
            return false
        }
    }

    private func requireMutationReview(cancelled: Bool) {
        needsMutationReview = true
        canKeepCurrentServerState = false
        actionOutcome = cancelled ? nil : .uncertain
        errorMessage = String(localized: "The collection change was not confirmed. Refresh and review the server state before making another change.")
    }

    /// Readback never repeats a mutation. The user explicitly accepts the freshly
    /// loaded server snapshot before a duplicate-capable action can be submitted again.
    func keepCurrentServerState() {
        guard canKeepCurrentServerState, !isMutating else { return }
        needsMutationReview = false
        canKeepCurrentServerState = false
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
