import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("Download store integration")
struct DownloadStoreIntegrationTests {
    @Test("background completion saves the originating account without replacing displayed records")
    func backgroundAccountIsolation() throws {
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
        store.downloadSessionCoordinator(coordinator, didFinishDownloadingTo: staged, recordID: pending.id)
        #expect(files.record(forRecordID: pending.id)?.status == .complete)
        #expect(store.records.count == 1)
        #expect(store.records.first?.userID == "b")
        #expect(store.records.first?.status == .paused)
        store.load(serverID: "server", userID: "a")
        #expect(store.completedRecords(serverID: "server", userID: "a").count == 1)
    }

    @Test("byte counters survive checkpoints with unknown total and late deleted callbacks are ignored")
    func checkpointAndDeletedCallback() throws {
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
        store.downloadSessionCoordinator(coordinator, didFinishDownloadingTo: staged, recordID: record.id)
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
        store.downloadSessionCoordinator(coordinator, didFinishDownloadingTo: staged, recordID: record.id)
        await store.downloadSessionCoordinatorDidFinishBackgroundEvents(coordinator)
        await store.downloadSessionCoordinatorDidFinishBackgroundEvents(coordinator)
        #expect(acknowledgements == 1)
    }
}

private final class IntegrationDownloadCoordinator: DownloadSessionCoordinating {
    func setEventHandler(_ eventHandler: DownloadSessionCoordinatorEventHandler?) {}
    func startDownload(from url: URL, recordID: String) {}
    func resumeDownload(with resumeData: Data, recordID: String) {}
    func pause(recordID: String, completion: @escaping (Data?) -> Void) {
        completion(nil)
    }

    func cancel(recordID: String) {}
    func reconnectActiveTasks() {}
}
