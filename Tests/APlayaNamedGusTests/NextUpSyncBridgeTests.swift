import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("Next Up sync bridge")
struct NextUpSyncBridgeTests {
    @Test("first verified identity preserves legacy order and discovery ranks across relaunch", arguments: [false, true])
    func firstIdentityPreservesLegacyOrdering(relaunch: Bool) throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let savedDirectory = folder.appendingPathComponent("saved")
        let persistence = UpNextPersistence(directory: folder.appendingPathComponent("queue"))
        let activityPersistence = NextUpActivityPersistence(directory: folder.appendingPathComponent("activity"))
        let sync = VideoPlaylistsStore(directory: savedDirectory, syncEnabled: false)
        let references = ["one", "two", "three"].map { MediaReference(item: MediaItem(id: $0, type: .movie), scope: scope) }
            .sorted { VideoPlaylistsStore.canonicalIntentID(reference: $0).uuidString > VideoPlaylistsStore.canonicalIntentID(reference: $1).uuidString }
        try persistence.saveEntries(references.map { UpNextEntry(id: UUID(), reference: $0) }, scope: scope)
        let queue = UpNextStore(persistence: persistence, syncStore: sync)
        let before = queue.entries(serverID: "s", userID: "u")
        #expect(before.map(\.reference.item.id) == references.map(\.item.id))
        let activity = NextUpActivityStore(persistence: activityPersistence, syncStore: sync)
        let firstSeen = ["media:jellyfin:automatic"] + references.reversed().compactMap { NextUpBuilder.mediaID($0.item) }
        activity.remember(firstSeen, scope: scope)
        activity.recordPlayback(item: MediaItem(id: "other"), scope: scope, at: Date(timeIntervalSince1970: 42))
        try sync.selectIdentity("account-a", scope: scope)
        let selectedSync = relaunch ? VideoPlaylistsStore(directory: savedDirectory, syncEnabled: false) : sync
        let selectedQueue = relaunch ? UpNextStore(persistence: persistence, syncStore: selectedSync) : queue
        let selectedActivity = relaunch ? NextUpActivityStore(persistence: activityPersistence, syncStore: selectedSync) : activity
        let migrated = selectedQueue.entries(serverID: "s", userID: "u")
        #expect(migrated.map(\.id) == before.map(\.id))
        #expect(migrated.map(\.reference.item.id) == references.map(\.item.id))
        #expect(migrated.allSatisfy { $0.activityAt == nil })
        #expect(selectedActivity.firstSeenIDs(scope: scope) == firstSeen)
        #expect(selectedActivity.snapshot(scope: scope)["media:jellyfin:other"] == Date(timeIntervalSince1970: 42))
        let displayed = NextUpBuilder.build(resume: [], nextEpisodes: [], saved: migrated, firstSeenIDs: selectedActivity.firstSeenIDs(scope: scope))
        #expect(displayed.compactMap { $0.item?.id } == references.reversed().compactMap(\.item.id))
        try selectedSync.selectIdentity("account-b", scope: scope)
        #expect(selectedQueue.entries(serverID: "s", userID: "u").isEmpty)
        #expect(selectedActivity.firstSeenIDs(scope: scope).isEmpty)
        #expect(selectedActivity.snapshot(scope: scope).isEmpty)
        try selectedSync.selectIdentity("account-a", scope: scope)
        #expect(selectedQueue.entries(serverID: "s", userID: "u").map(\.id) == before.map(\.id))
        #expect(selectedActivity.firstSeenIDs(scope: scope) == firstSeen)
    }

    @Test("an account switch before the queue observes migration cannot claim local data")
    func skippedIdentityObservationStillIsolatesAccountSwitch() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let sync = VideoPlaylistsStore(directory: folder.appendingPathComponent("saved"), syncEnabled: false)
        let queue = UpNextStore(persistence: UpNextPersistence(directory: folder.appendingPathComponent("queue")), syncStore: sync)
        queue.toggle(MediaItem(id: "local", type: .movie), serverID: "s", userID: "u")
        let activity = NextUpActivityStore(persistence: NextUpActivityPersistence(directory: folder.appendingPathComponent("activity")), syncStore: sync)
        activity.remember(["media:jellyfin:local"], scope: scope)
        try sync.selectIdentity("account-a", scope: scope)
        try sync.selectIdentity("account-b", scope: scope)
        #expect(queue.entries(serverID: "s", userID: "u").isEmpty)
        #expect(activity.firstSeenIDs(scope: scope).isEmpty)
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test("replacement preserves the durable intent key and settles without a revision feedback loop")
    func canonicalReplacement() async throws {
        let scope = AccountScope(serverID: "s", userID: "u")
        let sync = VideoPlaylistsStore(directory: directory(), syncEnabled: false)
        let store = UpNextStore(persistence: UpNextPersistence(directory: directory()), syncStore: sync)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { id in MediaItem(id: id, type: .movie) }
        let session = try SessionStore(
            client: JellyfinClientFactory.makeClient(url: #require(URL(string: "https://example.invalid"))),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: #require(URL(string: "https://example.invalid"))),
            mediaProvider: provider
        )
        let original = MediaItem(id: "old", type: .movie)
        store.toggle(original, serverID: "s", userID: "u")
        let old = store.entries(serverID: "s", userID: "u")[0]
        let replaced = await store.replace(old, with: MediaItem(id: "new", type: .movie), session: session)
        #expect(replaced)
        #expect(sync.savedIntents(scope: scope).filter(\.queued).count == 1)
        #expect(sync.savedIntents(scope: scope).first?.id == old.id)
        #expect(sync.savedIntents(scope: scope).first?.reference.item.id == "new")
        store.reconcileSyncedIntents(scope: scope)
        let revision = store.revision, syncRevision = sync.revision
        store.reconcileSyncedIntents(scope: scope)
        #expect(store.revision == revision)
        #expect(sync.revision == syncRevision)
        let entries = store.entries(serverID: "s", userID: "u")
        #expect(entries.count == 1)
        #expect(entries[0].id == old.id)
        #expect(entries[0].reference.item.id == "new")
        #expect(NextUpBuilder.build(resume: [], nextEpisodes: [], saved: entries).count == 1)
        #expect(entries[0].activityAt == old.activityAt)
    }

    @Test("a concurrent remote removal survives background reference refreshes with newer logical clocks")
    func metadataCannotRestoreMembership() async throws {
        let scope = AccountScope(serverID: "s", userID: "u")
        let first = VideoPlaylistsStore(directory: directory(), syncEnabled: false)
        let second = VideoPlaylistsStore(directory: directory(), syncEnabled: false)
        let a = UpNextStore(persistence: UpNextPersistence(directory: directory()), syncStore: first)
        let b = UpNextStore(persistence: UpNextPersistence(directory: directory()), syncStore: second)
        a.toggle(MediaItem(id: "movie", name: "Original", type: .movie), serverID: "s", userID: "u")
        second.load(scope: scope)
        _ = second.saveSyncState { state in state.records = first.envelope.records; state.clock = first.envelope.clock }
        b.load(serverID: "s", userID: "u")
        a.remove(a.entries(serverID: "s", userID: "u")[0])
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var refreshCount = 0
        provider.itemHandler = { id in
            refreshCount += 1
            return MediaItem(id: id, name: "Title \(refreshCount)", officialRating: "PG", type: .movie)
        }
        let session = try SessionStore(
            client: JellyfinClientFactory.makeClient(url: #require(URL(string: "https://example.invalid"))),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: #require(URL(string: "https://example.invalid"))),
            mediaProvider: provider
        )
        for _ in 0 ..< 5 {
            await b.refresh(session: session, force: true)
        }
        let remote = first.envelope.records
        _ = second.saveSyncState { state in
            for (key, record) in remote {
                state.records[key] = state.records[key]?.merging(record) ?? record
            }
        }
        b.reconcileSyncedIntents(scope: scope)
        #expect(second.savedIntents(scope: scope).filter(\.queued).isEmpty)
        #expect(b.entries(serverID: "s", userID: "u").isEmpty)
    }

    @Test("external cloud record or zone deletion after a rebind cannot republish cached intents", arguments: [false, true])
    func externalDeletionAfterRebind(zoneReset: Bool) async throws {
        let scope = AccountScope(serverID: "s", userID: "u")
        let sync = VideoPlaylistsStore(directory: directory(), syncEnabled: false)
        let persistence = UpNextPersistence(directory: directory())
        let store = UpNextStore(persistence: persistence, syncStore: sync)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { id in MediaItem(id: id, type: .movie) }
        let session = try SessionStore(
            client: JellyfinClientFactory.makeClient(url: #require(URL(string: "https://example.invalid"))),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: #require(URL(string: "https://example.invalid"))),
            mediaProvider: provider
        )
        store.toggle(MediaItem(id: "old", type: .movie), serverID: "s", userID: "u")
        let entry = try #require(store.entries(serverID: "s", userID: "u").first)
        let replaced = await store.replace(entry, with: MediaItem(id: "new", type: .movie), session: session)
        #expect(replaced)
        #expect(sync.saveSyncState { state in
            if zoneReset {
                try state.applyExternalZoneReset()
            } else {
                try state.applyExternalDeletion(recordIDs: ["intent-\(entry.id)"])
            }
        })
        store.reconcileSyncedIntents(scope: scope)
        let revision = store.revision, syncRevision = sync.revision
        store.reconcileSyncedIntents(scope: scope)
        #expect(store.revision == revision)
        #expect(sync.revision == syncRevision)
        #expect(sync.savedIntents(scope: scope).filter(\.queued).isEmpty)
        #expect(sync.envelope.pending.isEmpty)
        #expect(store.entries(serverID: "s", userID: "u").isEmpty)
        let reloaded = UpNextStore(persistence: persistence, syncStore: sync)
        reloaded.load(serverID: "s", userID: "u")
        #expect(reloaded.entries(serverID: "s", userID: "u").isEmpty)
        #expect(sync.envelope.pending.isEmpty)
    }
}
