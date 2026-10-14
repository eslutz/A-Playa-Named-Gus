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

    @Test func mutationRefreshFailureIsReportedAsSavedWithoutRetry() async {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.collectionPageHandler = { _, _ in throw URLError(.notConnectedToInternet) }
        let store = CollectionStore(session: session(provider))
        var calls = 0
        let result = await store.mutate { calls += 1; return "id" }
        #expect(result)
        #expect(calls == 1)
        #expect(store.statusMessage != nil)
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
        provider.collectionItemHandler = { id in
            active += 1; maximum = max(maximum, active)
            await Task.yield()
            active -= 1
            return MediaItem(id: id, type: .boxSet)
        }
        let store = CollectionStore(session: session(provider))
        await store.load()
        #expect(maximum <= 4)
        #expect(store.collections.count == 12)
        #expect(store.collections.allSatisfy { $0.membersLoaded })
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
