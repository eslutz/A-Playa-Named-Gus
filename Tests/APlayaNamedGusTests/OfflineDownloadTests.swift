import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@Suite("Offline downloads")
struct OfflineDownloadTests {
    @Test("offers downloads for any server-downloadable item")
    func gatesDownloadsOnlyByServerFlag() {
        let playable = BaseItemDto(
            canDownload: true,
            mediaSources: [
                MediaSourceInfo(
                    container: "mp4",
                    mediaStreams: [
                        MediaStream(codec: "h264", index: 0, type: .video),
                        MediaStream(codec: "aac", index: 1, type: .audio),
                    ],
                    videoType: .videoFile
                ),
            ]
        )
        let unplayableContainer = BaseItemDto(
            canDownload: true,
            mediaSources: [
                MediaSourceInfo(
                    container: "mkv",
                    mediaStreams: [
                        MediaStream(codec: "h264", index: 0, type: .video),
                        MediaStream(codec: "aac", index: 1, type: .audio),
                    ],
                    videoType: .videoFile
                ),
            ]
        )
        let serverDenied = BaseItemDto(
            canDownload: false,
            mediaSources: [
                MediaSourceInfo(
                    container: "mp4",
                    mediaStreams: [
                        MediaStream(codec: "h264", index: 0, type: .video),
                        MediaStream(codec: "aac", index: 1, type: .audio),
                    ],
                    videoType: .videoFile
                ),
            ]
        )

        #expect(OfflineDownloadEligibility.canDownload(playable))
        #expect(OfflineDownloadEligibility.canDownload(unplayableContainer))
        #expect(!OfflineDownloadEligibility.canDownload(serverDenied))
    }

    @Test("download source resolver chooses original download for AVPlayer-native sources")
    func sourceResolverChoosesDirectDownloadForPlayableSource() throws {
        let item = BaseItemDto(
            canDownload: true,
            id: "item-1",
            mediaSources: [
                MediaSourceInfo(
                    container: "mp4",
                    mediaStreams: [
                        MediaStream(codec: "h264", index: 0, type: .video),
                        MediaStream(codec: "aac", index: 1, type: .audio),
                    ],
                    videoType: .videoFile
                ),
            ]
        )

        let source = try DownloadSourceResolver.localSource(for: item)

        #expect(source.kind == DownloadSourceResolver.SourceKind.original)
        #expect(source.fileExtension == "mp4")
        #expect(source.request.id == "GetDownload")
    }

    @Test("download source resolver builds MP4 transcode request for incompatible sources")
    func sourceResolverBuildsTranscodeRequestForIncompatibleSource() throws {
        let item = BaseItemDto(
            canDownload: true,
            id: "item-1",
            mediaSources: [
                MediaSourceInfo(
                    container: "mkv",
                    id: "source-1",
                    mediaStreams: [
                        MediaStream(codec: "hevc", index: 0, type: .video),
                        MediaStream(codec: "flac", index: 1, type: .audio),
                    ],
                    videoType: .videoFile
                ),
            ]
        )

        let source = try DownloadSourceResolver.localSource(for: item)
        let query = source.request.query ?? []

        #expect(source.kind == DownloadSourceResolver.SourceKind.transcoded)
        #expect(source.fileExtension == "mp4")
        #expect(source.request.id == "GetVideoStreamByContainer")
        #expect(source.request.url?.path == "/Videos/item-1/stream.mp4")
        #expect(query.value(for: "mediaSourceId") == "source-1")
        #expect(query.value(for: "videoCodec") == "h264")
        #expect(query.value(for: "audioCodec") == "aac")
        #expect(query.value(for: "maxVideoBitDepth") == "8")
        #expect(query.value(for: "maxAudioChannels") == "2")
        #expect(query.value(for: "deviceId") == DeviceIdentity.deviceID)
    }

