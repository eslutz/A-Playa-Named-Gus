import CloudKit
import Foundation
@testable import Gus
import Testing

struct VideoPlaylistTests {
    @MainActor @Test func completionRetiresQueueAndExplicitRequeueResetsFinishedCursor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let id = UUID(), entryID = UUID()
        let store = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        #expect(store.registerServerPlaylist(id: id, scope: scope))
        store.setQueued(id: id, queued: true, scope: scope)
        #expect(store.setCursor(id: id, entryID: entryID, positionTicks: 10, finished: false, scope: scope))
        #expect(store.playlist(id: id, scope: scope)?.appearsInNextUp == true)
        #expect(store.setCursor(id: id, entryID: nil, positionTicks: nil, finished: true, scope: scope))
        let reloaded = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        #expect(reloaded.serverPlaylistState(id: id, scope: scope).queued == false)
        #expect(reloaded.playlist(id: id, scope: scope)?.appearsInNextUp == false)
        // Old installations may retain an explicit queue bit alongside completion.
        #expect(reloaded.setServerPlaylistState(id: id, cursor: PlaylistCursor(entryID: nil, positionTicks: nil, finished: true), queued: true, activityAt: nil, scope: scope))
        #expect(reloaded.playlist(id: id, scope: scope)?.appearsInNextUp == false)
        reloaded.setQueued(id: id, queued: true, scope: scope)
        let restored = try #require(reloaded.playlist(id: id, scope: scope))
        #expect(restored.appearsInNextUp)
        #expect(restored.cursor?.finished == false)
        #expect(restored.cursor?.positionTicks == 0)
    }

    @MainActor @Test(arguments: ["local", "account-a"])
    func disabledSyncIgnoresCloudAccountNotification(identity: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        if identity != "local" {
            try store.selectIdentity(identity, scope: scope)
        }
        let id = try #require(store.create(name: "Local legacy list", scope: scope))
        let nativeID = UUID(), entryID = UUID()
        #expect(store.setServerPlaylistState(id: nativeID, cursor: PlaylistCursor(entryID: entryID, positionTicks: 123, finished: false), queued: true, activityAt: nil, scope: scope))
        let queue = UpNextStore(persistence: UpNextPersistence(directory: directory.appendingPathComponent("queue")), syncStore: store)
        queue.toggle(MediaItem(id: "saved", type: .movie), serverID: "s", userID: "u")
        let before = store.envelope, revision = store.identityRevision
        let entries = queue.entries(serverID: "s", userID: "u")
        NotificationCenter.default.post(name: .CKAccountChanged, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.identityKey == identity)
        #expect(store.identityRevision == revision)
        #expect(store.envelope.records == before.records)
        #expect(store.envelope.pending == before.pending)
        #expect(store.playlist(id: id, scope: scope) != nil)
        #expect(store.serverPlaylistState(id: nativeID, scope: scope).cursor?.positionTicks == 123)
        #expect(queue.entries(serverID: "s", userID: "u") == entries)
        let restored = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        restored.load(scope: scope)
        #expect(restored.identityKey == identity)
        #expect(restored.envelope.records == before.records)
    }

    @MainActor @Test func enabledSyncStillIsolatesCloudAccountNotification() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = VideoPlaylistsStore(directory: directory, syncEnabled: true)
        _ = try #require(store.create(name: "Original account", scope: scope))
        NotificationCenter.default.post(name: .CKAccountChanged, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.identityKey.hasPrefix("signed-out-"))
        #expect(store.identityRevision > 0)
        #expect(store.playlists(scope: scope).isEmpty)
        #expect(store.envelope.pending.isEmpty)
    }

    @Test func concurrentFieldsAndEntriesMergeIndependently() throws {
        let scope = AccountScope(serverID: "server", userID: "user")
        var first = SavedMediaRecord(id: "playlist", scope: scope, kind: .playlist)
        var second = first
        try first.set("name", value: "A", revision: SavedMediaRevision(counter: 1, device: "a"))
        try second.set("queued", value: true, revision: SavedMediaRevision(counter: 1, device: "b"))
        let merged = first.merging(second)
        #expect(merged.value("name", as: String.self) == "A")
        #expect(merged.value("queued", as: Bool.self) == true)
        #expect(merged == second.merging(first))
    }

    @Test func equalClockUsesStableDeviceTie() throws {
        let scope = AccountScope(serverID: "server", userID: "user")
        var first = SavedMediaRecord(id: "playlist", scope: scope, kind: .playlist)
        var second = first
        try first.set("name", value: "A", revision: SavedMediaRevision(counter: 4, device: "a"))
        try second.set("name", value: "B", revision: SavedMediaRevision(counter: 4, device: "b"))
        #expect(first.merging(second).value("name", as: String.self) == "B")
        #expect(first.merging(second) == second.merging(first))
    }

    @Test func cloudReferenceDropsHistoryArtworkAndLocations() throws {
        var item = MediaItem(id: "media", imageTags: ["Primary": "https://secret/?token=x"], name: "Movie", type: .movie)
        item.externalIDs = ["Imdb": "tt123", "private": "https://secret"]
        let reference = SavedMediaReference(MediaReference(item: item, scope: AccountScope(serverID: "s", userID: "u")))
        let encoded = try String(decoding: JSONEncoder().encode(reference), as: UTF8.self)
        #expect(!encoded.contains("secret"))
        #expect(reference.reference.item.imageTags.isEmpty)
        #expect(reference.reference.item.mediaSources.isEmpty)
        #expect(reference.reference.item.userData == nil)
        #expect(reference.reference.item.externalIDs == ["imdb": "tt123"])
    }

    @MainActor @Test func persistenceKeepsCursorAndDeletedEntries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        let id = try #require(store.create(name: "Movies", scope: scope))
        #expect(store.add(item: MediaItem(id: "a", name: "A", type: .movie), to: id, scope: scope))
        #expect(store.add(item: MediaItem(id: "b", name: "B", type: .movie), to: id, scope: scope))
        let entries = try #require(store.playlist(id: id, scope: scope)).entries
        store.setCursor(id: id, entryID: entries[0].id, positionTicks: 100, finished: false, scope: scope)
        store.remove(entryID: entries[0].id, from: id, scope: scope)
        let restored = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        restored.load(scope: scope)
        let playlist = try #require(restored.playlist(id: id, scope: scope))
        #expect(playlist.entries.map(\.reference.item.id) == ["b"])
        #expect(playlist.cursor?.entryID == entries[1].id)
        #expect(playlist.cursor?.positionTicks == 0)
        #expect(restored.playlists(scope: AccountScope(serverID: "other", userID: "u")).isEmpty)
    }

    @MainActor @Test func canonicalSavedIntentRemovalCannotLeaveDuplicateUUID() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let reference = MediaReference(item: MediaItem(id: "movie", name: "M", type: .movie), scope: scope)
        let store = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        store.setSavedIntent(id: UUID(), reference: reference, queued: true, activityAt: nil, scope: scope)
        store.setSavedIntent(id: UUID(), reference: reference, queued: false, activityAt: nil, scope: scope)
        #expect(store.savedIntents(scope: scope).count == 1)
        #expect(store.savedIntents(scope: scope).first?.queued == false)
        #expect(store.savedIntents(scope: scope).first?.id == VideoPlaylistsStore.canonicalIntentID(reference: reference))
    }

    @MainActor @Test func identitySwitchIsolatesPendingChangesAndRestoresOriginalAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        let id = try #require(store.create(name: "A", scope: scope))
        try store.selectIdentity("account-a", scope: scope)
        #expect(store.playlist(id: id, scope: scope) != nil)
        #expect(store.envelope.pending.contains(id.uuidString))
        try store.selectIdentity("account-b", scope: scope)
        #expect(store.playlists(scope: scope).isEmpty)
        #expect(store.envelope.pending.isEmpty)
        _ = store.create(name: "B", scope: scope)
        try store.selectIdentity("account-a", scope: scope)
        #expect(store.playlists(scope: scope).map(\.name) == ["A"])
        #expect(store.envelope.pending == [id.uuidString])
    }

    @MainActor @Test func failedPersistenceDoesNotPublishMutation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        #expect(store.create(name: "Not saved", scope: scope) == nil)
        #expect(store.playlists(scope: scope).isEmpty)
        #expect(store.envelope.pending.isEmpty)
        #expect(store.errorMessage != nil)
    }

    @MainActor @Test func reorderAndReplacementRetainEntryIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        let id = try #require(store.create(name: "A", scope: scope))
        #expect(store.add(item: MediaItem(id: "first", type: .movie), to: id, scope: scope))
        #expect(store.add(item: MediaItem(id: "second", type: .episode), to: id, scope: scope))
        let entries = try #require(store.playlist(id: id, scope: scope)).entries
        store.move(entryID: entries[1].id, in: id, before: entries[0].id, scope: scope)
        #expect(store.playlist(id: id, scope: scope)?.entries.map(\.id) == [entries[1].id, entries[0].id])
        #expect(store.replace(entryID: entries[0].id, in: id, with: MediaItem(id: "replacement", type: .movie), scope: scope))
        #expect(store.playlist(id: id, scope: scope)?.entries.last?.id == entries[0].id)
        #expect(store.playlist(id: id, scope: scope)?.entries.last?.reference.item.id == "replacement")
    }

    @MainActor @Test func independentReplicaAddsAndCursorChangesConverge() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let first = VideoPlaylistsStore(directory: directory.appendingPathComponent("a"), syncEnabled: false)
        let second = VideoPlaylistsStore(directory: directory.appendingPathComponent("b"), syncEnabled: false)
        let id = try #require(first.create(name: "Shared", scope: scope))
        second.load(scope: scope)
        #expect(second.saveSyncState { state in
            state.records = first.envelope.records
            state.clock = first.envelope.clock
        })
        #expect(first.add(item: MediaItem(id: "one", type: .movie), to: id, scope: scope))
        #expect(second.add(item: MediaItem(id: "two", type: .episode), to: id, scope: scope))
        let entryID = try #require(first.playlist(id: id, scope: scope)?.entries.first?.id)
        first.setCursor(id: id, entryID: entryID, positionTicks: 200, finished: false, scope: scope)
        second.rename(id: id, name: "Renamed", scope: scope)
        let a = first.envelope.records, b = second.envelope.records
        #expect(first.saveSyncState { state in
            for (key, record) in b {
                state.records[key] = state.records[key]?.merging(record) ?? record
            }
        })
        #expect(second.saveSyncState { state in
            for (key, record) in a {
                state.records[key] = state.records[key]?.merging(record) ?? record
            }
        })
        #expect(first.playlist(id: id, scope: scope) == second.playlist(id: id, scope: scope))
        #expect(first.playlist(id: id, scope: scope)?.entries.count == 2)
        #expect(first.playlist(id: id, scope: scope)?.name == "Renamed")
        #expect(first.playlist(id: id, scope: scope)?.cursor?.positionTicks == 200)
    }

    @Test func staleIntentAddAndActivityConvergeWithoutResurrection() throws {
        let scope = AccountScope(serverID: "s", userID: "u")
        var added = SavedMediaRecord(id: "intent", scope: scope, kind: .intent)
        try added.set("queued", value: true, revision: SavedMediaRevision(counter: 1, device: "b"))
        try added.set("activity", value: Date(timeIntervalSince1970: 200), revision: SavedMediaRevision(counter: 1, device: "b"))
        var removed = added
        try removed.set("queued", value: false, revision: SavedMediaRevision(counter: 2, device: "a"))
        try removed.set("activity", value: Date(timeIntervalSince1970: 100), revision: SavedMediaRevision(counter: 3, device: "a"))
        let merged = added.merging(removed)
        #expect(merged.value("queued", as: Bool.self) == false)
        #expect(merged.value("activity", as: Date.self) == Date(timeIntervalSince1970: 200))
        #expect(merged == removed.merging(added))
        #expect(merged.merging(added) == merged)
    }

    @MainActor @Test func removingCurrentCursorUsesSuccessorThenPriorThenClears() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        let id = try #require(store.create(name: "A", scope: scope))
        for itemID in ["a", "b", "c"] {
            #expect(store.add(item: MediaItem(id: itemID, type: .movie), to: id, scope: scope))
        }
        let entries = try #require(store.playlist(id: id, scope: scope)).entries
        store.setCursor(id: id, entryID: entries[1].id, positionTicks: 123, finished: false, scope: scope)
        store.remove(entryID: entries[1].id, from: id, scope: scope)
        #expect(store.playlist(id: id, scope: scope)?.cursor == PlaylistCursor(entryID: entries[2].id, positionTicks: 0, finished: false))
        store.remove(entryID: entries[2].id, from: id, scope: scope)
        #expect(store.playlist(id: id, scope: scope)?.cursor?.entryID == entries[0].id)
        store.remove(entryID: entries[0].id, from: id, scope: scope)
        #expect(store.playlist(id: id, scope: scope)?.cursor == nil)
    }

    @MainActor @Test func remoteDeletedCurrentProjectsSuccessorWithoutWritingCursor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        let id = try #require(store.create(name: "A", scope: scope))
        for itemID in ["a", "b", "c"] {
            #expect(store.add(item: MediaItem(id: itemID, type: .movie), to: id, scope: scope))
        }
        let entries = try #require(store.playlist(id: id, scope: scope)).entries
        store.setCursor(id: id, entryID: entries[1].id, positionTicks: 123, finished: false, scope: scope)
        let original = store.envelope.records["cursor-\(id)"]
        #expect(store.saveSyncState { state in
            var removed = try #require(state.records[entries[1].id.uuidString])
            try removed.set("deleted", value: true, revision: SavedMediaRevision(counter: 100, device: "remote"))
            state.records[removed.id] = removed
        })
        let revision = store.revision
        #expect(store.playlist(id: id, scope: scope)?.cursor == PlaylistCursor(entryID: entries[2].id, positionTicks: 0, finished: false))
        #expect(store.envelope.records["cursor-\(id)"] == original)
        #expect(store.revision == revision)
    }

    @MainActor @Test func savedIntentReplacementIsAtomicAndReferenceRefreshPreservesRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        let old = MediaReference(item: MediaItem(id: "old", name: "Before", type: .movie), scope: scope)
        var fresh = MediaReference(item: MediaItem(id: "new", name: "After", type: .movie), scope: scope)
        let date = Date(timeIntervalSince1970: 123)
        store.setSavedIntent(id: UUID(), reference: old, queued: true, activityAt: date, scope: scope)
        let durableID = VideoPlaylistsStore.canonicalIntentID(reference: old)
        #expect(store.replaceSavedIntent(id: durableID, reference: fresh, removingIDs: [], activityAt: nil, scope: scope))
        #expect(store.savedIntents(scope: scope).filter(\.queued).map(\.reference.item.id) == ["new"])
        #expect(store.savedIntents(scope: scope).first { $0.queued }?.activityAt == date)
        let key = "intent-\(durableID)"
        let before = try #require(store.envelope.records[key])
        var remoteRemoval = before
        try remoteRemoval.set("queued", value: false, revision: SavedMediaRevision(counter: 50, device: "remote"))
        #expect(store.saveSyncState { $0.clock = 100 })
        fresh.item.name = "Updated title"
        store.updateSavedIntentReference(id: durableID, reference: fresh, scope: scope)
        let updated = try #require(store.envelope.records[key])
        #expect(updated.fields["queued"] == before.fields["queued"])
        #expect(updated.fields["activity"] == before.fields["activity"])
        #expect(updated.merging(remoteRemoval).value("queued", as: Bool.self) == false)
        #expect(store.savedIntents(scope: scope).map(\.id) == [durableID])
        store.setSavedIntent(id: durableID, reference: fresh, queued: false, activityAt: date, scope: scope)
        #expect(store.savedIntents(scope: scope).count == 1)
        #expect(store.savedIntents(scope: scope).first?.queued == false)
    }

    @MainActor @Test func externalDeletionPreservesReboundIntentTombstoneWithoutUpload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        let original = MediaReference(item: MediaItem(id: "old", type: .movie), scope: scope)
        let replacement = MediaReference(item: MediaItem(id: "new", type: .movie), scope: scope)
        let id = VideoPlaylistsStore.canonicalIntentID(reference: original)
        let key = "intent-\(id)"
        store.setSavedIntent(id: id, reference: original, queued: true, activityAt: nil, scope: scope)
        #expect(store.replaceSavedIntent(id: id, reference: replacement, removingIDs: [], activityAt: nil, scope: scope))
        let before = try #require(store.envelope.records[key]?.fields["queued"]?.revision)
        #expect(store.saveSyncState { try $0.applyExternalDeletion(recordIDs: [key]) })
        let saved = try #require(store.savedIntents(scope: scope).first)
        #expect(saved.id == id)
        #expect(saved.reference.item.id == "new")
        #expect(saved.queued == false)
        #expect(store.envelope.pending.isEmpty)
        #expect(try #require(store.envelope.records[key]?.fields["queued"]?.revision) > before)
        #expect(store.envelope.systemFields[key] == nil)
        let restored = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        restored.load(scope: scope)
        #expect(restored.savedIntents(scope: scope) == [saved])
        #expect(restored.envelope.pending.isEmpty)
    }

    @MainActor @Test func externalZoneResetDropsPlaylistsButRetainsIntentRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = VideoPlaylistsStore(directory: directory, syncEnabled: false)
        let reference = MediaReference(item: MediaItem(id: "movie", type: .movie), scope: scope)
        let id = VideoPlaylistsStore.canonicalIntentID(reference: reference)
        store.setSavedIntent(id: id, reference: reference, queued: true, activityAt: nil, scope: scope)
        _ = try #require(store.create(name: "Deleted zone", scope: scope))
        #expect(store.saveSyncState { try $0.applyExternalZoneReset() })
        #expect(store.playlists(scope: scope).isEmpty)
        #expect(store.savedIntents(scope: scope).map(\.queued) == [false])
        #expect(store.envelope.records.count == 1)
        #expect(store.envelope.pending.isEmpty)
        #expect(store.envelope.systemFields.isEmpty)
        store.setSavedIntent(id: id, reference: reference, queued: true, activityAt: nil, scope: scope)
        #expect(store.savedIntents(scope: scope).first?.queued == true)
        #expect(store.envelope.pending == ["intent-\(id)"])
    }
}
