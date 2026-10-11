import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@Suite("Offline downloads")
struct OfflineDownloadTests {
    @Test("HEVC normalization changes only the sample tag and preserves encoded media")
    func normalizerPreservesMediaBytes() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let original = Self.containerFixture(tag: "hev1")
        try original.write(to: file)
        try OfflineMP4Compatibility.normalizeHEVCTag(in: file)
        #expect(try Data(contentsOf: file) == Self.containerFixture(tag: "hvc1"))
        try OfflineMP4Compatibility.normalizeHEVCTag(in: file)
        #expect(try Data(contentsOf: file) == Self.containerFixture(tag: "hvc1"))
    }

    @Test("malformed HEVC configuration is rejected before changing the file")
    func normalizerRejectsIncompleteConfiguration() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let original = Self.containerFixture(tag: "hev1", validConfiguration: false)
        try original.write(to: file)
        #expect(throws: CocoaError.self) { try OfflineMP4Compatibility.normalizeHEVCTag(in: file) }
        #expect(try Data(contentsOf: file) == original)
    }

    private static func containerFixture(tag: String, validConfiguration: Bool = true) -> Data {
        func box(_ tag: String, _ payload: Data) -> Data {
            let size = UInt32(payload.count + 8)
            return Data([UInt8((size >> 24) & 255), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)]) + Data(tag.utf8) + payload
        }
        var configuration = Data(repeating: 0, count: 23)
        configuration[0] = validConfiguration ? 1 : 0
        configuration[22] = 3
        for type: UInt8 in [32, 33, 34] {
            configuration += Data([type, 0, 1, 0, 1, type << 1])
        }
        let entry = box(tag, Data(repeating: 0, count: 78) + box("hvcC", configuration))
        let stsd = box("stsd", Data([0, 0, 0, 0, 0, 0, 0, 1]) + entry)
        return box("ftyp", Data("isom".utf8)) + box("moov", box("trak", box("mdia", box("minf", box("stbl", stsd))))) + box("mdat", Data("hev1 media payload untouched".utf8))
    }

    @MainActor
    @Test("completed downloads survive URLSession temporary-file cleanup before the main actor saves them")
    func completedDownloadSurvivesDelegateReturn() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let temporaryFile = directory.appendingPathComponent("CFNetworkDownload.tmp")
        let content = Data("downloaded media".utf8)
        try content.write(to: temporaryFile)

        let fileStore = OfflineDownloadFileStore(directory: directory.appendingPathComponent("Downloads"))
        let coordinator = DownloadSessionCoordinator()
        let handler = DownloadCompletionTestHandler()
        coordinator.setEventHandler(handler)
        let requestURL = try #require(URL(string: "https://example.com/media"))
        let task = URLSession.shared.downloadTask(with: requestURL)
        task.taskDescription = "record-1"

        let record: OfflineDownloadRecord = try await withCheckedThrowingContinuation { continuation in
            handler.onFinish = { location in
                continuation.resume(with: Result {
                    try fileStore.persistDownloadedFile(
                        location,
                        item: MediaItem(id: "item-1", name: "Episode"),
                        serverID: "server-1",
                        userID: "user-1",
                        fileExtension: "mp4"
                    )
                })
            }
            handler.onFailure = { continuation.resume(throwing: $0) }
            coordinator.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: temporaryFile)
            // Model URLSession reclaiming its temporary URL immediately after the
            // delegate returns, before the main actor has run the completion task.
            try? FileManager.default.removeItem(at: temporaryFile)
        }

        #expect(record.status == .complete)
        #expect(record.byteCount == Int64(content.count))
        #expect(try Data(contentsOf: URL(fileURLWithPath: record.filePath)) == content)
    }

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

    @Test("download source resolver copies HEVC video while converting incompatible audio")
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

        let source = try DownloadSourceResolver.localSource(for: item, capabilities: Self.modernCapabilities)
        let query = source.request.query ?? []

        #expect(source.kind == DownloadSourceResolver.SourceKind.transcoded)
        #expect(source.fileExtension == "mp4")
        #expect(source.request.id == "GetVideoStreamByContainer")
        #expect(source.request.url?.path == "/Videos/item-1/stream.mp4")
        #expect(query.value(for: "mediaSourceId") == "source-1")
        #expect(query.value(for: "videoCodec") == "hevc")
        #expect(query.value(for: "audioCodec") == "aac")
        #expect(query.value(for: "maxVideoBitDepth") == "10")
        #expect(query.value(for: "maxAudioChannels") == "8")
        #expect(query.value(for: "allowVideoStreamCopy") == "true")
        #expect(query.value(for: "allowAudioStreamCopy") == "false")
        #expect(query.value(for: "deviceId") == DeviceIdentity.deviceID)
    }

    private static let modernCapabilities = DevicePlaybackCapabilities(supportsHEVCDecode: true, supportsAV1Decode: true, supportsHDRPlayback: true)

    @Test("HEVC Main 10 and surround AAC in MKV remux without encoding or downscaling")
    func compatibleMKVRemuxes() throws {
        let source = try DownloadSourceResolver.convertedSource(
            itemID: "episode",
            source: MediaSource(container: "mkv", id: "source", mediaStreams: [
                MediaStreamInfo(codec: "hevc", index: 0, profile: "Main 10", type: .video, bitDepth: 10, width: 1920, height: 1080),
                MediaStreamInfo(codec: "aac", index: 1, type: .audio, channels: 6),
            ]),
            capabilities: Self.modernCapabilities
        )
        let query = source.request.query ?? []
        #expect(source.kind == .remuxed)
        #expect(source.fileExtension == "mp4")
        #expect(query.value(for: "allowVideoStreamCopy") == "true")
        #expect(query.value(for: "allowAudioStreamCopy") == "true")
        #expect(query.value(for: "videoCodec") == "hevc")
        #expect(query.value(for: "audioCodec") == "aac")
        #expect(query.value(for: "maxWidth") == "1920")
        #expect(query.value(for: "maxHeight") == "1080")
        #expect(query.value(for: "maxAudioChannels") == "8")
        #expect(query.value(for: "subtitleStreamIndex") == "-1")
    }

    @Test("unsupported video and audio encode to H264 and AAC")
    func incompatibleStreamsEncode() throws {
        let source = try DownloadSourceResolver.convertedSource(itemID: "episode", source: MediaSource(id: "source", mediaStreams: [
            MediaStreamInfo(codec: "vp9", type: .video, width: 1920, height: 1080),
            MediaStreamInfo(codec: "opus", type: .audio),
        ]), capabilities: Self.modernCapabilities)
        let query = source.request.query ?? []
        #expect(source.kind == .transcoded)
        #expect(query.value(for: "allowVideoStreamCopy") == "false")
        #expect(query.value(for: "allowAudioStreamCopy") == "false")
        #expect(query.value(for: "videoCodec") == "h264")
        #expect(query.value(for: "audioCodec") == "aac")
        #expect(query.value(for: "maxWidth") == "1920")
    }

    @Test("HEVC on a device without HEVC decoding encodes only video")
    func unsupportedDeviceEncodesVideo() throws {
        let source = try DownloadSourceResolver.localSource(for: MediaItem(canDownload: true, id: "episode", mediaSources: [
            MediaSource(container: "mp4", id: "source", mediaStreams: [
                MediaStreamInfo(codec: "hevc", type: .video),
                MediaStreamInfo(codec: "aac", type: .audio),
            ]),
        ]), capabilities: DevicePlaybackCapabilities(supportsHEVCDecode: false, supportsAV1Decode: false, supportsHDRPlayback: false))
        let query = source.request.query ?? []
        #expect(source.kind == .transcoded)
        #expect(query.value(for: "allowVideoStreamCopy") == "false")
        #expect(query.value(for: "allowAudioStreamCopy") == "true")
        #expect(query.value(for: "videoCodec") == "h264")
    }

    @Test("10-bit H264 and HDR on an SDR device cannot bypass conversion")
    func unsupportedProfilesNeedEncoding() {
        #expect(!OfflineDownloadEligibility.isVideoStreamPlayable(MediaStreamInfo(codec: "h264", profile: "High 10", type: .video, bitDepth: 10), capabilities: Self.modernCapabilities))
        #expect(!OfflineDownloadEligibility.isVideoStreamPlayable(MediaStreamInfo(codec: "hevc", type: .video, videoRange: "HDR"), capabilities: DevicePlaybackCapabilities(supportsHEVCDecode: true, supportsAV1Decode: false, supportsHDRPlayback: false)))
    }

    @Test("HEVC originals tagged hev1 require an Apple-compatible container remux")
    func incompatibleHEVCTagRemuxes() throws {
        let source = try DownloadSourceResolver.localSource(for: MediaItem(canDownload: true, id: "episode", mediaSources: [
            MediaSource(container: "mp4", id: "source", mediaStreams: [
                MediaStreamInfo(codec: "hevc", codecTag: "hev1", type: .video),
                MediaStreamInfo(codec: "aac", type: .audio),
            ]),
        ]), capabilities: Self.modernCapabilities)
        #expect(source.kind == .remuxed)
        #expect(source.fileExtension == "mp4")
        #expect(source.request.query?.value(for: "allowVideoStreamCopy") == "true")
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
        #expect(store.records.first?.status == .downloading(0.4))
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

@MainActor
private final class DownloadCompletionTestHandler: DownloadSessionCoordinatorEventHandler {
    var onFinish: ((URL) -> Void)?
    var onFailure: ((Error) -> Void)?

    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didFinishDownloadingTo location: URL, recordID: String) {
        onFinish?(location)
    }

    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didFailWith error: Error, resumeData: Data?, recordID: String) {
        onFailure?(error)
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
