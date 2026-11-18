import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("Download store integration")
struct DownloadStoreIntegrationTests {
    #if !os(tvOS)
        @Test("capacity allows large offline libraries and accounts for active transfers across accounts")
        func capacityTracksRemainingBytes() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let files = OfflineDownloadFileStore(directory: directory)
            let coordinator = IntegrationDownloadCoordinator()
            let store = OfflineDownloadStore(fileStore: files, coordinator: coordinator, availableCapacity: { OfflineDownloadStore.minimumFreeBytes + 500 })
            let downloaded = OfflineDownloadRecord(id: "s:u:saved", item: MediaItem(id: "saved"), filePath: "", byteCount: 24 * 1024 * 1024 * 1024, serverID: "s", userID: "u", downloadedAt: .now)
            try files.persist(downloaded)
            var active = files.prepareDownloadRecord(item: MediaItem(id: "other"), serverID: "s", userID: "other", fileExtension: "mp4", status: .downloading(0), progress: 0)
            active.estimatedByteCount = 350
            try files.persist(active)
            let item = MediaItem(canDownload: true, id: "new", mediaSources: [MediaSource(id: "original", sizeBytes: 200)], officialRating: "G", type: .audio)
            let provider = FakeMediaProviderSession(capabilities: .init(supportsDownloads: true))
            provider.itemHandler = { _ in item }
            let url = try #require(URL(string: "https://example.invalid"))
            let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: .init(id: "u", name: "User", serverID: "s"), server: .init(id: "s", name: "Server", url: url), mediaProvider: provider)
            store.load(serverID: "s", userID: "u")

            await store.download(PlaybackRequest(item: item), session: session)
            #expect(coordinator.startedRecordIDs.isEmpty)
            #expect(store.errorMessage?.contains("Free up space") == true)

            // The server's reported length supersedes the estimate and bytes on
            // disk are already reflected in the volume's available capacity.
            store.downloadSessionCoordinator(coordinator, didUpdateActivity: DownloadActivity(phase: .downloading, receivedBytes: 50, expectedBytes: 400), recordID: active.id)
            store.downloadSessionCoordinator(coordinator, didUpdateActivity: DownloadActivity(phase: .downloading, receivedBytes: 100, expectedBytes: 400), recordID: active.id)
            await store.download(PlaybackRequest(item: item), session: session)
            let newRecord = try #require(files.record(forItemID: "new", serverID: "s", userID: "u"))
            #expect(coordinator.startedRecordIDs == [newRecord.id])
            #expect(newRecord.estimatedByteCount == 200)
            #expect(store.errorMessage == nil)
            #expect(files.record(forRecordID: downloaded.id) == downloaded)
        }

        @Test("disk-full errors retain native resume data and retry after freeing enough space")
        func retriesAfterDiskFull() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let files = OfflineDownloadFileStore(directory: directory)
            let coordinator = IntegrationDownloadCoordinator()
            var available = OfflineDownloadStore.minimumFreeBytes + 299
            let store = OfflineDownloadStore(fileStore: files, coordinator: coordinator, availableCapacity: { available })
            var record = files.prepareDownloadRecord(item: MediaItem(id: "item", type: .audio), serverID: "s", userID: "u", fileExtension: "mp3", status: .downloading(0.25), progress: 0.25)
            record.activity = DownloadActivity(phase: .downloading, receivedBytes: 100, expectedBytes: 400)
            try files.persist(record)
            store.load(serverID: "s", userID: "u")
            let url = try #require(URL(string: "https://example.invalid"))
            let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: .init(id: "u", name: "User", serverID: "s"), server: .init(id: "s", name: "Server", url: url))
            let error = NSError(domain: NSURLErrorDomain, code: URLError.cannotWriteToFile.rawValue, userInfo: [NSUnderlyingErrorKey: POSIXError(.ENOSPC)])
            let resumeData = Data("native resume data".utf8)

            store.downloadSessionCoordinator(coordinator, didFailWith: error, resumeData: resumeData, recordID: record.id)
            let failed = try #require(store.records.first)
            #expect(failed.status == .failed("This download ran out of storage space. Free up space on this device and try again."))
            #expect(failed.resumeData == resumeData)
            #expect(store.activeItemIDs.isEmpty)

            await store.resume(failed, session: session)
            #expect(coordinator.resumedRecordIDs.isEmpty)
            #expect(files.record(forRecordID: record.id)?.resumeData == resumeData)
            available += 1
            await store.resume(failed, session: session)
            #expect(coordinator.resumedRecordIDs == [record.id])
            #expect(store.errorMessage == nil)
        }
    #endif

    @Test("independent file handles serialize writes to the same canonical directory")
    func concurrentIndependentHandles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keeper = OfflineDownloadFileStore(directory: directory)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0 ..< 32 {
                group.addTask {
                    let files = OfflineDownloadFileStore(directory: directory.appendingPathComponent("."))
                    let item = MediaItem(id: String(index))
                    let record = OfflineDownloadRecord(id: "s:u:\(index)", item: item, filePath: "", byteCount: 0, serverID: "s", userID: "u", downloadedAt: Date())
                    try files.persist(record)
                }
            }
            try await group.waitForAll()
        }
        #expect(keeper.records(serverID: "s", userID: "u").count == 32)
    }

    @Test("unknown existing source remains usable automatically but cannot satisfy explicit source intent")
    func explicitOfflineSourceIdentity() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let item = MediaItem(id: "movie", type: .movie)
        _ = files.prepareDownloadRecord(item: item, serverID: "s", userID: "u", fileExtension: "mp4", status: .complete, progress: 1)
        let store = OfflineDownloadStore(fileStore: files, coordinator: IntegrationDownloadCoordinator())
        #expect(store.record(for: item, serverID: "s", userID: "u") != nil)
        #expect(store.record(for: item, serverID: "s", userID: "u", mediaSourceID: "extended") == nil)
        _ = files.prepareDownloadRecord(item: item, serverID: "s", userID: "u", fileExtension: "mp4", status: .complete, progress: 1, mediaSourceID: "extended")
        #expect(store.record(for: item, serverID: "s", userID: "u", mediaSourceID: "extended")?.mediaSourceID == "extended")
        #expect(store.record(for: item, serverID: "s", userID: "u", mediaSourceID: "theatrical") == nil)
    }

    @Test("download identity replacement offers the matching source checkpoint for explicit and refreshed references", arguments: [true, false])
    func sourceQualifiedProgressTransfer(explicitReplacement: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let progress = OfflinePlaybackProgressStore(directory: directory)
        let scope = AccountScope(serverID: "s", userID: "u")
        var original = MediaItem(id: "old", officialRating: "G", type: .movie)
        original.externalIDs = ["Tmdb": "123"]
        var replacement = original
        replacement.id = "new"
        let staged = directory.appendingPathComponent("staged.mp4")
        try Data("downloaded version".utf8).write(to: staged)
        let record = try files.persistDownloadedFile(staged, item: original, serverID: "s", userID: "u", fileExtension: "mp4", mediaSourceID: "cut")
        progress.checkpoint(itemID: "old", positionTicks: 99, scope: scope, item: original, mediaSourceID: "cut")
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in replacement }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(
            client: JellyfinClientFactory.makeClient(url: url),
            user: StoredUser(id: "u", name: "User", serverID: "s"),
            server: ServerConnection(id: "s", name: "Server", url: url),
            mediaProvider: provider
        )
        let store = OfflineDownloadStore(fileStore: files, coordinator: IntegrationDownloadCoordinator(), progressStore: progress)
        store.load(serverID: "s", userID: "u")
        if explicitReplacement {
            #expect(await store.replaceRemoteReference(record, with: replacement, session: session))
        } else {
            await store.refreshRemoteReferences(session: session)
        }
        let transfer = try #require(progress.transfers(scope: scope).first)
        #expect(transfer.itemID == "old")
        #expect(transfer.mediaSourceID == "cut")
        #expect(transfer.positionTicks == 99)
        #expect(transfer.replacement?.id == "new")
        #expect(progress.positionTicks(forItemID: "old", scope: scope) == nil)
    }

    @Test("unreadable current metadata cannot acknowledge or discard staged media")
    func unreadableMetadataRetainsStaging() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let record = files.prepareDownloadRecord(item: MediaItem(id: "item"), serverID: "s", userID: "u", fileExtension: "mp3", status: .downloading(0), progress: 0)
        let corrupt = Data("unreadable current metadata".utf8)
        try corrupt.write(to: directory.appendingPathComponent("records.json"))
        let staged = directory.appendingPathComponent("staged.mp3")
        let media = Data("complete media".utf8)
        try media.write(to: staged)
        let coordinator = IntegrationDownloadCoordinator()
        let store = OfflineDownloadStore(fileStore: files, coordinator: coordinator)
        #expect(await store.downloadSessionCoordinator(coordinator, finalizeDownloadedFileAt: staged, recordID: record.id, ownership: DownloadCompletionOwnership()) == false)
        #expect(try Data(contentsOf: staged) == media)
        #expect(try Data(contentsOf: directory.appendingPathComponent("records.json")) == corrupt)
        #expect(store.errorMessage != nil)
    }

    @Test("unreadable download metadata exposes retry, preserves a current snapshot, and never crosses accounts")
    func unreadableMetadataLoading() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let record = files.prepareDownloadRecord(item: MediaItem(id: "item"), serverID: "s", userID: "u", fileExtension: "mp3", status: .paused, progress: 0)
        let metadataURL = directory.appendingPathComponent("records.json")
        let original = try Data(contentsOf: metadataURL)
        let store = OfflineDownloadStore(fileStore: files, coordinator: IntegrationDownloadCoordinator())
        store.load(serverID: "s", userID: "u")
        #expect(store.loadState == .loaded)
        let unreadable = Data("unreadable metadata".utf8)
        try unreadable.write(to: metadataURL)
        store.load(serverID: "s", userID: "u")
        #expect(store.loadErrorMessage != nil)
        #expect(store.records.map(\.id) == [record.id])
        #expect(try Data(contentsOf: metadataURL) == unreadable)
        try original.write(to: metadataURL)
        store.load(serverID: "s", userID: "u")
        #expect(store.loadState == .loaded)
        #expect(store.loadErrorMessage == nil)
        try unreadable.write(to: metadataURL)
        store.load(serverID: "s", userID: "different-user")
        #expect(store.loadErrorMessage != nil)
        #expect(store.records.isEmpty)
    }

    @Test("a failed durable queue write or unsupported platform rejects the request without starting a transfer")
    func queueMetadataFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let coordinator = IntegrationDownloadCoordinator()
        coordinator.onCancel = { try? FileManager.default.createDirectory(at: directory.appendingPathComponent("records.json"), withIntermediateDirectories: false) }
        let item = MediaItem(canDownload: true, id: "item", officialRating: "G", type: .audio)
        let provider = FakeMediaProviderSession(capabilities: .init(supportsDownloads: true))
        provider.itemHandler = { _ in item }
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(
            client: JellyfinClientFactory.makeClient(url: url),
            user: .init(id: "u", name: "User", serverID: "s"),
            server: .init(id: "s", name: "Server", url: url),
            mediaProvider: provider
        )
        let store = OfflineDownloadStore(fileStore: files, coordinator: coordinator)
        store.load(serverID: "s", userID: "u")
        await store.download(PlaybackRequest(item: item), session: session)
        #expect(store.activeItemIDs.isEmpty)
        #expect(coordinator.startedRecordIDs.isEmpty)
        #expect(provider.downloadSourceCallCount == 0)
        if DownloadsAvailability.isSupported {
            #expect(store.errorMessage != nil)
            #expect(store.loadErrorMessage != nil)
        } else {
            #expect(store.errorMessage == nil)
            #expect(store.loadErrorMessage == nil)
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("records.json").path))
        }
    }

    @Test("pause and resume expose durable metadata failures without losing the current record", arguments: [true, false])
    func pauseResumeMetadataFailure(resuming: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let files = OfflineDownloadFileStore(directory: directory)
        let resumeData = Data("native resume data".utf8)
        let record = files.prepareDownloadRecord(item: MediaItem(id: "item", type: .audio), serverID: "s", userID: "u", fileExtension: "mp3", status: resuming ? .paused : .downloading(0.25), progress: 0.25, resumeData: resuming ? resumeData : nil)
        let metadataURL = directory.appendingPathComponent("records.json")
        let original = try Data(contentsOf: metadataURL)
        let coordinator = IntegrationDownloadCoordinator()
        coordinator.pauseResumeData = resumeData
        let store = OfflineDownloadStore(fileStore: files, coordinator: coordinator)
        store.load(serverID: "s", userID: "u")
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: .init(id: "u", name: "User", serverID: "s"), server: .init(id: "s", name: "Server", url: url))
        // The existing index stays readable, but atomic replacement cannot create
        // its temporary file. This exercises a write failure after successful reads.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        #expect(!FileManager.default.isWritableFile(atPath: directory.path))
        if resuming {
            await store.resume(record, session: session)
        } else {
            await store.pause(itemID: "item")
        }
        #expect(try Data(contentsOf: metadataURL) == original)
        #expect(store.errorMessage != nil)
        #expect(coordinator.resumedRecordIDs.isEmpty)
        #expect(store.records.first?.status == .paused)
        #expect(store.records.first?.resumeData == resumeData)
        #expect(store.activeItemIDs.isEmpty)
        store.load(serverID: "s", userID: "u")
        #expect(store.records.first?.status == .paused)
        #expect(store.records.first?.resumeData == resumeData)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let paused = try #require(store.records.first)
        await store.resume(paused, session: session)
        #expect(coordinator.resumedRecordIDs == [record.id])
        #expect(files.record(forRecordID: record.id)?.status == .downloading(0.25))
        #expect(files.record(forRecordID: record.id)?.resumeData == nil)
        #expect(store.records.first?.status == .downloading(0.25))
        #expect(store.errorMessage == nil)
        await store.resume(paused, session: session)
        #expect(coordinator.resumedRecordIDs == [record.id])
    }

    @Test("a stale native observation cannot overwrite finalized, deleted, or replaced metadata", arguments: ["finalized", "deleted", "replaced"])
    func staleObservationAfterDurableTransition(transition: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let independentlyConstructed = OfflineDownloadFileStore(directory: directory.appendingPathComponent("."))
        let original = files.prepareDownloadRecord(item: MediaItem(id: "item", type: .audio), serverID: "s", userID: "u", fileExtension: "mp3", status: .downloading(0.25), progress: 0.25)
        switch transition {
        case "finalized":
            let staged = directory.appendingPathComponent("staged.mp3")
            try Data("complete audio".utf8).write(to: staged)
            let finalized = try independentlyConstructed.finalizeDownloadedFile(staged, expected: original, ownership: DownloadCompletionOwnership())
            var completed = try #require(finalized)
            completed.remoteUnavailable = true
            #expect(try independentlyConstructed.updateExisting(completed, when: .complete))
        case "deleted":
            try independentlyConstructed.delete(original)
        default:
            _ = independentlyConstructed.prepareDownloadRecord(item: original.item, serverID: "s", userID: "u", fileExtension: "mp3", status: .queued, progress: 0, downloadedAt: original.downloadedAt.addingTimeInterval(1))
        }
        let metadataURL = directory.appendingPathComponent("records.json")
        let committed = try Data(contentsOf: metadataURL)
        var stale = original
        stale.status = .paused
        stale.resumeData = Data("stale resume data".utf8)
        #expect(try files.updateExisting(stale, when: .incomplete) == false)
        #expect(try Data(contentsOf: metadataURL) == committed)
        if transition == "finalized" {
            let completed = try #require(files.record(forRecordID: original.id))
            #expect(completed.status == .complete)
            #expect(completed.remoteUnavailable == true)
            #expect(files.localFileURL(for: completed) != nil)
        } else if transition == "deleted" {
            #expect(files.record(forRecordID: original.id) == nil)
        } else {
            #expect(files.record(forRecordID: original.id)?.downloadedAt != original.downloadedAt)
        }
    }

    @Test("completion cleanup is opt-in, scoped, and cannot delete a replacement")
    func completionCleanup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OfflineDownloadStore(fileStore: files, coordinator: IntegrationDownloadCoordinator(), defaults: defaults)
        let item = MediaItem(id: "same", name: "Media")
        func save(_ user: String) throws -> OfflineDownloadRecord {
            let source = directory.appendingPathComponent(UUID().uuidString)
            try Data("media".utf8).write(to: source)
            return try files.persistDownloadedFile(source, item: item, serverID: "s", userID: user, fileExtension: "mp3")
        }
        let original = try save("a")
        let other = try save("b")
        store.load(serverID: "s", userID: "b")
        store.deleteAfterCompletion(original)
        #expect(files.localFileURL(for: original) != nil)
        defaults.set(true, forKey: OfflineDownloadStore.deleteFinishedDefaultsKey)
        let replacement = try save("a")
        store.deleteAfterCompletion(original)
        #expect(files.localFileURL(for: replacement) != nil)
        store.delete(replacement, serverID: "s", userID: "b")
        #expect(files.localFileURL(for: replacement) != nil)
        store.deleteAfterCompletion(replacement)
        #expect(files.record(forRecordID: replacement.id) == nil)
        #expect(files.localFileURL(for: other) != nil)
        #expect(store.records.map(\.userID) == ["b"])
    }

    @Test("saved artwork survives store recreation and is removed with its download")
    func artworkPersistenceAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let record = files.prepareDownloadRecord(item: MediaItem(id: "art", name: "Artwork"), serverID: "s", userID: "u", fileExtension: "mp3", status: .complete, progress: 1)
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="))
        try files.persistArtwork(png, for: record)
        let reopened = OfflineDownloadFileStore(directory: directory)
        let url = try #require(reopened.localArtworkURL(for: record))
        #expect(try Data(contentsOf: url) == png)
        try reopened.delete(record)
        #expect(reopened.localArtworkURL(for: record) == nil)
        try files.persistArtwork(png, for: record)
        #expect(files.localArtworkURL(for: record) == nil, "A late fetch cannot recreate deleted artwork")
    }

    @Test("bulk deletion preserves unselected downloads and rejects wrong accounts")
    func selectiveDeletion() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let store = OfflineDownloadStore(fileStore: files, coordinator: IntegrationDownloadCoordinator())
        let records = ["a", "b", "c"].map { files.prepareDownloadRecord(item: MediaItem(id: $0, name: $0), serverID: "s", userID: "u", fileExtension: "mp3", status: .paused, progress: 0) }
        store.load(serverID: "s", userID: "u")
        store.delete(Array(records.prefix(2)), serverID: "s", userID: "wrong")
        #expect(store.records.count == 3)
        store.delete(Array(records.prefix(2)), serverID: "s", userID: "u")
        #expect(store.records.map(\.id) == [records[2].id])
    }

    @Test("background completion saves the originating account without replacing displayed records")
    func backgroundAccountIsolation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let coordinator = IntegrationDownloadCoordinator()
        let store = OfflineDownloadStore(fileStore: files, coordinator: coordinator)
        let item = MediaItem(id: "same-item", name: "Saved audio")
        let pending = files.prepareDownloadRecord(item: item, serverID: "server", userID: "a", fileExtension: "mp3", status: .downloading(0), progress: 0)
        _ = files.prepareDownloadRecord(item: item, serverID: "server", userID: "b", fileExtension: "mp3", status: .paused, progress: 0)
        store.load(serverID: "server", userID: "b")
        let staged = directory.appendingPathComponent("staged.mp3")
        try Data("audio".utf8).write(to: staged)
        _ = await store.downloadSessionCoordinator(coordinator, finalizeDownloadedFileAt: staged, recordID: pending.id, ownership: DownloadCompletionOwnership())
        #expect(files.record(forRecordID: pending.id)?.status == .complete)
        #expect(store.records.count == 1)
        #expect(store.records.first?.userID == "b")
        #expect(store.records.first?.status == .paused)
        store.load(serverID: "server", userID: "a")
        #expect(store.completedRecords(serverID: "server", userID: "a").count == 1)
    }

    @Test("byte counters survive checkpoints with unknown total and late deleted callbacks are ignored")
    func checkpointAndDeletedCallback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let coordinator = IntegrationDownloadCoordinator()
        let store = OfflineDownloadStore(fileStore: files, coordinator: coordinator)
        let record = files.prepareDownloadRecord(item: MediaItem(id: "item", name: "Media"), serverID: "s", userID: "u", fileExtension: "mp3", status: .downloading(0), progress: 0)
        store.load(serverID: "s", userID: "u")
        var activity = DownloadActivity()
        activity.recordTransfer(receivedBytes: 1024, expectedBytes: nil)
        store.downloadSessionCoordinator(coordinator, didUpdateActivity: activity, recordID: record.id)
        #expect(store.activities[record.id]?.receivedBytes == 1024)
        #expect(store.activities[record.id]?.progress == nil)
        #expect(files.record(forRecordID: record.id)?.activity?.receivedBytes == 1024)
        store.delete(record, serverID: "s", userID: "u")
        let staged = directory.appendingPathComponent("late.mp3")
        try Data("audio".utf8).write(to: staged)
        _ = await store.downloadSessionCoordinator(coordinator, finalizeDownloadedFileAt: staged, recordID: record.id, ownership: DownloadCompletionOwnership())
        #expect(files.record(forRecordID: record.id) == nil)
        #expect(store.completedRecords(serverID: "s", userID: "u").isEmpty)
    }

    @Test("completed records exclude missing and zero-length files")
    func validatesLocalFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let coordinator = IntegrationDownloadCoordinator()
        let store = OfflineDownloadStore(fileStore: files, coordinator: coordinator)
        _ = files.prepareDownloadRecord(item: MediaItem(id: "missing", name: "Missing"), serverID: "s", userID: "u", fileExtension: "mp3", status: .complete, progress: 1)
        let empty = directory.appendingPathComponent("empty.mp3")
        try Data().write(to: empty)
        _ = try files.persistDownloadedFile(empty, item: MediaItem(id: "empty", name: "Empty"), serverID: "s", userID: "u")
        store.load(serverID: "s", userID: "u")
        #expect(store.completedRecords(serverID: "s", userID: "u").isEmpty)
    }

    @Test("metadata persistence failure returns completed media to durable staging")
    func failedPersistencePreservesSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let staged = directory.appendingPathComponent("staged.mp3")
        let payload = Data("audio".utf8)
        try payload.write(to: staged)
        // The records path is a directory: the final atomic JSON write must fail.
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("records.json"), withIntermediateDirectories: true)
        #expect(throws: (any Error).self) {
            try files.persistDownloadedFile(staged, item: MediaItem(id: "item", name: "Media"), serverID: "s", userID: "u")
        }
        #expect(try Data(contentsOf: staged) == payload)
        #expect(files.record(forItemID: "item", serverID: "s", userID: "u") == nil)
    }

    @Test("background acknowledgement follows persistence and is consumed once")
    func completionAcknowledgement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let coordinator = IntegrationDownloadCoordinator()
        let store = OfflineDownloadStore(fileStore: files, coordinator: coordinator)
        let record = files.prepareDownloadRecord(item: MediaItem(id: "item", name: "Media"), serverID: "s", userID: "u", fileExtension: "mp3", status: .downloading(0), progress: 0)
        var acknowledgements = 0
        DownloadBackgroundEvents.shared.register {
            #expect(files.record(forRecordID: record.id)?.status == .complete)
            acknowledgements += 1
        }
        let staged = directory.appendingPathComponent("staged.mp3")
        try Data("audio".utf8).write(to: staged)
        _ = await store.downloadSessionCoordinator(coordinator, finalizeDownloadedFileAt: staged, recordID: record.id, ownership: DownloadCompletionOwnership())
        await store.downloadSessionCoordinatorDidFinishBackgroundEvents(coordinator)
        await store.downloadSessionCoordinatorDidFinishBackgroundEvents(coordinator)
        #expect(acknowledgements == 1)
    }

    @Test("deletion during asynchronous preparation cannot resurrect a completed download")
    func deletionDuringPreparation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let coordinator = IntegrationDownloadCoordinator()
        let gate = DownloadPreparationGate()
        let store = OfflineDownloadStore(fileStore: files, coordinator: coordinator, prepareFile: { _, _ in await gate.wait() })
        let record = files.prepareDownloadRecord(item: MediaItem(id: "item", name: "Media"), serverID: "s", userID: "u", fileExtension: "mp3", status: .downloading(0), progress: 0)
        store.load(serverID: "s", userID: "u")
        let staged = directory.appendingPathComponent("staged.mp3")
        try Data("audio".utf8).write(to: staged)
        let task = Task { await store.downloadSessionCoordinator(coordinator, finalizeDownloadedFileAt: staged, recordID: record.id, ownership: DownloadCompletionOwnership()) }
        while !(await gate.isWaiting) {
            await Task.yield()
        }
        store.delete(record, serverID: "s", userID: "u")
        await gate.finish()
        #expect(await task.value)
        #expect(files.record(forRecordID: record.id) == nil)
        #expect(store.records.isEmpty)
    }

    @Test("canceling a popped completion before its record read cannot fail the replacement")
    func replacementBeforeCompletionRecordRead() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let staging = directory.appendingPathComponent("Staging")
        let coordinator = DownloadSessionCoordinator(stagingDirectory: staging)
        let gate = DownloadPreparationGate()
        let store = OfflineDownloadStore(fileStore: files, coordinator: coordinator, readCompletionRecord: { id, files in
            await gate.wait()
            let current = try await DownloadFilePreparation.shared.record(id: id, in: files)
            await gate.didRead(current?.downloadedAt)
            return current
        })
        let original = files.prepareDownloadRecord(item: MediaItem(id: "item", type: .audio), serverID: "s", userID: "u", fileExtension: "mp3", status: .downloading(0), progress: 0)
        store.load(serverID: "s", userID: "u")
        let handler = ForwardingCompletionTestHandler(store: store)
        coordinator.setEventHandler(handler)
        let source = directory.appendingPathComponent("CFNetworkDownload.tmp")
        try Data("old generation".utf8).write(to: source)
        let task = try URLSession.shared.downloadTask(with: #require(URL(string: "https://example.invalid/media")))
        task.taskDescription = original.id
        // Exercise the actual coordinator's stage, pop and ownership registration.
        // This synthetic task is never resumed and makes no network request.
        coordinator.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: source)
        let readDeadline = ContinuousClock.now + .seconds(5)
        while !(await gate.isWaiting), ContinuousClock.now < readDeadline {
            await Task.yield()
        }
        guard await gate.isWaiting else {
            await gate.finish()
            Issue.record("Completion never reached the suspended record read")
            return
        }
        let ownership = try #require(handler.ownership)
        #expect(ownership.isCurrent)
        store.delete(original, serverID: "s", userID: "u")
        #expect(!ownership.isCurrent)
        let replacement = files.prepareDownloadRecord(item: original.item, serverID: "s", userID: "u", fileExtension: "mp3", status: .queued, progress: 0, downloadedAt: original.downloadedAt.addingTimeInterval(1))
        store.load(serverID: "s", userID: "u")
        let committed = try Data(contentsOf: directory.appendingPathComponent("records.json"))
        await gate.finish()
        let completionDeadline = ContinuousClock.now + .seconds(5)
        while !handler.didFinish, ContinuousClock.now < completionDeadline {
            await Task.yield()
        }
        #expect(handler.didFinish)
        #expect(handler.acknowledged)
        #expect(await gate.readGeneration == replacement.downloadedAt)
        #expect(files.record(forRecordID: replacement.id) == replacement)
        #expect(store.records.first == replacement)
        #expect(store.errorMessage == nil)
        #expect(try Data(contentsOf: directory.appendingPathComponent("records.json")) == committed)
        #expect(try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test("retired completion ownership cannot finalize or fail a matching replacement", arguments: [true, false])
    func retiredCompletionCannotCommit(finalizing: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let replacement = files.prepareDownloadRecord(item: MediaItem(id: "item", type: .audio), serverID: "s", userID: "u", fileExtension: "mp3", status: .queued, progress: 0)
        let ownership = DownloadCompletionOwnership()
        ownership.invalidate()
        let staged = directory.appendingPathComponent("old.mp3")
        let payload = Data("old generation".utf8)
        try payload.write(to: staged)
        let committed = try Data(contentsOf: directory.appendingPathComponent("records.json"))
        let result: OfflineDownloadRecord?
        if finalizing {
            result = try files.finalizeDownloadedFile(staged, expected: replacement, ownership: ownership)
        } else {
            result = try files.failFinalization(expected: replacement, ownership: ownership, message: "stale failure")
        }
        #expect(result == nil)
        #expect(files.record(forRecordID: replacement.id) == replacement)
        #expect(try Data(contentsOf: staged) == payload)
        #expect(try Data(contentsOf: directory.appendingPathComponent("records.json")) == committed)
    }

    @Test("finalization preserves conversion identity and remote metadata for offline projection", arguments: [DownloadActivity.SourceOperation.original, .remuxed, .transcoded])
    func finalizationPreservesSourceMetadata(operation: DownloadActivity.SourceOperation) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let coordinator = IntegrationDownloadCoordinator()
        let source = MediaSource(id: "alternate", mediaStreams: [MediaStreamInfo(index: 2, type: .audio), MediaStreamInfo(index: 9, type: .audio), MediaStreamInfo(index: 11, type: .subtitle)], defaultAudioStreamIndex: 2, defaultSubtitleStreamIndex: 11, runTimeTicks: 40_000_000)
        let item = MediaItem(id: "item", mediaSources: [source], runTimeTicks: 40_000_000, type: .audio)
        var record = files.prepareDownloadRecord(item: item, serverID: "s", userID: "u", fileExtension: "mp3", status: .downloading(0.5), progress: 0.5, mediaSourceID: "alternate")
        record.activity = DownloadActivity(phase: .saving, receivedBytes: 6, sourceOperation: operation)
        record.remoteReference = MediaReference(item: item, scope: AccountScope(serverID: "s", userID: "u"))
        record.remoteUnavailable = true
        try files.persist(record)
        let store = OfflineDownloadStore(fileStore: files, coordinator: coordinator)
        store.load(serverID: "s", userID: "u")
        let staged = directory.appendingPathComponent("staged.mp3")
        let payload = Data("completed media".utf8)
        try payload.write(to: staged)
        #expect(await store.downloadSessionCoordinator(coordinator, finalizeDownloadedFileAt: staged, recordID: record.id, ownership: DownloadCompletionOwnership()))
        let saved = try files.readRecord(forRecordID: record.id)
        let completed = try #require(saved)
        #expect(completed.status == .complete)
        #expect(completed.downloadedAt == record.downloadedAt)
        #expect(completed.mediaSourceID == "alternate")
        #expect(completed.activity?.sourceOperation == operation)
        #expect(completed.activity?.phase == .complete)
        #expect(completed.activity?.receivedBytes == Int64(payload.count))
        #expect(completed.remoteReference == record.remoteReference)
        #expect(completed.remoteUnavailable == true)
        #expect(completed.playbackItem.runTimeTicks == 40_000_000)
        #expect(completed.playbackItem.mediaSources.first?.mediaStreams.count == (operation == .original ? 3 : 0))
        #expect(files.localFileURL(for: completed) != nil)
    }

    @Test("a late Pause callback cannot discard already received staged bytes")
    func pauseDuringPreparationCompletesReceivedFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let coordinator = IntegrationDownloadCoordinator()
        let gate = DownloadPreparationGate()
        let store = OfflineDownloadStore(fileStore: files, coordinator: coordinator, prepareFile: { _, _ in await gate.wait() })
        let record = files.prepareDownloadRecord(item: MediaItem(id: "item", name: "Media"), serverID: "s", userID: "u", fileExtension: "mp3", status: .downloading(0), progress: 0)
        store.load(serverID: "s", userID: "u")
        let staged = directory.appendingPathComponent("staged.mp3")
        try Data("audio".utf8).write(to: staged)
        let task = Task { await store.downloadSessionCoordinator(coordinator, finalizeDownloadedFileAt: staged, recordID: record.id, ownership: DownloadCompletionOwnership()) }
        while !(await gate.isWaiting) {
            await Task.yield()
        }
        await store.pause(itemID: "item")
        #expect(files.record(forRecordID: record.id)?.status == .paused)
        await gate.finish()
        #expect(await task.value)
        let complete = try #require(files.record(forRecordID: record.id))
        #expect(complete.status == .complete)
        #expect(files.localFileURL(for: complete) != nil)
    }
}