    @Test("download records decode existing completed records without status fields")
    func recordDecodesLegacyCompletedRecord() throws {
        let json = """
        {
          "id": "server-1:user-1:item-1",
          "item": { "Id": "item-1", "Name": "Office Space" },
          "filePath": "/tmp/item-1.mp4",
          "byteCount": 5,
          "serverID": "server-1",
          "userID": "user-1",
          "downloadedAt": "1970-01-01T00:01:40Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let record = try decoder.decode(OfflineDownloadRecord.self, from: Data(json.utf8))

        #expect(record.status == .complete)
        #expect(record.progress == 1)
        #expect(record.resumeData == nil)
    }

    @Test("file store persists resolves and deletes downloaded media records")
    func fileStorePersistsResolvesAndDeletesRecords() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = OfflineDownloadFileStore(directory: directory)
        let item = BaseItemDto(id: "item-1", name: "Office Space")
        let source = directory.appendingPathComponent("source.mp4")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: source)

        let record = try store.persistDownloadedFile(
            source,
            item: item,
            serverID: "server-1",
            userID: "user-1",
            downloadedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(record.item.id == "item-1")
        #expect(record.byteCount == 5)
        #expect(record.serverID == "server-1")
        #expect(record.userID == "user-1")
        #expect(store.record(forItemID: "item-1", serverID: "server-1", userID: "user-1") == record)
        #expect(store.localFileURL(for: record) != nil)
        #expect(store.totalByteCount(serverID: "server-1", userID: "user-1") == 5)

        try store.delete(record)

        #expect(store.record(forItemID: "item-1", serverID: "server-1", userID: "user-1") == nil)
        #expect(store.localFileURL(for: record) == nil)
        #expect(store.totalByteCount(serverID: "server-1", userID: "user-1") == 0)
    }

    @Test("default application support location migrates legacy download records")
    func defaultLocationMigratesLegacyDownloadRecords() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyDirectory = baseDirectory
            .appendingPathComponent("Gus", isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
        let migratedDirectory = baseDirectory
            .appendingPathComponent("A Playa Named Gus", isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
        let legacyStore = OfflineDownloadFileStore(directory: legacyDirectory)
        let source = legacyDirectory.appendingPathComponent("source.mp4")
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: source)
        let record = try legacyStore.persistDownloadedFile(
            source,
            item: BaseItemDto(id: "item-1", name: "Office Space"),
            serverID: "server-1",
            userID: "user-1",
            downloadedAt: Date(timeIntervalSince1970: 100)
        )

        let store = OfflineDownloadFileStore(applicationSupportDirectory: baseDirectory)

        #expect(store.record(forItemID: "item-1", serverID: "server-1", userID: "user-1")?.id == record.id)
        #expect(FileManager.default.fileExists(atPath: migratedDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: legacyDirectory.path))
    }

    @MainActor
    @Test("pause stores resume data and resume clears it")
    func storePauseResumeRoundTrip() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = OfflineDownloadFileStore(directory: directory)
        let coordinator = FakeDownloadSessionCoordinator()
        let store = OfflineDownloadStore(fileStore: fileStore, coordinator: coordinator)
        let record = fileStore.prepareDownloadRecord(
            item: BaseItemDto(id: "item-1", name: "Office Space"),
            serverID: "server-1",
            userID: "user-1",
            fileExtension: "mp4",
            status: .downloading(0.4),
            progress: 0.4
        )
        store.load(serverID: "server-1", userID: "user-1")

        coordinator.pauseResumeData = Data("resume".utf8)
        await store.pause(itemID: "item-1")

        #expect(coordinator.pausedRecordIDs == [record.id])
        #expect(store.records.first?.status == .paused)
        #expect(store.records.first?.resumeData == Data("resume".utf8))

        await store.resume(itemID: "item-1", session: .testSession)

        #expect(coordinator.resumedRecordIDs == [record.id])
        #expect(store.records.first?.status == .downloading(0))
        #expect(store.records.first?.resumeData == nil)
    }

    @MainActor
    @Test("delete cancels active or paused task and clears record")
    func storeDeleteCancelsAndRemovesRecord() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = OfflineDownloadFileStore(directory: directory)
        let coordinator = FakeDownloadSessionCoordinator()
        let store = OfflineDownloadStore(fileStore: fileStore, coordinator: coordinator)
        let record = fileStore.prepareDownloadRecord(
            item: BaseItemDto(id: "item-1", name: "Office Space"),
            serverID: "server-1",
            userID: "user-1",
            fileExtension: "mp4",
            status: .paused,
            progress: 0,
            resumeData: Data("resume".utf8)
        )
        store.load(serverID: "server-1", userID: "user-1")

        store.delete(record, serverID: "server-1", userID: "user-1")

        #expect(coordinator.cancelledRecordIDs == [record.id])
        #expect(fileStore.record(forItemID: "item-1", serverID: "server-1", userID: "user-1") == nil)
    }
}

private extension Array where Element == (String, String?) {
    func value(for key: String) -> String? {
        first { $0.0 == key }?.1 ?? nil
    }
}

private final class FakeDownloadSessionCoordinator: DownloadSessionCoordinating {
    weak var eventHandler: DownloadSessionCoordinatorEventHandler?
    var pauseResumeData: Data?
    var startedRecordIDs: [String] = []
    var resumedRecordIDs: [String] = []
    var pausedRecordIDs: [String] = []
    var cancelledRecordIDs: [String] = []

    func setEventHandler(_ eventHandler: DownloadSessionCoordinatorEventHandler?) {
        self.eventHandler = eventHandler
    }

    func startDownload(from url: URL, recordID: String) {
        startedRecordIDs.append(recordID)
    }

    func resumeDownload(with resumeData: Data, recordID: String) {
        resumedRecordIDs.append(recordID)
    }

    func pause(recordID: String, completion: @escaping (Data?) -> Void) {
        pausedRecordIDs.append(recordID)
        completion(pauseResumeData)
    }

    func cancel(recordID: String) {
        cancelledRecordIDs.append(recordID)
    }

    func reconnectActiveTasks() {}
}

@MainActor
private extension SessionStore {
    static var testSession: SessionStore {
        SessionStore(
            client: JellyfinClient(
                configuration: .init(
                    url: URL(string: "https://example.com")!,
                    accessToken: "token",
                    client: "Gus",
                    deviceName: "Tests",
                    deviceID: "device",
                    version: "1"
                )
            ),
            user: StoredUser(id: "user-1", name: "User", serverID: "server-1"),
            server: ServerConnection(id: "server-1", name: "Server", url: URL(string: "https://example.com")!)
        )
    }
}
