import Foundation
@testable import Gus
import Testing

@MainActor
struct CollectionStoreTests {
    private func session(_ provider: FakeMediaProviderSession, serverID: String = "s", userID: String = "u") -> SessionStore {
        SessionStore(client: JellyfinClientFactory.makeClient(url: URL(string: "https://example.invalid")!), user: StoredUser(id: userID, name: "User", serverID: serverID), server: ServerConnection(id: serverID, name: "Server", url: URL(string: "https://example.invalid")!), mediaProvider: provider)
    }

    @Test func collectionSortPreservesDefaultAndPlacesUnknownDatesLast() {
        let movie = MediaItem(id: "one", name: "Z", premiereDate: Date(timeIntervalSince1970: 100), type: .movie)
        let unknown = MediaItem(id: "two", name: "A", type: .movie)
        #expect(CollectionSort.serverDefault.sorted([movie, unknown]).map(\.id) == ["one", "two"])
        #expect(CollectionSort.title.sorted([movie, unknown]).map(\.id) == ["two", "one"])
        #expect(CollectionSort.releaseDate.sorted([unknown, movie]).map(\.id) == ["one", "two"])
    }

    @Test func paginatedMembershipSupportsMultipleCollectionsAndLibraries() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.collectionPageHandler = { offset, _ in .init(items: offset == 0 ? [MediaItem(id: "a", name: "A", type: .boxSet)] : offset == 1 ? [MediaItem(id: "b", name: "B", type: .boxSet)] : [], totalRecordCount: 2) }
        provider.collectionItemHandler = { MediaItem(id: $0, name: $0, type: .boxSet) }
        provider.collectionMembersHandler = { _, offset, _ in .init(items: offset == 0 ? [MediaItem(id: "movie", name: "Movie", type: .movie)] : offset == 1 ? [MediaItem(id: "series", type: .series)] : [], totalRecordCount: 2) }
        provider.itemsHandler = { query in .init(items: query.parentID == "lib" ? [MediaItem(id: "movie", type: .movie)] : [], totalRecordCount: query.parentID == "lib" ? 1 : 0) }
        let store = CollectionStore(session: session(provider))
        await store.loadLibrary("lib")
        #expect(store.collections.count == 2)
        #expect(store.collections.allSatisfy { $0.members.count == 2 })
        #expect(store.memberships(for: "movie").count == 2)
        #expect(store.relevant(to: "lib").count == 2)
        await store.loadLibrary("other")
        #expect(store.relevant(to: "other").isEmpty)
    }

    @Test func libraryMembershipSurvivesInFlightAndFailedRefresh() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.collectionPageHandler = { _, _ in .init(items: [.init(id: "collection", type: .boxSet)], totalRecordCount: 1) }
        provider.collectionItemHandler = { .init(id: $0, type: .boxSet) }
        provider.collectionMembersHandler = { _, _, _ in .init(items: [.init(id: "movie", type: .movie)], totalRecordCount: 1) }
        provider.itemsHandler = { _ in .init(items: [.init(id: "movie", type: .movie)], totalRecordCount: 1) }
        let store = CollectionStore(session: session(provider))
        await store.loadLibrary("library")
        #expect(store.relevant(to: "library").map(\.id) == ["collection"])
        var continuation: CheckedContinuation<MediaItemPage, Error>?
        provider.collectionPageHandler = { _, _ in try await withCheckedThrowingContinuation { continuation = $0 } }
        let refresh = Task { await store.load(force: true) }
        while continuation == nil {
            await Task.yield()
        }
        #expect(store.relevant(to: "library").map(\.id) == ["collection"])
        continuation?.resume(throwing: GusError.offline)
        await refresh.value
        #expect(store.relevant(to: "library").map(\.id) == ["collection"])
        #expect(store.errorMessage != nil)
    }

    @Test func discoveryUsesListedHeadersAndOnlyFetchesEditPermissionsUponOpening() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.collectionPageHandler = { _, _ in .init(items: [.init(id: "box", name: "Films", type: .boxSet)], totalRecordCount: 1) }
        var detailReads = 0
        provider.collectionItemHandler = { _ in detailReads += 1; throw GusError.offline }
        var permissionIDs: [String?] = []
        provider.collectionCapabilitiesHandler = { id in permissionIDs.append(id); return .init(delete: id != nil) }
        provider.collectionMembersHandler = { _, _, _ in .init(items: [.init(id: "movie", type: .movie)], totalRecordCount: 1) }
        let store = CollectionStore(session: session(provider))
        await store.load()
        #expect(store.relevant(to: nil).map(\.id) == ["box"])
        #expect(store.errorMessage == nil)
        #expect(detailReads == 0)
        #expect(permissionIDs == [nil])
        await store.loadDetail(id: "box")
        #expect(store.permissions(for: "box").delete)
        #expect(permissionIDs == [nil, "box"])
    }

    @Test func discoverySurvivesPermissionLookupFailure() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.collectionCapabilitiesHandler = { _ in throw GusError.server("Permissions unavailable") }
        provider.collectionPageHandler = { _, _ in .init(items: [MediaItem(id: "a", type: .boxSet)], totalRecordCount: 1) }
        provider.collectionItemHandler = { MediaItem(id: $0, type: .boxSet) }
        provider.collectionMembersHandler = { _, _, _ in .init(items: [], totalRecordCount: 0) }
        let store = CollectionStore(session: session(provider))
        await store.load()
        #expect(store.state == .loaded)
        #expect(store.collections.count == 1)
        #expect(store.capabilities.create == false)
    }

    @Test func failedMutationDoesNotCreateLocalCollectionOrRetry() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let store = CollectionStore(session: session(provider))
        var calls = 0
        let result = await store.mutate { calls += 1; throw URLError(.timedOut) }
        #expect(!result)
        #expect(calls == 1)
        #expect(store.collections.isEmpty)
        #expect(store.errorMessage != nil)
    }

    @Test func mixedFormatWritesConfirmOnlyTheRequestedMemberships() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let store = CollectionStore(session: session(provider))
        let id = "c0000000000000000000000000000001"
        let returnedID = "C0000000-0000-0000-0000-000000000001"
        let book = MediaItem(id: "book", type: .book)
        let audio = MediaItem(id: "audio", type: .audioBook)
        var members = [MediaItem]()
        var headers = [MediaItem]()
        provider.collectionPageHandler = { _, _ in .init(items: headers, totalRecordCount: headers.count) }
        provider.collectionMembersHandler = { _, _, _ in .init(items: members, totalRecordCount: members.count) }
        #expect(await store.mutate(verifying: .contains([])) {
            headers = [.init(id: id, type: .boxSet)]
            return returnedID
        })
        #expect(store.collection(id)?.members.isEmpty == true)
        #expect(await store.mutate(collectionID: id, verifying: .contains(["book", "audio"])) {
            members = [book, audio, MediaItem(id: "another-user-added", type: .movie)]
            return id
        })
        #expect(store.actionOutcome == .confirmed)
        #expect(store.memberships(for: "audio").map(\.id) == [id])
        #expect(await store.mutate(collectionID: id, verifying: .excludes(["audio"])) {
            members.removeAll { $0.id == "audio" }
            return id
        })
        #expect(store.collection(id)?.members.map(\.id) == ["book", "another-user-added"])
        provider.itemHandler = { _ in throw GusError.notFound }
        #expect(await store.mutate(collectionID: id, verifying: .deleted) {
            headers = []
            return id
        })
        #expect(store.collection(id) == nil)
        #expect(store.actionOutcome == .confirmed)
    }

    @Test func acknowledgedPartialSeedRequiresReviewWithoutRepeatingTheWrite() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let store = CollectionStore(session: session(provider))
        var calls = 0
        provider.collectionPageHandler = { _, _ in .init(items: [.init(id: "box", type: .boxSet), .init(id: "other", type: .boxSet)], totalRecordCount: 2) }
        provider.collectionMembersHandler = { id, _, _ in
            if id == "other" {
                throw GusError.offline
            }
            return .init(items: [.init(id: "book", type: .book)], totalRecordCount: 1)
        }
        #expect(await store.mutate(verifying: .contains(["book", "audio"])) { calls += 1; return "box" } == false)
        #expect(store.actionOutcome == .uncertain)
        #expect(!store.hasCompleteMembershipCatalog)
        #expect(store.canKeepCurrentServerState)
        #expect(store.reviewedCollection?.members.map(\.id) == ["book"])
        #expect(await store.mutate { calls += 1; return "duplicate" } == false)
        store.keepCurrentServerState()
        #expect(await store.mutate(collectionID: "box", verifying: .contains(["book"])) { calls += 1; return "box" })
        #expect(store.actionOutcome == .confirmed)
        #expect(calls == 2)
        #expect(store.reviewCollectionID == nil)
    }

    @Test func absentFromVisibleCatalogDoesNotProveDeletion() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.collectionPageHandler = { _, _ in .init(items: [], totalRecordCount: 0) }
        var itemReads = [String]()
        provider.itemHandler = { id in
            itemReads.append(id)
            return MediaItem(id: id, type: .boxSet)
        }
        let store = CollectionStore(session: session(provider))
        #expect(await store.mutate(collectionID: "hidden", verifying: .deleted) { "hidden" } == false)
        #expect(itemReads == ["hidden"])
        #expect(store.actionOutcome == .uncertain)
        #expect(store.needsMutationReview)
    }

    @Test func staleOrOverlappingMembershipPagesCannotConfirmRemoval() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let store = CollectionStore(session: session(provider))
        provider.collectionPageHandler = { _, _ in .init(items: [.init(id: "box", type: .boxSet)], totalRecordCount: 1) }
        provider.collectionMembersHandler = { _, _, _ in .init(items: [], totalRecordCount: 0) }
        await store.load()
        #expect(store.hasCompleteMembershipCatalog)
        provider.collectionMembersHandler = { _, offset, _ in
            let ids = offset == 0 ? ["a", "b"] : ["b", "c"]
            return .init(items: ids.map { .init(id: $0, type: .book) }, totalRecordCount: 4)
        }
        #expect(await store.mutate(collectionID: "box", verifying: .excludes(["audio"])) { "box" } == false)
        #expect(!store.hasCompleteMembershipCatalog)
        #expect(!store.canKeepCurrentServerState)
        #expect(store.memberErrors["box"] != nil)
        provider.collectionMembersHandler = { _, _, _ in .init(items: [.init(id: "audio", type: .audioBook)], totalRecordCount: 1) }
        await store.load(force: true)
        #expect(store.canKeepCurrentServerState)
        #expect(store.reviewedCollection?.members.map(\.id) == ["audio"])
        store.keepCurrentServerState()
        #expect(await store.mutate(collectionID: "box", verifying: .deleted) { "box" } == false)
        #expect(store.actionOutcome == .uncertain)
    }

    @Test("an uncertain collection create requires fresh server review before another write", arguments: [GusError.timeout, .offline, .network("Lost response")])
    func uncertainCreateRequiresReview(failure: GusError) async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.collectionCapabilitiesHandler = { _ in .init(create: true) }
        var writes = 0
        var remote: [MediaItem] = []
        provider.createCollectionHandler = { name, _ in
            writes += 1
            remote = [MediaItem(id: "created", name: name, type: .boxSet)]
            throw failure
        }
        provider.collectionPageHandler = { _, _ in .init(items: remote, totalRecordCount: remote.count) }
        provider.collectionItemHandler = { id in remote.first { $0.id == id } ?? MediaItem(id: id, type: .boxSet) }
        let store = CollectionStore(session: session(provider))
        #expect(await store.mutate { try await provider.createCollection(name: "Favorites", itemIDs: []) } == false)
        #expect(store.actionOutcome == .uncertain)
        #expect(store.needsMutationReview)
        #expect(!store.canSubmitMutations)
        #expect(await store.mutate { try await provider.createCollection(name: "Favorites", itemIDs: []) } == false)
        #expect(writes == 1)
        store.keepCurrentServerState()
        #expect(store.needsMutationReview)

        await store.load(force: true)
        #expect(store.collections.map(\.id) == ["created"])
        #expect(store.canKeepCurrentServerState)
        #expect(!store.canSubmitMutations)
        store.keepCurrentServerState()
        #expect(store.canSubmitMutations)
        #expect(store.actionOutcome == nil)
        #expect(writes == 1)
    }

    @Test func deniedCollectionMutationIsFailedWithoutReviewOrSessionExpiry() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let active = session(provider)
        let store = CollectionStore(session: active)
        #expect(await store.mutate { throw GusError.forbidden } == false)
        #expect(store.actionOutcome == .failed(.forbidden))
        #expect(!store.needsMutationReview)
        #expect(store.canSubmitMutations)
        #expect(active.isActive)
    }

    @Test("leaving collection content does not discard an in-flight write outcome", arguments: [true, false])
    func hiddenCollectionRetainsMutationOutcome(accepted: Bool) async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let store = CollectionStore(session: session(provider))
        var continuation: CheckedContinuation<String?, Error>?
        var writes = 0
        let task = Task {
            await store.mutate {
                writes += 1
                return try await withCheckedThrowingContinuation { continuation = $0 }
            }
        }
        while continuation == nil {
            await Task.yield()
        }
        store.cancelForegroundLoads()
        if accepted {
            continuation?.resume(returning: "created")
        } else {
            continuation?.resume(throwing: GusError.timeout)
        }
        #expect(await task.value == accepted)
        #expect(store.actionOutcome == (accepted ? .accepted : .uncertain))
        if !accepted {
            #expect(store.needsMutationReview)
            #expect(!store.canSubmitMutations)
            #expect(await store.mutate { writes += 1; return "duplicate" } == false)
        }
        #expect(writes == 1)
    }

    @Test func retiredSessionCannotPublishLateCollectionWriteOutcome() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let active = session(provider)
        let store = CollectionStore(session: active)
        var continuation: CheckedContinuation<String?, Never>?
        let task = Task { await store.mutate { await withCheckedContinuation { continuation = $0 } } }
        while continuation == nil {
            await Task.yield()
        }
        active.invalidate()
        continuation?.resume(returning: "created")
        #expect(await task.value == false)
        #expect(store.actionOutcome == nil)
        #expect(!store.canSubmitMutations)
    }

    @Test func mutationRefreshFailureIsReportedAsSavedWithoutRetry() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.collectionPageHandler = { _, _ in throw URLError(.notConnectedToInternet) }
        let store = CollectionStore(session: session(provider))
        var calls = 0
        let result = await store.mutate { calls += 1; return "id" }
        #expect(result)
        #expect(calls == 1)
        #expect(store.statusMessage != nil)
        #expect(store.actionOutcome == .accepted)
        #expect(store.needsMutationReview)
        provider.collectionPageHandler = { _, _ in .init(items: [], totalRecordCount: 0) }
        await store.load(force: true)
        #expect(store.statusMessage == nil)
    }

    @Test func invalidationRejectsLateCollectionResponse() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var continuation: CheckedContinuation<MediaItemPage, Never>?
        provider.collectionPageHandler = { _, _ in await withCheckedContinuation { continuation = $0 } }
        let store = CollectionStore(session: session(provider))
        let task = Task { await store.load() }
        while continuation == nil {
            await Task.yield()
        }
        store.invalidate()
        continuation?.resume(returning: .init(items: [MediaItem(id: "late", type: .boxSet)], totalRecordCount: 1))
        await task.value
        #expect(store.collections.isEmpty)
    }

    @Test func collectionReferencesAreAccountAndServerScoped() {
        #expect(MediaCollectionRef(id: "same", scope: .init(serverID: "a", userID: "u")) != MediaCollectionRef(id: "same", scope: .init(serverID: "b", userID: "u")))
        #expect(MediaCollectionRef(id: "same", scope: .init(serverID: "a", userID: "u")) != MediaCollectionRef(id: "same", scope: .init(serverID: "a", userID: "v")))
    }

    @Test func deletedCollectionIsRemovedFromSnapshot() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.collectionPageHandler = { _, _ in .init(items: [MediaItem(id: "deleted", type: .boxSet)], totalRecordCount: 1) }
        provider.collectionItemHandler = { MediaItem(id: $0, type: .boxSet) }
        let store = CollectionStore(session: session(provider))
        await store.load()
        #expect(store.collection("deleted") != nil)
        provider.collectionItemHandler = { _ in throw GusError.notFound }
        await store.loadDetail(id: "deleted", force: true)
        #expect(store.collection("deleted") == nil)
    }

    @Test func membershipLoadsHaveAtMostFourConcurrentRequests() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.collectionPageHandler = { _, _ in .init(items: (0 ..< 12).map { MediaItem(id: String($0), type: .boxSet) }, totalRecordCount: 12) }
        var active = 0, maximum = 0
        provider.collectionMembersHandler = { _, _, _ in
            active += 1; maximum = max(maximum, active)
            await Task.yield()
            active -= 1
            return .init(items: [], totalRecordCount: 0)
        }
        let store = CollectionStore(session: session(provider))
        await store.load()
        #expect((1 ... 4).contains(maximum))
        #expect(store.collections.count == 12)
        #expect(store.collections.allSatisfy { $0.membersLoaded })
    }

    @Test func returningAfterInterruptedMembershipLoadRetriesFromTheServer() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.collectionPageHandler = { _, _ in .init(items: [.init(id: "box", type: .boxSet)], totalRecordCount: 1) }
        var suspended: CheckedContinuation<MediaItemPage, Never>?
        var reads = 0
        provider.collectionMembersHandler = { _, _, _ in
            reads += 1
            if reads == 1 {
                return await withCheckedContinuation { suspended = $0 }
            }
            return .init(items: [.init(id: "movie", type: .movie)], totalRecordCount: 1)
        }
        let store = CollectionStore(session: session(provider))
        let first = Task { await store.load() }
        while suspended == nil {
            await Task.yield()
        }
        store.cancelForegroundLoads()
        #expect(store.collection("box") != nil)
        #expect(store.state == .idle)
        suspended?.resume(returning: .init(items: [], totalRecordCount: 0))
        await first.value
        await store.load()
        #expect(reads == 2)
        #expect(store.relevant(to: nil).map(\.id) == ["box"])
        #expect(store.errorMessage == nil)
    }

    @Test func inactiveStoreRejectsChainedDetailAndLibraryLoads() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.collectionItemHandler = { MediaItem(id: $0, type: .boxSet) }
        var libraryRequests = 0
        provider.itemsHandler = { _ in libraryRequests += 1; return .init(items: [], totalRecordCount: 0) }
        let store = CollectionStore(session: session(provider))
        store.invalidate()
        await store.loadDetail(id: "late")
        await store.loadLibrary("lib")
        #expect(store.collections.isEmpty)
        #expect(libraryRequests == 0)
    }

    @Test func forcedRefreshRebuildsLibraryRelevance() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.collectionPageHandler = { _, _ in .init(items: [MediaItem(id: "a", type: .boxSet)], totalRecordCount: 1) }
        provider.collectionItemHandler = { MediaItem(id: $0, type: .boxSet) }
        provider.collectionMembersHandler = { _, _, _ in .init(items: [MediaItem(id: "movie", type: .movie)], totalRecordCount: 1) }
        var inLibrary = false
        provider.itemsHandler = { _ in .init(items: inLibrary ? [MediaItem(id: "movie", type: .movie)] : [], totalRecordCount: inLibrary ? 1 : 0) }
        let store = CollectionStore(session: session(provider))
        await store.loadLibrary("lib")
        #expect(store.relevant(to: "lib").isEmpty)
        inLibrary = true
        await store.load(force: true)
        await store.loadLibrary("lib")
        #expect(store.relevant(to: "lib").count == 1)
    }

    @Test func latePermissionsCannotReviveInvalidatedStore() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var continuation: CheckedContinuation<CollectionCapabilities, Never>?
        provider.collectionCapabilitiesHandler = { _ in await withCheckedContinuation { continuation = $0 } }
        let store = CollectionStore(session: session(provider))
        let task = Task { await store.load() }
        while continuation == nil {
            await Task.yield()
        }
        store.invalidate()
        continuation?.resume(returning: .init(create: true))
        await task.value
        #expect(!store.capabilities.create)
    }

    @Test func sameAccountSessionReplacementGetsFreshCollectionState() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let first = session(provider), second = session(provider)
        let root = RootNavigationState()
        let old = root.collectionStore(session: first)
        #expect(root.collectionStore(session: first) === old)
        first.invalidateCollections()
        let current = root.collectionStore(session: second)
        #expect(current !== old)
        provider.collectionItemHandler = { MediaItem(id: $0, type: .boxSet) }
        await old.loadDetail(id: "late")
        #expect(old.collections.isEmpty)
    }

    @Test func canceledTaskDoesNotDispatchCollectionWrite() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let store = CollectionStore(session: session(provider))
        var calls = 0
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await store.mutate { calls += 1; return "id" }
        }
        let result = await task.value
        #expect(!result)
        #expect(calls == 0)
    }

    @Test func canceledWriteOutcomeDoesNotPublishSuccess() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let store = CollectionStore(session: session(provider))
        var continuation: CheckedContinuation<String?, Never>?
        let task = Task { await store.mutate { await withCheckedContinuation { continuation = $0 } } }
        while continuation == nil {
            await Task.yield()
        }
        task.cancel()
        continuation?.resume(returning: "id")
        let result = await task.value
        #expect(!result)
        #expect(store.revision == 0)
    }

    @Test func permissionsUseTheCurrentProviderWitness() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var calls = 0
        provider.collectionCapabilitiesHandler = { _ in calls += 1; return .init(create: true, addMembers: true) }
        let store = CollectionStore(session: session(provider))
        await store.loadPermissions()
        #expect(store.capabilities.create && store.capabilities.addMembers)
        #expect(calls == 1)
    }

    @Test func concurrentForcedRefreshesCoalesceIntoOneFollowupRead() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var continuation: CheckedContinuation<MediaItemPage, Never>?
        var calls = 0
        provider.collectionPageHandler = { _, _ in
            calls += 1
            if calls == 1 {
                return await withCheckedContinuation { continuation = $0 }
            }
            return .init(items: [], totalRecordCount: 0)
        }
        let store = CollectionStore(session: session(provider))
        let first = Task { await store.load() }
        while continuation == nil {
            await Task.yield()
        }
        let second = Task { await store.load(force: true) }
        let third = Task { await store.load(force: true) }
        await Task.yield()
        continuation?.resume(returning: .init(items: [], totalRecordCount: 0))
        await first.value; await second.value; await third.value
        #expect(calls == 2)
    }

    @Test func editPermissionDoesNotSilentlyDropAnArtworkDraft() {
        #expect(!CollectionCapabilities().permitsEdit(artworkIncluded: false))
        #expect(CollectionCapabilities(editMetadata: true).permitsEdit(artworkIncluded: false))
        #expect(!CollectionCapabilities(editMetadata: true).permitsEdit(artworkIncluded: true))
        #expect(CollectionCapabilities(editArtwork: true).permitsEdit(artworkIncluded: true))
        #expect(!CollectionCapabilities(editArtwork: true).permitsEdit(artworkIncluded: false))
    }

    @Test func partialMetadataSuccessRefreshesBeforeReportingArtworkFailure() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        var title = "Old"
        var metadataWrites = 0, artworkWrites = 0
        provider.collectionCapabilitiesHandler = { _ in .init(editMetadata: true, editArtwork: true) }
        provider.collectionPageHandler = { _, _ in .init(items: [MediaItem(id: "a", name: title, type: .boxSet)], totalRecordCount: 1) }
        provider.collectionItemHandler = { MediaItem(id: $0, name: title, type: .boxSet) }
        provider.updateCollectionHandler = { _, name, _ in title = name; metadataWrites += 1 }
        provider.setCollectionArtworkHandler = { _, _ in artworkWrites += 1; throw GusError.server("Artwork denied") }
        let store = CollectionStore(session: session(provider))
        await store.load()
        let saved = await store.saveEdits(id: "a", name: "New", overview: "Description", artwork: Data([1]))
        #expect(!saved)
        #expect(metadataWrites == 1 && artworkWrites == 1)
        #expect(store.collection("a")?.item.name == "New")
        #expect(store.statusMessage != nil)
        #expect(store.errorMessage == "Artwork denied")
        #expect(store.actionOutcome == .uncertain)
        #expect(store.needsMutationReview)
    }

    @Test func teardownBetweenEditPhasesDoesNotDispatchArtwork() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.collectionCapabilitiesHandler = { _ in .init(editMetadata: true, editArtwork: true) }
        let store = CollectionStore(session: session(provider))
        await store.load()
        var artworkWrites = 0
        provider.updateCollectionHandler = { [weak store] _, _, _ in store?.invalidate() }
        provider.setCollectionArtworkHandler = { _, _ in artworkWrites += 1 }
        let saved = await store.saveEdits(id: "a", name: "New", overview: "", artwork: Data([1]))
        #expect(!saved)
        #expect(artworkWrites == 0)
    }
}