private final class IntegrationDownloadCoordinator: DownloadSessionCoordinating {
    var onCancel: (() -> Void)?
    var pauseResumeData: Data?
    private(set) var startedRecordIDs: [String] = []
    private(set) var resumedRecordIDs: [String] = []
    func setEventHandler(_ eventHandler: DownloadSessionCoordinatorEventHandler?) {}
    func startDownload(from url: URL, recordID: String) {
        startedRecordIDs.append(recordID)
    }

    func resumeDownload(with resumeData: Data, recordID: String) {
        resumedRecordIDs.append(recordID)
    }

    func pause(recordID: String, completion: @escaping (Data?) -> Void) {
        completion(pauseResumeData)
    }

    func cancel(recordID: String) {
        onCancel?()
    }

    func reconnectActiveTasks() {}
}

private actor DownloadPreparationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false
    private(set) var readGeneration: Date?
    var isWaiting: Bool {
        continuation != nil
    }

    func wait() async {
        guard !finished else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func didRead(_ generation: Date?) {
        readGeneration = generation
    }

    func finish() {
        finished = true
        continuation?.resume(); continuation = nil
    }
}

@MainActor
private final class ForwardingCompletionTestHandler: DownloadSessionCoordinatorEventHandler {
    let store: OfflineDownloadStore
    private(set) var ownership: DownloadCompletionOwnership?
    private(set) var didFinish = false
    private(set) var acknowledged = false

    init(store: OfflineDownloadStore) {
        self.store = store
    }

    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, finalizeDownloadedFileAt location: URL, recordID: String, ownership: DownloadCompletionOwnership) async -> Bool {
        self.ownership = ownership
        acknowledged = await store.downloadSessionCoordinator(coordinator, finalizeDownloadedFileAt: location, recordID: recordID, ownership: ownership)
        didFinish = true
        return acknowledged
    }
}
