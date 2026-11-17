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
        let store = SavedMediaStore(directory: directory, syncEnabled: false)
        #expect(store.registerServerPlaylist(id: id, scope: scope))
        store.setQueued(id: id, queued: true, scope: scope)
        #expect(store.setCursor(id: id, entryID: entryID, positionTicks: 10, finished: false, scope: scope))
        #expect(store.playlist(id: id, scope: scope)?.appearsInNextUp == true)
        #expect(store.setCursor(id: id, entryID: nil, positionTicks: nil, finished: true, scope: scope))
        let reloaded = SavedMediaStore(directory: directory, syncEnabled: false)
        #expect(reloaded.serverPlaylistState(id: id, scope: scope).queued == false)
        #expect(reloaded.playlist(id: id, scope: scope)?.appearsInNextUp == false)
        // Independently merged queue and completion registers may coexist.
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
        let store = SavedMediaStore(directory: directory, syncEnabled: false)
        if identity != "local" {
            try store.selectIdentity(identity, scope: scope)
        }
        let id = UUID()
        #expect(store.registerServerPlaylist(id: id, scope: scope))
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
        let restored = SavedMediaStore(directory: directory, syncEnabled: false)
        restored.load(scope: scope)
        #expect(restored.identityKey == identity)
        #expect(restored.envelope.records == before.records)
    }

    @MainActor @Test func enabledSyncStillIsolatesCloudAccountNotification() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = SavedMediaStore(directory: directory, syncEnabled: true)
        #expect(store.registerServerPlaylist(id: UUID(), scope: scope))
        NotificationCenter.default.post(name: .CKAccountChanged, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.identityKey.hasPrefix("signed-out-"))
        #expect(store.identityRevision > 0)
        #expect(!store.envelope.records.values.contains { $0.kind == .playlist })
        #expect(store.envelope.pending.isEmpty)
    }

    @Test func concurrentSupplementalFieldsMergeIndependently() throws {
        let scope = AccountScope(serverID: "server", userID: "user")
        var first = SavedMediaRecord(id: "playlist", scope: scope, kind: .playlist)
        var second = first
        try first.set("activity", value: Date(timeIntervalSince1970: 1), revision: SavedMediaRevision(counter: 1, device: "a"))
        try second.set("queued", value: true, revision: SavedMediaRevision(counter: 1, device: "b"))
        let merged = first.merging(second)
        #expect(merged.value("activity", as: Date.self) == Date(timeIntervalSince1970: 1))
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

    @MainActor @Test func canonicalSavedIntentRemovalCannotLeaveDuplicateUUID() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let reference = MediaReference(item: MediaItem(id: "movie", name: "M", type: .movie), scope: scope)
        let store = SavedMediaStore(directory: directory, syncEnabled: false)
        store.setSavedIntent(id: UUID(), reference: reference, queued: true, activityAt: nil, scope: scope)
        store.setSavedIntent(id: UUID(), reference: reference, queued: false, activityAt: nil, scope: scope)
        #expect(store.savedIntents(scope: scope).count == 1)
        #expect(store.savedIntents(scope: scope).first?.queued == false)
        #expect(store.savedIntents(scope: scope).first?.id == SavedMediaStore.canonicalIntentID(reference: reference))
    }

    @MainActor @Test func identitySwitchIsolatesPendingChangesAndRestoresOriginalAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = SavedMediaStore(directory: directory, syncEnabled: false)
        let id = UUID()
        #expect(store.registerServerPlaylist(id: id, scope: scope))
        try store.selectIdentity("account-a", scope: scope)
        #expect(store.playlist(id: id, scope: scope) != nil)
        let originalPending = store.envelope.pending
        #expect(originalPending.count == 1)
        try store.selectIdentity("account-b", scope: scope)
        #expect(!store.envelope.records.values.contains { $0.kind == .playlist })
        #expect(store.envelope.pending.isEmpty)
        #expect(store.registerServerPlaylist(id: UUID(), scope: scope))
        try store.selectIdentity("account-a", scope: scope)
        #expect(store.playlist(id: id, scope: scope) != nil)
        #expect(store.envelope.pending == originalPending)
    }

    @MainActor @Test func failedPersistenceDoesNotPublishMutation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = SavedMediaStore(directory: directory, syncEnabled: false)
        #expect(!store.registerServerPlaylist(id: UUID(), scope: scope))
        #expect(!store.envelope.records.values.contains { $0.kind == .playlist })
        #expect(store.envelope.pending.isEmpty)
        #expect(store.errorMessage != nil)
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

    @MainActor @Test func savedIntentReplacementIsAtomicAndReferenceRefreshPreservesRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = SavedMediaStore(directory: directory, syncEnabled: false)
        let old = MediaReference(item: MediaItem(id: "old", name: "Before", type: .movie), scope: scope)
        var fresh = MediaReference(item: MediaItem(id: "new", name: "After", type: .movie), scope: scope)
        let date = Date(timeIntervalSince1970: 123)
        store.setSavedIntent(id: UUID(), reference: old, queued: true, activityAt: date, scope: scope)
        let durableID = SavedMediaStore.canonicalIntentID(reference: old)
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
        let store = SavedMediaStore(directory: directory, syncEnabled: false)
        let original = MediaReference(item: MediaItem(id: "old", type: .movie), scope: scope)
        let replacement = MediaReference(item: MediaItem(id: "new", type: .movie), scope: scope)
        let id = SavedMediaStore.canonicalIntentID(reference: original)
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
        let restored = SavedMediaStore(directory: directory, syncEnabled: false)
        restored.load(scope: scope)
        #expect(restored.savedIntents(scope: scope) == [saved])
        #expect(restored.envelope.pending.isEmpty)
    }

    @MainActor @Test func externalZoneResetDropsPlaylistsButRetainsIntentRemoval() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = SavedMediaStore(directory: directory, syncEnabled: false)
        let reference = MediaReference(item: MediaItem(id: "movie", type: .movie), scope: scope)
        let id = SavedMediaStore.canonicalIntentID(reference: reference)
        store.setSavedIntent(id: id, reference: reference, queued: true, activityAt: nil, scope: scope)
        #expect(store.registerServerPlaylist(id: UUID(), scope: scope))
        #expect(store.saveSyncState { try $0.applyExternalZoneReset() })
        #expect(!store.envelope.records.values.contains { $0.kind == .playlist })
        #expect(store.savedIntents(scope: scope).map(\.queued) == [false])
        #expect(store.envelope.records.count == 1)
        #expect(store.envelope.pending.isEmpty)
        #expect(store.envelope.systemFields.isEmpty)
        store.setSavedIntent(id: id, reference: reference, queued: true, activityAt: nil, scope: scope)
        #expect(store.savedIntents(scope: scope).first?.queued == true)
        #expect(store.envelope.pending == ["intent-\(id)"])
    }

    @MainActor @Test func currentCursorSurvivesRelaunchAndOtherScopesStayIsolated() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let id = UUID(), entry = UUID()
        let store = SavedMediaStore(directory: directory, syncEnabled: false)
        #expect(store.registerServerPlaylist(id: id, scope: scope))
        #expect(store.setCursor(id: id, entryID: entry, positionTicks: 123, finished: false, scope: scope))
        let restored = SavedMediaStore(directory: directory, syncEnabled: false)
        #expect(restored.playlist(id: id, scope: scope)?.cursor == PlaylistCursor(entryID: entry, positionTicks: 123, finished: false))
        #expect(restored.playlist(id: id, scope: AccountScope(serverID: "other", userID: "u")) == nil)
    }

    @MainActor @Test func retiredRecordsAreDroppedWithoutLosingCurrentIntent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = AccountScope(serverID: "s", userID: "u")
        let store = SavedMediaStore(directory: directory, syncEnabled: false)
        let id = UUID()
        #expect(store.registerServerPlaylist(id: id, scope: scope))
        let url = directory.appendingPathComponent("local.json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var records = try #require(json["records"] as? [String: Any])
        records["retired-entry"] = ["kind": "entry"]
        records["retired-playlist"] = ["kind": "playlist", "id": "retired-playlist", "scope": ["serverID": "s", "userID": "u"], "fields": [:]]
        json["records"] = records
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let restored = SavedMediaStore(directory: directory, syncEnabled: false)
        #expect(restored.playlist(id: id, scope: scope) != nil)
        #expect(restored.envelope.records.count == 1)
        #expect(restored.errorMessage == nil)
    }
}
