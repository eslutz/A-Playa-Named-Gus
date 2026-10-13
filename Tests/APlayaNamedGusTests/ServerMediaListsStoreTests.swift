import Foundation
@testable import Gus
import Testing

@MainActor
struct ServerMediaListsStoreTests {
    private let scope = AccountScope(serverID: "s", userID: "u")

    private func session(_ provider: FakeMediaProviderSession, userID: String = "u") -> SessionStore {
        SessionStore(
            client: JellyfinClientFactory.makeClient(url: URL(string: "https://example.invalid")!),
            user: StoredUser(id: userID, name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: URL(string: "https://example.invalid")!),
            mediaProvider: provider
        )
    }

    @Test func restartRetainsNativeOrderAndAudioWithoutCloudMembership() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let id = UUID(), first = UUID(), second = UUID()
        let list = ServerMediaList(id: id, name: "Mixed", kind: .playlist, entries: [
            ServerMediaListEntry(id: first, item: MediaItem(id: "video", type: .movie)),
            ServerMediaListEntry(id: second, item: MediaItem(id: "audio", type: .audio)),
        ], canEdit: true, entriesLoaded: true)
        provider.mediaListsHandler = { kind in kind == .playlist ? [list] : [] }
        provider.mediaListHandler = { _, _ in list }
        let store = ServerMediaListsStore(directory: directory)
        await store.refresh(session: session(provider))
        let restored = ServerMediaListsStore(directory: directory)
        restored.load(scope: scope)
        let supplemental = VideoPlaylistsStore(directory: directory.appendingPathComponent("cloud"), syncEnabled: false)
        supplemental.registerServerPlaylist(id: id, scope: scope)
        supplemental.setCursor(id: id, entryID: second, positionTicks: 123, finished: false, scope: scope)
        let projection = try #require(restored.videoPlaylist(id: id, scope: scope, supplemental: supplemental))
        #expect(projection.entries.map(\.id) == [first, second])
        #expect(projection.entries.map(\.reference.item.id) == ["video", "audio"])
        #expect(projection.cursor?.positionTicks == 123)
        #expect(supplemental.playlists(scope: scope).isEmpty)
        #expect(supplemental.envelope.records.values.filter { $0.kind == .entry }.isEmpty)
        #expect(restored.lists(kind: .playlist, scope: AccountScope(serverID: "s", userID: "other")).isEmpty)
    }

    @Test func ambiguousAddIsDurableAndNeverAutomaticallyRepeated() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let id = UUID()
        let list = ServerMediaList(id: id, name: "A", kind: .playlist, entries: [], canEdit: true, entriesLoaded: true)
        provider.mediaListsHandler = { kind in kind == .playlist ? [list] : [] }
        provider.mediaListHandler = { _, _ in list }
        var additions = 0
        provider.addToMediaListHandler = { _, _, _ in additions += 1; throw URLError(.networkConnectionLost) }
        let store = ServerMediaListsStore(directory: directory)
        await store.refresh(session: session(provider))
        #expect(await store.add(item: MediaItem(id: "movie", type: .movie), to: id, kind: .playlist, session: session(provider)))
        let restored = ServerMediaListsStore(directory: directory)
        await restored.refresh(session: session(provider))
        #expect(additions == 1)
        #expect(restored.pendingEdits(scope: scope).first?.needsReview == true)
        #expect(restored.list(id: id, kind: .playlist, scope: scope)?.entries.map(\.item.id) == ["movie"])
    }

    @Test func ambiguousCreateCannotDuplicateAfterRestart() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.mediaListsHandler = { _ in [] }
        var creations = 0
        provider.createMediaListHandler = { _, _, _ in creations += 1; throw URLError(.timedOut) }
        let store = ServerMediaListsStore(directory: directory)
        #expect(await store.create(name: "A", kind: .playlist, session: session(provider)) != nil)
        let restored = ServerMediaListsStore(directory: directory)
        await restored.refresh(session: session(provider))
        #expect(creations == 1)
        #expect(restored.pendingEdits(scope: scope).first?.needsReview == true)
    }

    @Test func offlineRemovalReplaysAgainstFreshOccurrenceList() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let id = UUID(), removed = UUID(), survivor = UUID()
        var list = ServerMediaList(id: id, name: "A", kind: .playlist, entries: [
            ServerMediaListEntry(id: removed, item: MediaItem(id: "same", type: .movie)),
            ServerMediaListEntry(id: survivor, item: MediaItem(id: "same", type: .movie)),
        ], canEdit: true, entriesLoaded: true)
        provider.mediaListsHandler = { kind in kind == .playlist ? [list] : [] }
        provider.mediaListHandler = { _, _ in list }
        let store = ServerMediaListsStore(directory: directory)
        await store.refresh(session: session(provider))
        provider.mediaListHandler = { _, _ in throw URLError(.notConnectedToInternet) }
        #expect(await store.remove(entryID: removed, from: id, kind: .playlist, session: session(provider)))
        #expect(store.list(id: id, kind: .playlist, scope: scope)?.entries.map(\.id) == [survivor])
        list.entries.removeFirst() // Another client already removed this occurrence.
        provider.mediaListHandler = { _, _ in list }
        var removals = 0
        provider.removeFromMediaListHandler = { _, _, _ in removals += 1 }
        await store.refresh(session: session(provider))
        #expect(removals == 0)
        #expect(store.pendingEdits(scope: scope).isEmpty)
        #expect(store.list(id: id, kind: .playlist, scope: scope)?.entries.map(\.id) == [survivor])
    }

    @Test func lateReadCannotPublishIntoAnotherAccount() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let id = UUID()
        let remote = ServerMediaList(id: id, name: "Private", kind: .playlist, entries: [], canEdit: true, entriesLoaded: true)
        var continuation: CheckedContinuation<[ServerMediaList], Never>?
        provider.mediaListsHandler = { kind in
            if kind == .collection {
                return []
            }
            return await withCheckedContinuation { continuation = $0 }
        }
        let store = ServerMediaListsStore(directory: directory)
        let task = Task { await store.refresh(session: session(provider)) }
        while continuation == nil {
            await Task.yield()
        }
        let other = AccountScope(serverID: "s", userID: "other")
        store.load(scope: other)
        continuation?.resume(returning: [remote])
        await task.value
        #expect(store.lists(kind: .playlist, scope: other).isEmpty)
        #expect(store.lists(kind: .playlist, scope: scope).isEmpty)
    }

    @Test func removalProjectsSuccessorCursorWithoutCloudMembership() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let id = UUID(), first = UUID(), current = UUID(), successor = UUID()
        let list = ServerMediaList(id: id, name: "A", kind: .playlist, entries: [first, current, successor].map {
            ServerMediaListEntry(id: $0, item: MediaItem(id: "movie", type: .movie))
        }, canEdit: true, entriesLoaded: true)
        provider.mediaListsHandler = { kind in kind == .playlist ? [list] : [] }
        provider.mediaListHandler = { _, _ in list }
        let store = ServerMediaListsStore(directory: directory)
        await store.refresh(session: session(provider))
        let supplemental = VideoPlaylistsStore(directory: directory.appendingPathComponent("cloud"), syncEnabled: false)
        supplemental.registerServerPlaylist(id: id, scope: scope)
        supplemental.setCursor(id: id, entryID: current, positionTicks: 100, finished: false, scope: scope)
        provider.mediaListHandler = { _, _ in throw URLError(.notConnectedToInternet) }
        #expect(await store.remove(entryID: current, from: id, kind: .playlist, session: session(provider)))
        #expect(store.videoPlaylist(id: id, scope: scope, supplemental: supplemental)?.cursor == PlaylistCursor(entryID: successor, positionTicks: 0, finished: false))
        #expect(supplemental.serverPlaylistState(id: id, scope: scope).cursor?.entryID == current)
    }

    @Test func importPreservesUniqueEntryCursorAndOriginal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let nativeID = UUID(), first = UUID(), second = UUID()
        var created = false
        let native = ServerMediaList(id: nativeID, name: "Legacy", kind: .playlist, entries: [
            ServerMediaListEntry(id: first, item: MediaItem(id: "first", type: .movie)),
            ServerMediaListEntry(id: second, item: MediaItem(id: "second", type: .movie)),
        ], canEdit: true, entriesLoaded: true)
        provider.mediaListsHandler = { kind in created && kind == .playlist ? [native] : [] }
        provider.mediaListHandler = { _, _ in native }
        var createCalls = 0
        provider.createMediaListHandler = { name, kind, itemIDs in
            #expect(name == "Legacy")
            #expect(kind == .playlist)
            #expect(itemIDs == ["first", "second"])
            createCalls += 1; created = true
            return nativeID
        }
        let supplemental = VideoPlaylistsStore(directory: directory.appendingPathComponent("cloud"), syncEnabled: false)
        let oldID = try #require(supplemental.create(name: "Legacy", scope: scope))
        for itemID in ["first", "second"] {
            #expect(supplemental.add(item: MediaItem(id: itemID, type: .movie), to: oldID, scope: scope))
        }
        let oldEntries = try #require(supplemental.playlist(id: oldID, scope: scope)).entries
        supplemental.setCursor(id: oldID, entryID: oldEntries[1].id, positionTicks: 777, finished: false, scope: scope)
        supplemental.setQueued(id: oldID, queued: true, scope: scope)
        let original = try #require(supplemental.playlist(id: oldID, scope: scope))
        let store = ServerMediaListsStore(directory: directory)
        #expect(await store.importLegacy(original, session: session(provider), supplemental: supplemental) == nativeID)
        #expect(store.legacyImportID(for: oldID, scope: scope) == nativeID)
        #expect(supplemental.playlist(id: oldID, scope: scope) == original)
        let imported = try #require(store.videoPlaylist(id: nativeID, scope: scope, supplemental: supplemental))
        #expect(imported.cursor == PlaylistCursor(entryID: second, positionTicks: 777, finished: false))
        #expect(imported.queued)
        #expect(imported.activityAt == original.activityAt)
        #expect(await store.importLegacy(original, session: session(provider), supplemental: supplemental) == nativeID)
        #expect(createCalls == 1)
    }

    @Test func offlineCreateAliasesNativeIdentityAndCursorOnReconnect() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let nativeID = UUID(), first = UUID(), second = UUID()
        var online = false, created = false
        let native = ServerMediaList(id: nativeID, name: "Offline", kind: .playlist, entries: [
            ServerMediaListEntry(id: first, item: MediaItem(id: "first", type: .movie)),
            ServerMediaListEntry(id: second, item: MediaItem(id: "second", type: .movie)),
        ], canEdit: true, entriesLoaded: true)
        provider.mediaListsHandler = { kind in
            guard online else { throw URLError(.notConnectedToInternet) }
            return created && kind == .playlist ? [native] : []
        }
        provider.mediaListHandler = { _, _ in native }
        provider.createMediaListHandler = { _, _, _ in created = true; return nativeID }
        let store = ServerMediaListsStore(directory: directory)
        let localID = try #require(await store.create(name: "Offline", kind: .playlist, session: session(provider), itemIDs: ["first", "second"]))
        let draft = try #require(store.list(id: localID, kind: .playlist, scope: scope))
        let oldEntry = draft.entries[1].id
        let supplemental = VideoPlaylistsStore(directory: directory.appendingPathComponent("cloud"), syncEnabled: false)
        supplemental.registerServerPlaylist(id: localID, scope: scope)
        supplemental.setCursor(id: localID, entryID: oldEntry, positionTicks: 321, finished: false, scope: scope)
        online = true
        await store.refresh(session: session(provider))
        #expect(store.resolvedID(localID, scope: scope) == nativeID)
        #expect(store.resolvedEntryID(oldEntry, inList: localID, scope: scope) == second)
        supplemental.registerServerPlaylist(id: nativeID, scope: scope)
        #expect(store.videoPlaylist(id: nativeID, scope: scope, supplemental: supplemental)?.cursor == PlaylistCursor(entryID: second, positionTicks: 321, finished: false))
        let before = supplemental.revision
        _ = store.videoPlaylist(id: nativeID, scope: scope, supplemental: supplemental)
        #expect(supplemental.revision == before)
    }

    @Test func concurrentUnrelatedAddAndReorderRetainConfirmedOccurrenceAlias() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let listID = UUID(), first = UUID(), second = UUID(), added = UUID(), external = UUID()
        let a = ServerMediaListEntry(id: first, item: MediaItem(id: "a", type: .movie))
        let b = ServerMediaListEntry(id: second, item: MediaItem(id: "b", type: .movie))
        var remote = ServerMediaList(id: listID, name: "A", kind: .playlist, entries: [a, b], canEdit: true, entriesLoaded: true)
        var online = true
        provider.mediaListsHandler = { kind in kind == .playlist ? [remote] : [] }
        provider.mediaListHandler = { _, _ in
            guard online else { throw URLError(.notConnectedToInternet) }
            return remote
        }
        provider.addToMediaListHandler = { _, _, _ in
            remote.entries = [
                b,
                ServerMediaListEntry(id: added, item: MediaItem(id: "c", type: .movie)),
                a,
                ServerMediaListEntry(id: external, item: MediaItem(id: "other", type: .movie)),
            ]
        }
        let store = ServerMediaListsStore(directory: directory)
        await store.refresh(session: session(provider))
        online = false
        #expect(await store.add(item: MediaItem(id: "c", type: .movie), to: listID, kind: .playlist, session: session(provider)))
        let provisional = try #require(store.list(id: listID, kind: .playlist, scope: scope)?.entries.last?.id)
        let supplemental = VideoPlaylistsStore(directory: directory.appendingPathComponent("cloud"), syncEnabled: false)
        supplemental.registerServerPlaylist(id: listID, scope: scope)
        supplemental.setCursor(id: listID, entryID: provisional, positionTicks: 999, finished: false, scope: scope)
        online = true
        await store.refresh(session: session(provider))
        #expect(store.resolvedEntryID(provisional, inList: listID, scope: scope) == added)
        #expect(store.videoPlaylist(id: listID, scope: scope, supplemental: supplemental)?.cursor == PlaylistCursor(entryID: added, positionTicks: 999, finished: false))
        #expect(store.list(id: listID, kind: .playlist, scope: scope)?.entries.map(\.id) == [second, added, first, external])
    }

    @Test func ambiguousConcurrentIdenticalAddPreservesUnmatchedCursorAndTicks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let listID = UUID(), added = UUID(), external = UUID()
        var remote = ServerMediaList(id: listID, name: "A", kind: .playlist, entries: [], canEdit: true, entriesLoaded: true)
        var online = true
        provider.mediaListsHandler = { kind in kind == .playlist ? [remote] : [] }
        provider.mediaListHandler = { _, _ in
            guard online else { throw URLError(.notConnectedToInternet) }
            return remote
        }
        provider.addToMediaListHandler = { _, _, _ in
            remote.entries = [added, external].map { ServerMediaListEntry(id: $0, item: MediaItem(id: "same", type: .movie)) }
        }
        let store = ServerMediaListsStore(directory: directory)
        await store.refresh(session: session(provider))
        online = false
        #expect(await store.add(item: MediaItem(id: "same", type: .movie), to: listID, kind: .playlist, session: session(provider)))
        let provisional = try #require(store.list(id: listID, kind: .playlist, scope: scope)?.entries.first?.id)
        let supplemental = VideoPlaylistsStore(directory: directory.appendingPathComponent("cloud"), syncEnabled: false)
        supplemental.registerServerPlaylist(id: listID, scope: scope)
        supplemental.setCursor(id: listID, entryID: provisional, positionTicks: 456, finished: false, scope: scope)
        online = true
        await store.refresh(session: session(provider))
        #expect(store.resolvedEntryID(provisional, inList: listID, scope: scope) == provisional)
        let projection = try #require(store.videoPlaylist(id: listID, scope: scope, supplemental: supplemental))
        #expect(projection.cursor == PlaylistCursor(entryID: provisional, positionTicks: 456, finished: false))
        #expect(projection.entries.map(\.id) == [added, external])
        let restored = ServerMediaListsStore(directory: directory)
        restored.load(scope: scope)
        #expect(restored.videoPlaylist(id: listID, scope: scope, supplemental: supplemental)?.cursor == projection.cursor)
    }

    @Test func offlineAddFollowedByRemoveUsesPublishedOccurrence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let listID = UUID(), existing = UUID(), published = UUID()
        var remote = ServerMediaList(id: listID, name: "A", kind: .playlist, entries: [
            ServerMediaListEntry(id: existing, item: MediaItem(id: "existing", type: .movie)),
        ], canEdit: true, entriesLoaded: true)
        var online = true
        provider.mediaListsHandler = { kind in kind == .playlist ? [remote] : [] }
        provider.mediaListHandler = { _, _ in
            guard online else { throw URLError(.notConnectedToInternet) }
            return remote
        }
        provider.addToMediaListHandler = { _, _, _ in
            remote.entries.append(ServerMediaListEntry(id: published, item: MediaItem(id: "new", type: .movie)))
        }
        var removedIDs: [UUID] = []
        provider.removeFromMediaListHandler = { _, _, entryIDs in
            removedIDs += entryIDs
            remote.entries.removeAll { entryIDs.contains($0.id) }
        }
        let store = ServerMediaListsStore(directory: directory)
        await store.refresh(session: session(provider))
        online = false
        #expect(await store.add(item: MediaItem(id: "new", type: .movie), to: listID, kind: .playlist, session: session(provider)))
        let provisional = try #require(store.list(id: listID, kind: .playlist, scope: scope)?.entries.last?.id)
        #expect(await store.remove(entryID: provisional, from: listID, kind: .playlist, session: session(provider)))
        online = true
        await store.refresh(session: session(provider))
        #expect(removedIDs == [published])
        #expect(remote.entries.map(\.id) == [existing])
        #expect(store.pendingEdits(scope: scope).isEmpty)
    }

    @Test(arguments: [false, true])
    func offlineMoveResolvesBothMovingAndBeforeOccurrence(useProvisionalBefore: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let listID = UUID(), first = UUID(), second = UUID(), published = UUID()
        var remote = ServerMediaList(id: listID, name: "A", kind: .playlist, entries: [
            ServerMediaListEntry(id: first, item: MediaItem(id: "first", type: .movie)),
            ServerMediaListEntry(id: second, item: MediaItem(id: "second", type: .movie)),
        ], canEdit: true, entriesLoaded: true)
        var online = true
        provider.mediaListsHandler = { kind in kind == .playlist ? [remote] : [] }
        provider.mediaListHandler = { _, _ in
            guard online else { throw URLError(.notConnectedToInternet) }
            return remote
        }
        provider.addToMediaListHandler = { _, _, _ in
            remote.entries.append(ServerMediaListEntry(id: published, item: MediaItem(id: "new", type: .movie)))
        }
        provider.moveMediaListEntryHandler = { _, entryID, destination in
            let index = try #require(remote.entries.firstIndex { $0.id == entryID })
            let entry = remote.entries.remove(at: index)
            remote.entries.insert(entry, at: destination)
        }
        let store = ServerMediaListsStore(directory: directory)
        await store.refresh(session: session(provider))
        online = false
        #expect(await store.add(item: MediaItem(id: "new", type: .movie), to: listID, kind: .playlist, session: session(provider)))
        let provisional = try #require(store.list(id: listID, kind: .playlist, scope: scope)?.entries.last?.id)
        #expect(await store.move(
            entryID: useProvisionalBefore ? first : provisional,
            in: listID,
            before: useProvisionalBefore ? provisional : first,
            session: session(provider)
        ))
        online = true
        await store.refresh(session: session(provider))
        #expect(remote.entries.map(\.id) == (useProvisionalBefore ? [second, first, published] : [published, first, second]))
        #expect(store.pendingEdits(scope: scope).isEmpty)
    }

    @Test func ambiguousTemporaryRemovalIsRetainedForReview() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let listID = UUID(), published = UUID(), other = UUID()
        var remote = ServerMediaList(id: listID, name: "A", kind: .playlist, entries: [], canEdit: true, entriesLoaded: true)
        var online = true
        provider.mediaListsHandler = { kind in kind == .playlist ? [remote] : [] }
        provider.mediaListHandler = { _, _ in
            guard online else { throw URLError(.notConnectedToInternet) }
            return remote
        }
        provider.addToMediaListHandler = { _, _, _ in
            remote.entries = [published, other].map { ServerMediaListEntry(id: $0, item: MediaItem(id: "same", type: .movie)) }
        }
        var removedIDs: [UUID] = []
        provider.removeFromMediaListHandler = { _, _, ids in removedIDs += ids }
        let store = ServerMediaListsStore(directory: directory)
        await store.refresh(session: session(provider))
        online = false
        #expect(await store.add(item: MediaItem(id: "same", type: .movie), to: listID, kind: .playlist, session: session(provider)))
        let provisional = try #require(store.list(id: listID, kind: .playlist, scope: scope)?.entries.first?.id)
        #expect(await store.remove(entryID: provisional, from: listID, kind: .playlist, session: session(provider)))
        online = true
        await store.refresh(session: session(provider))
        #expect(removedIDs.isEmpty)
        #expect(remote.entries.map(\.id) == [published, other])
        let pending = try #require(store.pendingEdits(scope: scope).first)
        #expect(pending.action == .remove)
        #expect(pending.entryID == provisional)
        #expect(pending.needsReview)
    }

    @Test func acknowledgedRemovalKeepsSuccessorThroughRestartAndUnrelatedServerEdit() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let listID = UUID(), first = UUID(), current = UUID(), successor = UUID(), external = UUID()
        var remote = ServerMediaList(id: listID, name: "A", kind: .playlist, entries: [first, current, successor].map {
            ServerMediaListEntry(id: $0, item: MediaItem(id: $0.uuidString, type: .movie))
        }, canEdit: true, entriesLoaded: true)
        provider.mediaListsHandler = { kind in kind == .playlist ? [remote] : [] }
        provider.mediaListHandler = { _, _ in remote }
        provider.removeFromMediaListHandler = { _, _, ids in remote.entries.removeAll { ids.contains($0.id) } }
        let store = ServerMediaListsStore(directory: directory)
        await store.refresh(session: session(provider))
        let supplemental = VideoPlaylistsStore(directory: directory.appendingPathComponent("cloud"), syncEnabled: false)
        supplemental.registerServerPlaylist(id: listID, scope: scope)
        supplemental.setCursor(id: listID, entryID: current, positionTicks: 123, finished: false, scope: scope)
        #expect(await store.remove(entryID: current, from: listID, kind: .playlist, session: session(provider)))
        #expect(store.videoPlaylist(id: listID, scope: scope, supplemental: supplemental)?.cursor == PlaylistCursor(entryID: successor, positionTicks: 0, finished: false))
        let restored = ServerMediaListsStore(directory: directory)
        restored.load(scope: scope)
        #expect(restored.videoPlaylist(id: listID, scope: scope, supplemental: supplemental)?.cursor?.entryID == successor)
        remote.entries = [ServerMediaListEntry(id: external, item: MediaItem(id: "external", type: .movie)), remote.entries[1], remote.entries[0]]
        await restored.refresh(session: session(provider))
        #expect(restored.videoPlaylist(id: listID, scope: scope, supplemental: supplemental)?.cursor?.entryID == successor)
        #expect(supplemental.serverPlaylistState(id: listID, scope: scope).cursor?.entryID == current)
        let restartedAgain = ServerMediaListsStore(directory: directory)
        restartedAgain.load(scope: scope)
        #expect(restartedAgain.videoPlaylist(id: listID, scope: scope, supplemental: supplemental)?.cursor?.entryID == successor)
    }

    @Test func offlineCreatePreservesKnownMediaSnapshotAndRating() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.mediaListsHandler = { _ in throw URLError(.notConnectedToInternet) }
        let item = MediaItem(id: "movie", name: "Downloaded Movie", officialRating: "PG", productionYear: 2025, type: .movie)
        let store = ServerMediaListsStore(directory: directory)
        let id = try #require(await store.create(name: "Offline", kind: .playlist, session: session(provider), items: [item]))
        let restored = ServerMediaListsStore(directory: directory)
        restored.load(scope: scope)
        #expect(restored.list(id: id, kind: .playlist, scope: scope)?.entries.first?.item == item)
        let supplemental = VideoPlaylistsStore(directory: directory.appendingPathComponent("cloud"), syncEnabled: false)
        #expect(restored.videoPlaylist(id: id, scope: scope, supplemental: supplemental)?.entries.first?.reference.item.type == .movie)
        #expect(restored.videoPlaylist(id: id, scope: scope, supplemental: supplemental)?.entries.first?.reference.item.officialRating == "PG")
        #expect(restored.pendingEdits(scope: scope).first?.items == [item])
    }

    @Test func unseenMissingNativeCursorRetainsUnknownPosition() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let listID = UUID(), available = UUID(), unknown = UUID()
        let list = ServerMediaList(id: listID, name: "A", kind: .playlist, entries: [
            ServerMediaListEntry(id: available, item: MediaItem(id: "available", type: .movie)),
        ], canEdit: true, entriesLoaded: true)
        provider.mediaListsHandler = { kind in kind == .playlist ? [list] : [] }
        provider.mediaListHandler = { _, _ in list }
        let store = ServerMediaListsStore(directory: directory)
        await store.refresh(session: session(provider))
        let supplemental = VideoPlaylistsStore(directory: directory.appendingPathComponent("cloud"), syncEnabled: false)
        supplemental.registerServerPlaylist(id: listID, scope: scope)
        supplemental.setCursor(id: listID, entryID: unknown, positionTicks: 789, finished: false, scope: scope)
        #expect(store.videoPlaylist(id: listID, scope: scope, supplemental: supplemental)?.cursor == PlaylistCursor(entryID: unknown, positionTicks: 789, finished: false))
    }

    @Test func deactivationRecordsInflightAcknowledgmentButStopsNextMutation() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let listID = UUID()
        var remote = ServerMediaList(id: listID, name: "Original", kind: .playlist, entries: [], canEdit: true, entriesLoaded: true)
        var online = true
        provider.mediaListsHandler = { kind in kind == .playlist ? [remote] : [] }
        provider.mediaListHandler = { _, _ in
            guard online else { throw URLError(.notConnectedToInternet) }
            return remote
        }
        var acknowledgment: CheckedContinuation<Void, Never>?
        var mutations: [String] = []
        provider.renameMediaListHandler = { _, _, name in
            mutations.append(name)
            if name == "First" {
                await withCheckedContinuation { acknowledgment = $0 }
            }
            remote.name = name
        }
        let store = ServerMediaListsStore(directory: directory)
        await store.refresh(session: session(provider))
        online = false
        #expect(await store.rename(id: listID, kind: .playlist, name: "First", session: session(provider)))
        #expect(await store.rename(id: listID, kind: .playlist, name: "Second", session: session(provider)))
        online = true
        let task = Task { await store.refresh(session: session(provider)) }
        while acknowledgment == nil {
            await Task.yield()
        }
        store.deactivate()
        acknowledgment?.resume()
        await task.value
        #expect(mutations == ["First"])
        #expect(remote.name == "First")
        #expect(store.pendingEdits(scope: scope).map(\.name) == ["Second"])
        let restored = ServerMediaListsStore(directory: directory)
        restored.load(scope: scope)
        #expect(restored.pendingEdits(scope: scope).map(\.name) == ["Second"])
        store.load(scope: scope)
        await store.refresh(session: session(provider))
        #expect(mutations == ["First", "Second"])
        #expect(remote.name == "Second")
        #expect(store.pendingEdits(scope: scope).isEmpty)
    }

    @Test func deactivatedStoreRejectsLateSessionTasksUntilExplicitLoad() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var reads = 0
        provider.mediaListsHandler = { _ in reads += 1; return [] }
        let store = ServerMediaListsStore(directory: directory)
        store.load(scope: scope)
        store.deactivate()
        await store.refresh(session: session(provider))
        #expect(await store.create(name: "Stale", kind: .playlist, session: session(provider)) == nil)
        #expect(reads == 0)
        #expect(store.pendingEdits(scope: scope).isEmpty)
        store.load(scope: scope)
        await store.refresh(session: session(provider))
        #expect(reads == 2)
        store.load(scope: AccountScope(serverID: "s", userID: "other"))
        await store.refresh(session: session(provider))
        #expect(await store.create(name: "Old account", kind: .playlist, session: session(provider)) == nil)
        #expect(reads == 2)
    }

    @Test func repeatedNativeCreateInputIsRejectedBeforeJournalOrNetwork() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var reads = 0, creates = 0
        provider.mediaListsHandler = { _ in reads += 1; return [] }
        provider.createMediaListHandler = { _, _, _ in creates += 1; return UUID() }
        let store = ServerMediaListsStore(directory: directory)
        let mediaID = UUID()
        #expect(await store.create(name: "Repeated", kind: .playlist, session: session(provider), itemIDs: [mediaID.uuidString, ServerMediaListID.string(mediaID)]) == nil)
        let item = MediaItem(id: mediaID.uuidString, type: .movie)
        #expect(await store.create(name: "Repeated snapshots", kind: .playlist, session: session(provider), items: [item, item]) == nil)
        #expect(reads == 0)
        #expect(creates == 0)
        #expect(store.pendingEdits(scope: scope).isEmpty)
        #expect(store.lists(kind: .playlist, scope: scope).isEmpty)
        #expect(store.errorMessage != nil)
    }

    @Test func duplicateLegacyImportPreservesOriginalAndDoesNotTransmit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var reads = 0, creates = 0
        provider.mediaListsHandler = { _ in reads += 1; return [] }
        provider.createMediaListHandler = { _, _, _ in creates += 1; return UUID() }
        let supplemental = VideoPlaylistsStore(directory: directory.appendingPathComponent("cloud"), syncEnabled: false)
        let oldID = try #require(supplemental.create(name: "Repeat", scope: scope))
        for _ in 0 ..< 2 {
            #expect(supplemental.add(item: MediaItem(id: "same", type: .movie), to: oldID, scope: scope))
        }
        let original = try #require(supplemental.playlist(id: oldID, scope: scope))
        let store = ServerMediaListsStore(directory: directory)
        #expect(await store.importLegacy(original, session: session(provider), supplemental: supplemental) == nil)
        #expect(supplemental.playlist(id: oldID, scope: scope) == original)
        #expect(store.legacyImportID(for: oldID, scope: scope) == nil)
        #expect(store.pendingEdits(scope: scope).isEmpty)
        #expect(reads == 0)
        #expect(creates == 0)
        #expect(store.errorMessage != nil)
    }

    @Test func addingExistingMediaIsRejectedBeforeJournal() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let listID = UUID(), mediaID = UUID()
        let list = ServerMediaList(id: listID, name: "Unique", kind: .playlist, entries: [
            ServerMediaListEntry(id: mediaID, item: MediaItem(id: ServerMediaListID.string(mediaID), type: .movie)),
        ], canEdit: true, entriesLoaded: true)
        provider.mediaListsHandler = { kind in kind == .playlist ? [list] : [] }
        provider.mediaListHandler = { _, _ in list }
        var additions = 0
        provider.addToMediaListHandler = { _, _, _ in additions += 1 }
        let store = ServerMediaListsStore(directory: directory)
        await store.refresh(session: session(provider))
        #expect(await store.add(item: MediaItem(id: mediaID.uuidString, type: .movie), to: listID, kind: .playlist, session: session(provider)) == false)
        #expect(additions == 0)
        #expect(store.pendingEdits(scope: scope).isEmpty)
        #expect(store.list(id: listID, kind: .playlist, scope: scope)?.entries.count == 1)
        #expect(store.errorMessage != nil)
    }

    @Test func deactivationStopsRemainingReplacementMutationStages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let listID = UUID(), oldID = UUID(), newID = UUID()
        var remote = ServerMediaList(id: listID, name: "A", kind: .playlist, entries: [
            ServerMediaListEntry(id: oldID, item: MediaItem(id: "old", type: .movie)),
        ], canEdit: true, entriesLoaded: true)
        provider.mediaListsHandler = { kind in kind == .playlist ? [remote] : [] }
        provider.mediaListHandler = { _, _ in remote }
        provider.addToMediaListHandler = { _, _, _ in remote.entries.append(ServerMediaListEntry(id: newID, item: MediaItem(id: "new", type: .movie))) }
        var acknowledgment: CheckedContinuation<Void, Never>?
        provider.moveMediaListEntryHandler = { _, _, _ in await withCheckedContinuation { acknowledgment = $0 } }
        var removals = 0
        provider.removeFromMediaListHandler = { _, _, _ in removals += 1 }
        let store = ServerMediaListsStore(directory: directory)
        await store.refresh(session: session(provider))
        let task = Task { await store.replace(entryID: oldID, in: listID, with: MediaItem(id: "new", type: .movie), session: session(provider)) }
        while acknowledgment == nil {
            await Task.yield()
        }
        store.deactivate()
        acknowledgment?.resume(returning: ())
        #expect(await task.value)
        #expect(removals == 0)
        let pending = try #require(store.pendingEdits(scope: scope).first)
        #expect(pending.action == .replace)
        #expect(pending.replacementID == newID)
        #expect(pending.status == .queued)
    }

    @Test func readdingReplacedNativeGUIDSelectsAndRemovesTheCurrentMembership() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let listID = UUID(), originalID = UUID(), replacementID = UUID()
        let original = MediaItem(id: ServerMediaListID.string(originalID), name: "Original", officialRating: "G", type: .movie)
        let replacement = MediaItem(id: ServerMediaListID.string(replacementID), name: "Replacement", officialRating: "G", type: .movie)
        var remote = ServerMediaList(id: listID, name: "Queue", kind: .playlist, entries: [ServerMediaListEntry(id: originalID, item: original)], canEdit: true, entriesLoaded: true)
        var online = true
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.mediaListsHandler = { kind in
            guard online else { throw URLError(.notConnectedToInternet) }
            return kind == .playlist ? [remote] : []
        }
        provider.mediaListHandler = { _, _ in
            guard online else { throw URLError(.notConnectedToInternet) }
            return remote
        }
        provider.addToMediaListHandler = { id, _, ids in
            #expect(id == listID)
            if ids == [ServerMediaListID.string(replacementID)] {
                remote.entries.append(ServerMediaListEntry(id: replacementID, item: replacement))
            } else {
                #expect(ids == [ServerMediaListID.string(originalID)])
                remote.entries.append(ServerMediaListEntry(id: originalID, item: original))
            }
        }
        provider.moveMediaListEntryHandler = { _, entryID, index in
            let oldIndex = try #require(remote.entries.firstIndex { $0.id == entryID })
            let entry = remote.entries.remove(at: oldIndex)
            remote.entries.insert(entry, at: index)
        }
        var removedIDs: [UUID] = []
        provider.removeFromMediaListHandler = { _, _, ids in
            removedIDs += ids
            remote.entries.removeAll { ids.contains($0.id) }
        }
        let store = ServerMediaListsStore(directory: folder.appendingPathComponent("native"))
        let session = session(provider)
        await store.refresh(session: session)
        #expect(await store.replace(entryID: originalID, in: listID, with: replacement, session: session))
        #expect(store.list(id: listID, kind: .playlist, scope: scope)?.entries.map(\.id) == [replacementID])
        online = false
        #expect(await store.add(item: original, to: listID, kind: .playlist, session: session))
        let provisional = try #require(store.list(id: listID, kind: .playlist, scope: scope)?.entries.last?.id)
        #expect(provisional != originalID)
        let supplemental = VideoPlaylistsStore(directory: folder.appendingPathComponent("supplemental"), syncEnabled: false)
        #expect(supplemental.registerServerPlaylist(id: listID, scope: scope))
        #expect(supplemental.setCursor(id: listID, entryID: provisional, positionTicks: 4_321_000, finished: false, scope: scope))
        online = true
        await store.refresh(session: session)
        #expect(store.pendingEdits(scope: scope).isEmpty)
        #expect(store.videoPlaylist(id: listID, scope: scope, supplemental: supplemental)?.cursor == PlaylistCursor(entryID: originalID, positionTicks: 4_321_000, finished: false))
        // Selecting the confirmed re-added membership must not follow its old alias.
        #expect(supplemental.setCursor(id: listID, entryID: originalID, positionTicks: 7_654_000, finished: false, scope: scope))
        let downloads = OfflineDownloadStore(fileStore: OfflineDownloadFileStore(directory: folder.appendingPathComponent("downloads")), coordinator: NativeListDownloadCoordinator())
        let player = PlaybackStore(item: original, session: session, playbackRefresh: PlaybackRefreshStore(), downloads: downloads)
        let coordinator = VideoPlaylistPlaybackCoordinator(playlistID: listID, entryID: originalID, fromBeginning: false, playlists: supplemental, session: session, downloads: downloads, serverLists: store)
        defer { coordinator.stop(player) }
        var requestedItems: [String] = []
        provider.itemHandler = { id in requestedItems.append(id); throw URLError(.notConnectedToInternet) }
        await coordinator.start(player)
        #expect(requestedItems == [ServerMediaListID.string(originalID)])
        #expect(supplemental.serverPlaylistState(id: listID, scope: scope).cursor == PlaylistCursor(entryID: originalID, positionTicks: 7_654_000, finished: false))
        removedIDs.removeAll()
        #expect(await store.remove(entryID: originalID, from: listID, kind: .playlist, session: session))
        #expect(removedIDs == [originalID])
        #expect(store.list(id: listID, kind: .playlist, scope: scope)?.entries.map(\.id) == [replacementID])
    }

    @Test func legacyUnscopedAliasPreservesUnknownCursorAndRequiresMutationReview() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let listID = UUID(), unknown = UUID(), available = UUID(), ambiguous = UUID()
        let list = ServerMediaList(id: listID, name: "Legacy cached list", kind: .playlist, entries: [
            ServerMediaListEntry(id: available, item: MediaItem(id: ServerMediaListID.string(available), type: .movie)),
        ], canEdit: true, entriesLoaded: true)
        var cache = ServerMediaListsStore.Cache()
        cache.lists = [list]
        cache.entryAliases[unknown.uuidString] = ambiguous
        cache.previousEntries[listID.uuidString] = [unknown, available]
        cache.pending = [ServerMediaListsStore.PendingEdit(id: UUID(), listID: listID, kind: .playlist, action: .remove, entryID: unknown)]
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cacheURL = folder.appendingPathComponent(VideoPlaylistsStore.digest(scope.serverID + "\u{0}" + scope.userID) + ".json")
        try JSONEncoder().encode(cache).write(to: cacheURL)
        let store = ServerMediaListsStore(directory: folder)
        store.load(scope: scope)
        let supplemental = VideoPlaylistsStore(directory: folder.appendingPathComponent("supplemental"), syncEnabled: false)
        let cursor = PlaylistCursor(entryID: unknown, positionTicks: 9_876_543, finished: false)
        #expect(supplemental.setServerPlaylistState(id: listID, cursor: cursor, queued: true, activityAt: nil, scope: scope))
        #expect(store.videoPlaylist(id: listID, scope: scope, supplemental: supplemental)?.cursor == cursor)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.mediaListsHandler = { kind in kind == .playlist ? [list] : [] }
        provider.mediaListHandler = { _, _ in list }
        var removals = 0
        provider.removeFromMediaListHandler = { _, _, _ in removals += 1 }
        await store.refresh(session: session(provider))
        #expect(removals == 0)
        #expect(store.pendingEdits(scope: scope).first?.needsReview == true)
        #expect(store.videoPlaylist(id: listID, scope: scope, supplemental: supplemental)?.cursor == cursor)
        let preserved = try JSONDecoder().decode(ServerMediaListsStore.Cache.self, from: Data(contentsOf: cacheURL))
        #expect(preserved.entryAliases[unknown.uuidString] == ambiguous)
    }

    @Test func replacingSharedNativeMediaGUIDDoesNotRedirectAnotherPlaylist() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let firstID = UUID(), secondID = UUID(), sharedID = UUID(), replacementID = UUID()
        let shared = MediaItem(id: ServerMediaListID.string(sharedID), name: "Shared movie", officialRating: "G", type: .movie)
        let replacement = MediaItem(id: ServerMediaListID.string(replacementID), name: "Replacement", officialRating: "G", type: .movie)
        let sharedEntry = ServerMediaListEntry(id: sharedID, item: shared)
        var first = ServerMediaList(id: firstID, name: "Edited", kind: .playlist, entries: [sharedEntry], canEdit: true, entriesLoaded: true)
        var second = ServerMediaList(id: secondID, name: "Untouched", kind: .playlist, entries: [sharedEntry, ServerMediaListEntry(id: replacementID, item: replacement)], canEdit: true, entriesLoaded: true)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.mediaListsHandler = { kind in kind == .playlist ? [first, second] : [] }
        provider.mediaListHandler = { id, _ in id == firstID ? first : second }
        provider.addToMediaListHandler = { id, _, ids in
            #expect(id == firstID)
            #expect(ids == [ServerMediaListID.string(replacementID)])
            first.entries.append(ServerMediaListEntry(id: replacementID, item: replacement))
        }
        provider.moveMediaListEntryHandler = { id, entryID, index in
            #expect(id == firstID)
            let indexToMove = try #require(first.entries.firstIndex { $0.id == entryID })
            let entry = first.entries.remove(at: indexToMove)
            first.entries.insert(entry, at: index)
        }
        var removedFromSecond: [UUID] = []
        provider.removeFromMediaListHandler = { id, _, ids in
            if id == firstID {
                first.entries.removeAll { ids.contains($0.id) }
            } else {
                #expect(id == secondID)
                removedFromSecond += ids
                second.entries.removeAll { ids.contains($0.id) }
            }
        }
        let directory = folder.appendingPathComponent("native")
        let store = ServerMediaListsStore(directory: directory)
        let session = session(provider)
        await store.refresh(session: session)
        let supplemental = VideoPlaylistsStore(directory: folder.appendingPathComponent("supplemental"), syncEnabled: false)
        let cursor = PlaylistCursor(entryID: sharedID, positionTicks: 8_765_432, finished: false)
        let activity = Date(timeIntervalSince1970: 1_720_000_000)
        #expect(supplemental.setServerPlaylistState(id: firstID, cursor: cursor, queued: true, activityAt: activity, scope: scope))
        #expect(supplemental.setServerPlaylistState(id: secondID, cursor: cursor, queued: true, activityAt: activity, scope: scope))
        let downloads = OfflineDownloadStore(fileStore: OfflineDownloadFileStore(directory: folder.appendingPathComponent("downloads")), coordinator: NativeListDownloadCoordinator())
        let player = PlaybackStore(item: shared, session: session, playbackRefresh: PlaybackRefreshStore(), downloads: downloads)
        let coordinator = VideoPlaylistPlaybackCoordinator(playlistID: secondID, entryID: sharedID, fromBeginning: false, playlists: supplemental, session: session, downloads: downloads, serverLists: store)
        defer { coordinator.stop(player) }

        #expect(await store.replace(entryID: sharedID, in: firstID, with: replacement, session: session))
        #expect(store.pendingEdits(scope: scope).isEmpty)
        #expect(store.videoPlaylist(id: firstID, scope: scope, supplemental: supplemental)?.cursor?.entryID == replacementID)
        let untouched = try #require(store.videoPlaylist(id: secondID, scope: scope, supplemental: supplemental))
        #expect(untouched.entries.map(\.id) == [sharedID, replacementID])
        #expect(untouched.cursor == cursor)
        #expect(untouched.queued)
        #expect(untouched.activityAt == activity)
        var requestedItems: [String] = []
        provider.itemHandler = { id in requestedItems.append(id); throw URLError(.notConnectedToInternet) }
        await coordinator.start(player)
        #expect(requestedItems == [ServerMediaListID.string(sharedID)])
        #expect(supplemental.serverPlaylistState(id: secondID, scope: scope).cursor == cursor)
        #expect(supplemental.serverPlaylistState(id: secondID, scope: scope).queued)
        #expect(provider.playbackResolutionCallCount == 0)
        let restored = ServerMediaListsStore(directory: directory)
        restored.load(scope: scope)
        #expect(restored.videoPlaylist(id: secondID, scope: scope, supplemental: supplemental)?.cursor == cursor)
        #expect(await store.remove(entryID: sharedID, from: secondID, kind: .playlist, session: session))
        #expect(removedFromSecond == [sharedID])
        #expect(store.list(id: secondID, kind: .playlist, scope: scope)?.entries.map(\.id) == [replacementID])
    }

    @Test func migratedIntentSurvivesDelayedCanonicalDefaultInBothMergeDirections() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let oldID = UUID(), nativeID = UUID(), entryID = UUID()
        let cursor = PlaylistCursor(entryID: entryID, positionTicks: 7_654_321, finished: false)
        let activity = Date(timeIntervalSince1970: 1_720_000_000)
        let store = VideoPlaylistsStore(directory: folder.appendingPathComponent("source"), syncEnabled: false)
        #expect(store.setServerPlaylistState(id: oldID, cursor: cursor, queued: true, activityAt: activity, scope: scope))
        // Playback registration happens before draft migration, giving its
        // default queued:false a newer revision than the draft's queued:true.
        #expect(store.registerServerPlaylist(id: nativeID, scope: scope))
        let delayed = store.envelope
        #expect(store.migrateServerPlaylistState(from: oldID, to: nativeID, scope: scope))
        let migrated = store.envelope

        for delayedFirst in [false, true] {
            let restored = VideoPlaylistsStore(directory: folder.appendingPathComponent(delayedFirst ? "delayed-first" : "migrated-first"), syncEnabled: false)
            restored.load(scope: scope)
            #expect(restored.saveSyncState { state in
                state.records = delayedFirst ? delayed.records : migrated.records
                for (key, record) in delayedFirst ? migrated.records : delayed.records {
                    state.records[key] = state.records[key]?.merging(record) ?? record
                }
                state.clock = max(delayed.clock, migrated.clock)
            })
            let result = restored.serverPlaylistState(id: nativeID, scope: scope)
            #expect(result.queued)
            #expect(result.activityAt == activity)
            #expect(result.cursor == cursor)
            let revision = restored.revision
            #expect(restored.migrateServerPlaylistState(from: oldID, to: nativeID, scope: scope))
            #expect(restored.revision == revision)
            #expect(restored.serverPlaylistState(id: nativeID, scope: scope).queued)
        }
    }

    @Test func confirmedNativeCursorAliasPersistsForDeviceWithoutAliasCache() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let nativeID = UUID(), mediaID = UUID()
        let item = MediaItem(id: ServerMediaListID.string(mediaID), name: "Movie", officialRating: "G", type: .movie)
        let native = ServerMediaList(
            id: nativeID,
            name: "Queue",
            kind: .playlist,
            entries: [ServerMediaListEntry(id: mediaID, item: item)],
            canEdit: true,
            entriesLoaded: true
        )
        var online = false, created = false
        provider.mediaListsHandler = { kind in
            guard online else { throw URLError(.notConnectedToInternet) }
            return created && kind == .playlist ? [native] : []
        }
        provider.mediaListHandler = { _, _ in native }
        provider.createMediaListHandler = { _, _, _ in created = true; return nativeID }
        let firstCache = ServerMediaListsStore(directory: folder.appendingPathComponent("first-native"))
        let provisionalList = try #require(await firstCache.create(name: "Queue", kind: .playlist, session: session(provider), items: [item]))
        let provisionalEntry = try #require(firstCache.list(id: provisionalList, kind: .playlist, scope: scope)?.entries.first?.id)
        let firstState = VideoPlaylistsStore(directory: folder.appendingPathComponent("first-cloud"), syncEnabled: false)
        firstState.registerServerPlaylist(id: provisionalList, scope: scope)
        firstState.setCursor(id: provisionalList, entryID: provisionalEntry, positionTicks: 1_234_567, finished: false, scope: scope)
        firstState.setQueued(id: provisionalList, queued: true, scope: scope)
        let activity = firstState.serverPlaylistState(id: provisionalList, scope: scope).activityAt
        online = true
        await firstCache.refresh(session: session(provider))
        #expect(firstCache.resolvedEntryID(provisionalEntry, inList: provisionalList, scope: scope) == mediaID)
        #expect(firstCache.videoPlaylist(id: nativeID, scope: scope, supplemental: firstState)?.cursor?.entryID == mediaID)
        let canonical = firstState.serverPlaylistState(id: nativeID, scope: scope)
        #expect(canonical.cursor == PlaylistCursor(entryID: mediaID, positionTicks: 1_234_567, finished: false))
        #expect(canonical.queued)
        #expect(canonical.activityAt == activity)
        let revision = firstState.revision
        _ = firstCache.videoPlaylist(id: nativeID, scope: scope, supplemental: firstState)
        #expect(firstState.revision == revision)

        // Replicate only Gus CloudKit records; native aliases stay on device one.
        let secondState = VideoPlaylistsStore(directory: folder.appendingPathComponent("second-cloud"), syncEnabled: false)
        secondState.load(scope: scope)
        #expect(secondState.saveSyncState { state in
            state.records = firstState.envelope.records
            state.clock = firstState.envelope.clock
        })
        let secondCache = ServerMediaListsStore(directory: folder.appendingPathComponent("second-native"))
        await secondCache.refresh(id: nativeID, kind: .playlist, session: session(provider))
        #expect(secondCache.resolvedEntryID(provisionalEntry, inList: nativeID, scope: scope) == provisionalEntry)
        let secondProjection = try #require(secondCache.videoPlaylist(id: nativeID, scope: scope, supplemental: secondState))
        #expect(secondProjection.cursor == PlaylistCursor(entryID: mediaID, positionTicks: 1_234_567, finished: false))
        #expect(secondProjection.entries.contains { $0.id == secondProjection.cursor?.entryID })
        #expect(secondProjection.queued)
        #expect(secondProjection.activityAt == activity)
    }
}

private final class NativeListDownloadCoordinator: DownloadSessionCoordinating {
    func setEventHandler(_ eventHandler: DownloadSessionCoordinatorEventHandler?) {}
    func startDownload(from url: URL, recordID: String) {}
    func resumeDownload(with resumeData: Data, recordID: String) {}
    func pause(recordID: String, completion: @escaping (Data?) -> Void) {
        completion(nil)
    }

    func cancel(recordID: String) {}
    func reconnectActiveTasks() {}
}
