import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@Suite("Offline downloads")
struct OfflineDownloadTests {
    @Test("offers downloads for any server-downloadable item")
    func gatesDownloadsOnlyByServerFlag() {
        let playable = MediaItem(
            canDownload: true,
            mediaSources: [
                MediaSource(
                    container: "mp4",
                    mediaStreams: [
                        MediaStreamInfo(codec: "h264", index: 0, type: .video),
                        MediaStreamInfo(codec: "aac", index: 1, type: .audio),
                    ],
                    videoType: .videoFile
                ),
            ]
        )
        let unplayableContainer = MediaItem(
            canDownload: true,
            mediaSources: [
                MediaSource(
                    container: "mkv",
                    mediaStreams: [
                        MediaStreamInfo(codec: "h264", index: 0, type: .video),
                        MediaStreamInfo(codec: "aac", index: 1, type: .audio),
                    ],
                    videoType: .videoFile
                ),
            ]
        )
        let serverDenied = MediaItem(
            canDownload: false,
            mediaSources: [
                MediaSource(
                    container: "mp4",
                    mediaStreams: [
                        MediaStreamInfo(codec: "h264", index: 0, type: .video),
                        MediaStreamInfo(codec: "aac", index: 1, type: .audio),
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
        let item = MediaItem(
            canDownload: true,
            id: "item-1",
            mediaSources: [
                MediaSource(
                    container: "mp4",
                    mediaStreams: [
                        MediaStreamInfo(codec: "h264", index: 0, type: .video),
                        MediaStreamInfo(codec: "aac", index: 1, type: .audio),
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
        let item = MediaItem(
            canDownload: true,
            id: "item-1",
            mediaSources: [
                MediaSource(
                    container: "mkv",
                    id: "source-1",
                    mediaStreams: [
                        MediaStreamInfo(codec: "hevc", index: 0, type: .video),
                        MediaStreamInfo(codec: "flac", index: 1, type: .audio),
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
        let item = MediaItem(id: "item-1", name: "Office Space")
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

    @Test("file store deletes downloaded media for only the requested account")
    func fileStoreDeletesRecordsForOnlyRequestedAccount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = OfflineDownloadFileStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let accountSource = directory.appendingPathComponent("account-source.mp4")
        let otherSource = directory.appendingPathComponent("other-source.mp4")
        try Data("video-a".utf8).write(to: accountSource)
        try Data("video-b".utf8).write(to: otherSource)

        let accountRecord = try store.persistDownloadedFile(
            accountSource,
            item: MediaItem(id: "item-1", name: "Office Space"),
            serverID: "server-1",
            userID: "user-1",
            downloadedAt: Date(timeIntervalSince1970: 100)
        )
        let otherRecord = try store.persistDownloadedFile(
            otherSource,
            item: MediaItem(id: "item-1", name: "Office Space"),
            serverID: "server-2",
            userID: "user-2",
            downloadedAt: Date(timeIntervalSince1970: 200)
        )

        try store.deleteRecords(serverID: "server-1", userID: "user-1")

        #expect(store.records(serverID: "server-1", userID: "user-1").isEmpty)
        #expect(store.localFileURL(for: accountRecord) == nil)
        #expect(store.record(forItemID: "item-1", serverID: "server-2", userID: "user-2") == otherRecord)
        #expect(store.localFileURL(for: otherRecord) != nil)
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
            item: MediaItem(id: "item-1", name: "Office Space"),
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
            item: MediaItem(id: "item-1", name: "Office Space"),
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
            item: MediaItem(id: "item-1", name: "Office Space"),
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

    @MainActor
    @Test("delete all cancels and clears only the loaded account")
    func storeDeleteAllCancelsAndRemovesOnlyLoadedAccount() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = OfflineDownloadFileStore(directory: directory)
        let coordinator = FakeDownloadSessionCoordinator()
        let store = OfflineDownloadStore(fileStore: fileStore, coordinator: coordinator)
        let activeRecord = fileStore.prepareDownloadRecord(
            item: MediaItem(id: "item-1", name: "Office Space"),
            serverID: "server-1",
            userID: "user-1",
            fileExtension: "mp4",
            status: .downloading(0.5),
            progress: 0.5
        )
        let pausedRecord = fileStore.prepareDownloadRecord(
            item: MediaItem(id: "item-2", name: "The Big Lebowski"),
            serverID: "server-1",
            userID: "user-1",
            fileExtension: "mp4",
            status: .paused,
            progress: 0.5,
            resumeData: Data("resume".utf8)
        )
        let otherRecord = fileStore.prepareDownloadRecord(
            item: MediaItem(id: "item-1", name: "Office Space"),
            serverID: "server-2",
            userID: "user-2",
            fileExtension: "mp4",
            status: .queued,
            progress: 0
        )
        store.load(serverID: "server-1", userID: "user-1")

        store.deleteAll(serverID: "server-1", userID: "user-1")

        #expect(Set(coordinator.cancelledRecordIDs) == [activeRecord.id, pausedRecord.id])
        #expect(store.records.isEmpty)
        #expect(store.activeItemIDs.isEmpty)
        #expect(fileStore.records(serverID: "server-1", userID: "user-1").isEmpty)
        #expect(fileStore.record(forItemID: "item-1", serverID: "server-2", userID: "user-2") == otherRecord)
    }

    @MainActor
    @Test("download store respects provider download capability")
    func storeSkipsDownloadWhenProviderDisablesDownloads() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = OfflineDownloadFileStore(directory: directory)
        let coordinator = FakeDownloadSessionCoordinator()
        let store = OfflineDownloadStore(fileStore: fileStore, coordinator: coordinator)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities(supportsDownloads: false))
        let session = SessionStore.makeTestSession(mediaProvider: provider)
        let item = MediaItem(
            canDownload: true,
            id: "item-1",
            mediaSources: [
                MediaSource(container: "mp4", videoType: .videoFile),
            ]
        )

        await store.download(item, session: session)

        #expect(provider.downloadSourceCallCount == 0)
        #expect(coordinator.startedRecordIDs.isEmpty)
        #expect(store.records.isEmpty)
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
        makeTestSession()
    }

    static func makeTestSession(mediaProvider: (any MediaProviderSession)? = nil) -> SessionStore {
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
            server: ServerConnection(id: "server-1", name: "Server", url: URL(string: "https://example.com")!),
            mediaProvider: mediaProvider
        )
    }
}
