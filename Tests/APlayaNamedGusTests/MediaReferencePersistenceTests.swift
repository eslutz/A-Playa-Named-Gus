import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@MainActor
@Suite("Saved reference safety")
struct MediaReferencePersistenceTests {
    let scope = AccountScope(serverID: "s", userID: "u")
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func session(_ provider: FakeMediaProviderSession) -> SessionStore {
        SessionStore(
            client: JellyfinClientFactory.makeClient(url: URL(string: "https://example.invalid")!),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: URL(string: "https://example.invalid")!),
            mediaProvider: provider
        )
    }

    @Test("legacy migration preserves order and stable queue identities on relaunch")
    func legacyMigration() throws {
        let dir = directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(scope.storageKey + ".json")
        let old = [MediaItem(id: "a", name: "Trespass", type: .movie), MediaItem(id: "b", type: .episode)]
        let bytes = try JSONEncoder().encode(old)
        try bytes.write(to: url)
        let persistence = UpNextPersistence(directory: dir)
        let first = try persistence.loadEntries(scope: scope)
        let second = try persistence.loadEntries(scope: scope)
        #expect(first.map(\.reference.item.id) == ["a", "b"])
        #expect(first.map(\.id) == second.map(\.id))
        #expect(try Data(contentsOf: url.appendingPathExtension("legacy-backup")) == bytes)
    }

    @Test("unreadable queue is never overwritten by a toggle")
    func corruptQueue() throws {
        let dir = directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(scope.storageKey + ".json")
        let bytes = Data("corrupt".utf8)
        try bytes.write(to: url)
        let store = UpNextStore(persistence: UpNextPersistence(directory: dir))
        store.toggle(MediaItem(id: "new"), serverID: "s", userID: "u")
        #expect(try Data(contentsOf: url) == bytes)
        #expect(store.errorMessage != nil)
    }

    @Test("removed pin cannot be restored by late refresh")
    func removalDuringRefresh() async {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var continuation: CheckedContinuation<MediaItem, Never>?
        provider.itemHandler = { _ in await withCheckedContinuation { continuation = $0 } }
        let session = session(provider)
        let progress = OfflinePlaybackProgressStore(directory: directory())
        progress.checkpoint(itemID: "old", positionTicks: 200, scope: scope)
        let store = UpNextStore(persistence: UpNextPersistence(directory: directory()), progressStore: progress)
        store.toggle(MediaItem(id: "old"), serverID: "s", userID: "u")
        let entry = store.entries(serverID: "s", userID: "u")[0]
        let refresh = Task { await store.refresh(session: session) }
        for _ in 0 ..< 1000 {
            if continuation != nil {
                break
            }; await Task.yield()
        }
        #expect(continuation != nil)
        store.remove(entry)
        continuation?.resume(returning: MediaItem(id: "new", name: "Fresh"))
        await refresh.value
        #expect(store.items(serverID: "s", userID: "u").isEmpty)
        #expect(progress.transfers(scope: scope).isEmpty)
    }

    @Test("only a committed replacement stages progress transfer", arguments: [false, true])
    func replacementTransferRequiresCommit(staleVersion: Bool) async {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { id in MediaItem(id: id, type: .movie) }
        let session = session(provider)
        let progress = OfflinePlaybackProgressStore(directory: directory())
        progress.checkpoint(itemID: "old", positionTicks: 200, scope: scope)
        let store = UpNextStore(persistence: UpNextPersistence(directory: directory()), progressStore: progress)
        store.toggle(MediaItem(id: "old", type: .movie), serverID: "s", userID: "u")
        let entry = store.entries(serverID: "s", userID: "u")[0]
        if staleVersion {
            await store.refresh(session: session)
            #expect(store.entries(serverID: "s", userID: "u")[0].version != entry.version)
        }
        let accepted = await store.replace(entry, with: MediaItem(id: "new", type: .movie), session: session)
        #expect(accepted == !staleVersion)
        #expect(store.items(serverID: "s", userID: "u").first?.id == (staleVersion ? "old" : "new"))
        #expect(progress.transfers(scope: scope).map(\.replacement?.id) == (staleVersion ? [] : ["new"]))
        #expect(progress.positionTicks(forItemID: "old", scope: scope) == 200)
    }

    @Test("offline queue remains intact while confirmed missing entries become manageable")
    func unavailableVersusOffline() async {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in throw GusError.offline }
        let session = session(provider)
        let store = UpNextStore(persistence: UpNextPersistence(directory: directory()))
        store.toggle(MediaItem(id: "old"), serverID: "s", userID: "u")
        await store.refresh(session: session)
        #expect(store.entries(serverID: "s", userID: "u")[0].availability == .unverified)
        provider.itemHandler = { _ in throw GusError.notFound }
        await store.refresh(session: session, force: true)
        #expect(store.entries(serverID: "s", userID: "u")[0].availability == .unavailable)
        #expect(store.items(serverID: "s", userID: "u").count == 1)
    }

    @Test("a missing progress target does not starve healthy uploads")
    func missingProgressDoesNotBlock() async {
        let progress = OfflinePlaybackProgressStore(directory: directory())
        progress.checkpoint(itemID: "a", positionTicks: 100, scope: scope)
        progress.checkpoint(itemID: "b", positionTicks: 200, scope: scope)
        var uploaded: [String] = []
        await progress.sync(scope: scope, isCurrentScope: { true }) { entry in
            if entry.itemID == "a" {
                throw GusError.notFound
            }
            uploaded.append(entry.itemID)
        }
        #expect(uploaded == ["b"])
        #expect(progress.pendingCheckpoints(scope: scope).map(\.itemID) == ["a"])
    }

    @Test("replacement progress requires confirmation and preserves original position")
    func progressConfirmation() async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let replacement = MediaItem(id: "new", runTimeTicks: 150, type: .movie)
        provider.itemHandler = { _ in replacement }
        let progress = OfflinePlaybackProgressStore(directory: directory())
        progress.checkpoint(itemID: "old", positionTicks: 200, scope: scope)
        progress.offerTransfer(from: "old", to: replacement, scope: scope)
        #expect(progress.positionTicks(forItemID: "new", scope: scope) == nil)
        let pending = try #require(progress.transfers(scope: scope).first)
        try await progress.confirmTransfer(pending, session: session(provider))
        #expect(progress.positionTicks(forItemID: "old", scope: scope) == 200)
        #expect(progress.positionTicks(forItemID: "new", scope: scope) == 149)
        #expect(progress.transfers(scope: scope).isEmpty)
    }

    @Test("remote rebinding never changes downloaded file identity")
    func preservesLocalIdentity() throws {
        let old = MediaItem(id: "old", type: .movie)
        var record = OfflineDownloadRecord(
            id: "record",
            item: old,
            filePath: "original.mp4",
            byteCount: 100,
            serverID: "s",
            userID: "u",
            downloadedAt: Date()
        )
        record.remoteReference = MediaReference(item: MediaItem(id: "new", type: .movie), scope: scope)
        let decoded = try JSONDecoder().decode(OfflineDownloadRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded.item.id == "old")
        #expect(decoded.filePath == "original.mp4")
        #expect(decoded.remoteReference?.item.id == "new")
    }

    @Test("remote bindings never alias original downloaded bytes")
    func remoteBindingIsNotLocalIdentity() throws {
        let files = OfflineDownloadFileStore(directory: directory())
        var record = OfflineDownloadRecord(
            id: "record",
            item: MediaItem(id: "old"),
            filePath: "old.mp4",
            byteCount: 100,
            serverID: "s",
            userID: "u",
            downloadedAt: Date()
        )
        record.remoteReference = MediaReference(item: MediaItem(id: "different"), scope: scope)
        try files.persist(record)
        #expect(files.record(forItemID: "old", serverID: "s", userID: "u") != nil)
        #expect(files.record(forItemID: "different", serverID: "s", userID: "u") == nil)
    }

    @Test("account changes and replaced checkpoints prevent stale uploads", arguments: [true, false])
    func preUploadRecheck(accountChanged: Bool) async {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var continuation: CheckedContinuation<MediaItem, Never>?
        provider.itemHandler = { _ in await withCheckedContinuation { continuation = $0 } }
        var uploaded = 0
        provider.progressHandler = { _, _ in uploaded += 1 }
        let progress = OfflinePlaybackProgressStore(directory: directory())
        progress.checkpoint(itemID: "item", positionTicks: 10, scope: scope)
        var active = true
        let task = Task { await progress.sync(session: session(provider)) { active } }
        for _ in 0 ..< 1000 {
            if continuation != nil {
                break
            }; await Task.yield()
        }
        #expect(continuation != nil)
        if accountChanged {
            active = false
        } else {
            progress.checkpoint(itemID: "item", positionTicks: 99, scope: scope)
        }
        continuation?.resume(returning: MediaItem(id: "item"))
        await task.value
        #expect(uploaded == 0)
        #expect(progress.pendingCheckpoints(scope: scope).count == 1)
    }

    @Test("scoped links refuse a different server and round trip")
    func scopedLinks() throws {
        let link = ContentLink.item(id: "movie", serverID: "s", provider: .jellyfin)
        #expect(ContentLink(url: link.url) == link)
        #expect(ContentLink(url: link.universalURL) == link)
        #expect(try !link.accepts(server: ServerConnection(id: "other", name: "Other", url: #require(URL(string: "https://example.invalid")))))
    }
}
