import Foundation
import ImageIO
import Observation
import os
import OSLog

enum DownloadStatus: Codable, Equatable, Sendable {
    case queued
    case downloading(Double)
    case paused
    case complete
    case failed(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case progress
        case message
    }

    private enum Kind: String, Codable {
        case queued
        case downloading
        case paused
        case complete
        case failed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .queued:
            self = .queued
        case .downloading:
            self = try .downloading(container.decodeIfPresent(Double.self, forKey: .progress) ?? 0)
        case .paused:
            self = .paused
        case .complete:
            self = .complete
        case .failed:
            self = try .failed(container.decodeIfPresent(String.self, forKey: .message) ?? "")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .queued:
            try container.encode(Kind.queued, forKey: .kind)
        case let .downloading(progress):
            try container.encode(Kind.downloading, forKey: .kind)
            try container.encode(progress, forKey: .progress)
        case .paused:
            try container.encode(Kind.paused, forKey: .kind)
        case .complete:
            try container.encode(Kind.complete, forKey: .kind)
        case let .failed(message):
            try container.encode(Kind.failed, forKey: .kind)
            try container.encode(message, forKey: .message)
        }
    }

    var isActive: Bool {
        switch self {
        case .queued, .downloading:
            return true
        case .paused, .complete, .failed:
            return false
        }
    }

    var isComplete: Bool {
        self == .complete
    }

    var actionOutcome: ActionOutcome? {
        switch self {
        case .queued: .queued
        case .downloading: .pending
        case .paused: nil
        case .complete: .confirmed
        case let .failed(message): .failed(.unknown(message))
        }
    }
}

struct OfflineDownloadRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let item: MediaItem
    let filePath: String
    let byteCount: Int64
    let serverID: String
    let userID: String
    let downloadedAt: Date
    var remoteReference: MediaReference? = nil
    var remoteUnavailable: Bool? = nil
    /// Nil identifies a preexisting download whose precise server source is unknown.
    var mediaSourceID: String? = nil
    var status: DownloadStatus
    var progress: Double
    var resumeData: Data?
    var activity: DownloadActivity?
    var estimatedByteCount: Int64? = nil

    private enum CodingKeys: String, CodingKey {
        case id
        case item
        case filePath
        case byteCount
        case serverID
        case userID
        case downloadedAt
        case remoteUnavailable
        case mediaSourceID
        case remoteReference
        case status
        case progress
        case resumeData
        case activity
        case estimatedByteCount
    }

    init(
        id: String,
        item: MediaItem,
        filePath: String,
        byteCount: Int64,
        serverID: String,
        userID: String,
        downloadedAt: Date,
        status: DownloadStatus = .complete,
        progress: Double = 1,
        resumeData: Data? = nil,
        activity: DownloadActivity? = nil,
        mediaSourceID: String? = nil
    ) {
        self.id = id
        self.item = item
        self.filePath = filePath
        self.byteCount = byteCount
        self.serverID = serverID
        self.userID = userID
        self.downloadedAt = downloadedAt
        self.status = status
        self.progress = progress
        self.resumeData = resumeData
        self.activity = activity
        self.mediaSourceID = mediaSourceID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        item = try container.decode(MediaItem.self, forKey: .item)
        filePath = try container.decode(String.self, forKey: .filePath)
        byteCount = try container.decode(Int64.self, forKey: .byteCount)
        serverID = try container.decode(String.self, forKey: .serverID)
        userID = try container.decode(String.self, forKey: .userID)
        downloadedAt = try container.decode(Date.self, forKey: .downloadedAt)
        remoteReference = try container.decodeIfPresent(MediaReference.self, forKey: .remoteReference)
        remoteUnavailable = try container.decodeIfPresent(Bool.self, forKey: .remoteUnavailable)
        mediaSourceID = try container.decodeIfPresent(String.self, forKey: .mediaSourceID)
        status = try container.decode(DownloadStatus.self, forKey: .status)
        progress = try container.decode(Double.self, forKey: .progress)
        resumeData = try container.decodeIfPresent(Data.self, forKey: .resumeData)
        activity = try container.decodeIfPresent(DownloadActivity.self, forKey: .activity)
        estimatedByteCount = try container.decodeIfPresent(Int64.self, forKey: .estimatedByteCount)
    }

    var itemID: String? {
        item.id
    }

    var requiresServerPreparationForDownload: Bool {
        item.mediaSources.contains { OfflineDownloadEligibility.isAVPlayerPlayable($0) } != true
    }
}

enum OfflineDownloadEligibility {
    private static let playableContainers: Set<String> = ["mp4", "m4v", "mov"]
    /// Audio-only originals AVPlayer plays natively (songs, audiobooks).
    static let playableAudioContainers: Set<String> = ["mp3", "m4a", "m4b", "aac", "flac", "alac", "wav"]
    private static let playableAudioCodecs: Set<String> = ["aac", "mp3", "ac3", "eac3", "alac", "flac"]

    static func canDownload(_ item: MediaItem) -> Bool {
        item.canDownload == true
    }

    static func isAVPlayerPlayable(_ source: MediaSource, capabilities: DevicePlaybackCapabilities = .current) -> Bool {
        guard source.videoType == nil || source.videoType == .videoFile else { return false }
        let containers = source.container?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } ?? []

        // Audio-only sources (no video streams) qualify via the audio container list.
        let isAudioOnly = !source.mediaStreams.contains { $0.type == .video }
        if isAudioOnly, containers.contains(where: { playableAudioContainers.contains($0) }) {
            return source.mediaStreams.filter { $0.type == .audio }.allSatisfy { stream in
                guard let codec = stream.codec?.lowercased() else { return true }
                return playableAudioCodecs.contains(codec) || playableAudioContainers.contains(codec)
            }
        }

        guard containers.contains(where: { playableContainers.contains($0) }) else { return false }

        let streams = source.mediaStreams
        let videoStreams = streams.filter { $0.type == .video }
        let audioStreams = streams.filter { $0.type == .audio }
        let videoPlayable = videoStreams.isEmpty || videoStreams.allSatisfy {
            isVideoStreamPlayable($0, capabilities: capabilities) && !AVPlayerContainerCompatibility.requiresHEVCRemux(codecTag: $0.codecTag)
        }
        let audioPlayable = audioStreams.isEmpty || audioStreams.allSatisfy { codec in
            guard let codec = codec.codec?.lowercased() else { return false }
            return playableAudioCodecs.contains(codec)
        }
        return videoPlayable && audioPlayable
    }

    /// Conservative MP4 copy policy: unsupported profiles and HDR displays fall back
    /// to server conversion even if the codec's name is otherwise familiar.
    static func isVideoStreamPlayable(_ stream: MediaStreamInfo, capabilities: DevicePlaybackCapabilities) -> Bool {
        if stream.videoRange?.lowercased() == "hdr", !capabilities.supportsHDRPlayback {
            return false
        }
        let profile = stream.profile?.lowercased().replacingOccurrences(of: " ", with: "")
        switch stream.codec?.lowercased() {
        case "h264":
            return (stream.bitDepth ?? 8) <= 8 && profile.map { ["baseline", "constrainedbaseline", "main", "high", "constrainedhigh"].contains($0) } != false
        case "hevc":
            return capabilities.supportsHEVCDecode && (stream.bitDepth ?? 10) <= 10 && profile.map { ["main", "main10"].contains($0) } != false
        default:
            return false
        }
    }
}

/// Every handle for the same canonical directory serializes its filesystem transactions.
private final class DownloadFileLock: @unchecked Sendable {
    let lock = NSRecursiveLock()
}

private final class WeakDownloadFileLock: @unchecked Sendable {
    weak var value: DownloadFileLock?
    init(_ value: DownloadFileLock) {
        self.value = value
    }
}

private enum DownloadFileLocks {
    private static let locks = OSAllocatedUnfairLock(initialState: [String: WeakDownloadFileLock]())

    static func shared(for directory: URL) -> DownloadFileLock {
        let key = directory.standardizedFileURL.resolvingSymlinksInPath().path
        return locks.withLock { values in
            values = values.filter { $0.value.value != nil }
            if let current = values[key]?.value {
                return current
            }
            let current = DownloadFileLock()
            values[key] = WeakDownloadFileLock(current)
            return current
        }
    }
}

struct OfflineDownloadFileStore: Sendable {
    static let shared = OfflineDownloadFileStore()

    private let directory: URL
    private let recordsFileName = "records.json"
    private let fileLock: DownloadFileLock

    init(directory: URL = Self.defaultDirectory()) {
        self.directory = directory
        self.fileLock = DownloadFileLocks.shared(for: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    init(applicationSupportDirectory: URL) {
        self.init(directory: Self.defaultDirectory(applicationSupportDirectory: applicationSupportDirectory))
    }

    func records(serverID: String, userID: String) -> [OfflineDownloadRecord] {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        return loadRecords().filter { $0.serverID == serverID && $0.userID == userID }
    }

    func readRecords(serverID: String, userID: String) throws -> [OfflineDownloadRecord] {
        try readRecords().filter { $0.serverID == serverID && $0.userID == userID }
    }

    func readRecords() throws -> [OfflineDownloadRecord] {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        return try loadRecordsStrictly()
    }

    func availableCapacity() -> Int64? {
        #if os(tvOS)
            return nil
        #elseif os(watchOS)
            let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return values?.volumeAvailableCapacity.map(Int64.init)
        #else
            let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values?.volumeAvailableCapacityForImportantUsage
        #endif
    }

    func record(forItemID itemID: String, serverID: String, userID: String) -> OfflineDownloadRecord? {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        return records(serverID: serverID, userID: userID).first { $0.item.id == itemID }
    }

    func record(forRecordID id: String) -> OfflineDownloadRecord? {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        return loadRecords().first { $0.id == id }
    }

    /// Finalization must distinguish explicit deletion from unreadable metadata.
    func readRecord(forRecordID id: String) throws -> OfflineDownloadRecord? {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        return try loadRecordsStrictly().first { $0.id == id }
    }

    func localArtworkURL(for record: OfflineDownloadRecord) -> URL? {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        let url = artworkURL(for: record)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { return nil }
        return url
    }

    func persistArtwork(_ data: Data, for record: OfflineDownloadRecord) throws {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        guard !data.isEmpty, data.count <= 4 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil,
              self.record(forRecordID: record.id)?.downloadedAt == record.downloadedAt else { return }
        let destination = artworkURL(for: record)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        try excludeFromBackup(destination)
    }

    func artworkURL(for record: OfflineDownloadRecord) -> URL {
        accountDirectory(serverID: record.serverID, userID: record.userID)
            .appendingPathComponent(safePathComponent(record.item.id ?? record.id) + "-poster")
            .appendingPathExtension("image")
    }

    func localFileURL(for record: OfflineDownloadRecord) -> URL? {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        guard record.status.isComplete else { return nil }
        let url = URL(fileURLWithPath: record.filePath)
        let fallback = accountDirectory(serverID: record.serverID, userID: record.userID)
            .appendingPathComponent(safePathComponent(record.item.id ?? ""))
            .appendingPathExtension(url.pathExtension)
        let candidate = FileManager.default.fileExists(atPath: url.path) ? url : fallback
        guard let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { return nil }
        return candidate
    }

    func totalByteCount(serverID: String, userID: String) -> Int64 {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        return records(serverID: serverID, userID: userID).reduce(0) { $0 + $1.byteCount }
    }

    func persistDownloadedFile(
        _ sourceURL: URL,
        item: MediaItem,
        serverID: String,
        userID: String,
        fileExtension: String? = nil,
        downloadedAt: Date = Date(),
        mediaSourceID: String? = nil,
        activity: DownloadActivity? = nil,
        remoteReference: MediaReference? = nil,
        remoteUnavailable: Bool? = nil
    ) throws -> OfflineDownloadRecord {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        guard let itemID = item.id else { throw CocoaError(.fileNoSuchFile) }
        let resolvedExtension = fileExtension ?? (sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension)
        let destination = try destinationURL(itemID: itemID, serverID: serverID, userID: userID, fileExtension: resolvedExtension)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: sourceURL, to: destination)
        do {
            try excludeFromBackup(destination)

            let values = try destination.resourceValues(forKeys: [.fileSizeKey])
            let byteCount = Int64(values.fileSize ?? 0)
            var completedActivity = activity
            completedActivity?.transition(to: .complete)
            completedActivity?.receivedBytes = byteCount
            completedActivity?.expectedBytes = byteCount > 0 ? byteCount : nil
            var record = OfflineDownloadRecord(
                id: Self.recordID(itemID: itemID, serverID: serverID, userID: userID),
                item: item,
                filePath: destination.path,
                byteCount: byteCount,
                serverID: serverID,
                userID: userID,
                downloadedAt: downloadedAt,
                status: .complete,
                progress: 1,
                activity: completedActivity,
                mediaSourceID: mediaSourceID
            )
            record.remoteReference = remoteReference
            record.remoteUnavailable = remoteUnavailable
            try persist(record)
            return record
        } catch {
            // Keep the coordinator's recovery source until metadata is durable.
            if FileManager.default.fileExists(atPath: destination.path),
               !FileManager.default.fileExists(atPath: sourceURL.path)
            {
                try? FileManager.default.moveItem(at: destination, to: sourceURL)
            }
            throw error
        }
    }

    func finalizeDownloadedFile(_ sourceURL: URL, expected: OfflineDownloadRecord, ownership: DownloadCompletionOwnership) throws -> OfflineDownloadRecord? {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        guard ownership.isCurrent,
              let current = try readRecord(forRecordID: expected.id), current.downloadedAt == expected.downloadedAt,
              !current.status.isComplete else { return nil }
        return try persistDownloadedFile(
            sourceURL,
            item: current.item,
            serverID: current.serverID,
            userID: current.userID,
            fileExtension: URL(fileURLWithPath: current.filePath).pathExtension,
            downloadedAt: current.downloadedAt,
            mediaSourceID: current.mediaSourceID,
            activity: current.activity,
            remoteReference: current.remoteReference,
            remoteUnavailable: current.remoteUnavailable
        )
    }

    func failFinalization(expected: OfflineDownloadRecord, ownership: DownloadCompletionOwnership, message: String) throws -> OfflineDownloadRecord? {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        guard ownership.isCurrent,
              var current = try readRecord(forRecordID: expected.id), current.downloadedAt == expected.downloadedAt,
              !current.status.isComplete else { return nil }
        current.status = .failed(message)
        current.activity?.transition(to: .failed)
        try persist(current)
        return current
    }

    @discardableResult
    func prepareDownloadRecord(
        item: MediaItem,
        serverID: String,
        userID: String,
        fileExtension: String,
        status: DownloadStatus,
        progress: Double,
        resumeData: Data? = nil,
        downloadedAt: Date = Date(),
        mediaSourceID: String? = nil
    ) -> OfflineDownloadRecord {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        guard let itemID = item.id,
              let destination = try? destinationURL(itemID: itemID, serverID: serverID, userID: userID, fileExtension: fileExtension)
        else {
            let record = OfflineDownloadRecord(
                id: UUID().uuidString,
                item: item,
                filePath: "",
                byteCount: 0,
                serverID: serverID,
                userID: userID,
                downloadedAt: downloadedAt,
                status: status,
                progress: progress,
                resumeData: resumeData,
                mediaSourceID: mediaSourceID
            )
            upsert(record)
            return record
        }

        let record = OfflineDownloadRecord(
            id: Self.recordID(itemID: itemID, serverID: serverID, userID: userID),
            item: item,
            filePath: destination.path,
            byteCount: 0,
            serverID: serverID,
            userID: userID,
            downloadedAt: downloadedAt,
            status: status,
            progress: progress,
            resumeData: resumeData,
            mediaSourceID: mediaSourceID
        )
        upsert(record)
        return record
    }

    /// Throwing persistence is required before acknowledging system background events.
    func persist(_ record: OfflineDownloadRecord) throws {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        var records = try loadRecordsStrictly()
        records.removeAll { $0.id == record.id }
        records.append(record)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records.sorted { $0.downloadedAt > $1.downloadedAt })
        try data.write(to: recordsURL, options: .atomic)
    }

    enum UpdateCondition { case incomplete, complete }

    /// The status/generation check and write share the canonical-directory lock.
    /// Native observations cannot overwrite completion, deletion, or replacement.
    @discardableResult
    func updateExisting(_ record: OfflineDownloadRecord, when condition: UpdateCondition) throws -> Bool {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        guard let current = try readRecord(forRecordID: record.id), current.downloadedAt == record.downloadedAt,
              current.status.isComplete == (condition == .complete) else { return false }
        try persist(record)
        return true
    }

    func delete(_ record: OfflineDownloadRecord) throws {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        guard let current = try readRecord(forRecordID: record.id), current.downloadedAt == record.downloadedAt else { return }
        if let fileURL = localFileURL(for: current) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try? FileManager.default.removeItem(at: artworkURL(for: current))
        var records = try loadRecordsStrictly()
        records.removeAll { $0.id == record.id }
        try saveRecords(records)
    }

    func deleteRecords(serverID: String, userID: String) throws {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        var records = try loadRecordsStrictly()
        records.removeAll { $0.serverID == serverID && $0.userID == userID }
        try saveRecords(records)

        let accountDirectory = accountDirectory(serverID: serverID, userID: userID)
        if FileManager.default.fileExists(atPath: accountDirectory.path) {
            try FileManager.default.removeItem(at: accountDirectory)
        }
    }

    static func recordID(itemID: String, serverID: String, userID: String) -> String {
        "\(serverID):\(userID):\(itemID)"
    }

    private static func defaultDirectory(
        applicationSupportDirectory: URL = AppStorageLocation.applicationSupportDirectory()
    ) -> URL {
        AppStorageLocation.appDirectory(applicationSupportDirectory: applicationSupportDirectory)
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    private var recordsURL: URL {
        directory.appendingPathComponent(recordsFileName)
    }

    private func destinationURL(itemID: String, serverID: String, userID: String, fileExtension: String) throws -> URL {
        let destinationDirectory = accountDirectory(serverID: serverID, userID: userID)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        return destinationDirectory
            .appendingPathComponent(safePathComponent(itemID))
            .appendingPathExtension(fileExtension)
    }

    private func accountDirectory(serverID: String, userID: String) -> URL {
        directory
            .appendingPathComponent(safePathComponent(serverID), isDirectory: true)
            .appendingPathComponent(safePathComponent(userID), isDirectory: true)
    }

    private func loadRecords() -> [OfflineDownloadRecord] {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        return (try? loadRecordsStrictly()) ?? []
    }

    private func loadRecordsStrictly() throws -> [OfflineDownloadRecord] {
        do {
            return try JSONDecoder().decode([OfflineDownloadRecord].self, from: Data(contentsOf: recordsURL))
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
    }

    private func saveRecords(_ records: [OfflineDownloadRecord]) throws {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        try data.write(to: recordsURL, options: .atomic)
    }

    private func upsert(_ record: OfflineDownloadRecord) {
        fileLock.lock.lock()
        defer { fileLock.lock.unlock() }
        try? persist(record)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private func safePathComponent(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
        }.reduce(into: "") { $0.append($1) }
    }
}

@MainActor
@Observable
final class OfflineDownloadStore: DownloadSessionCoordinatorEventHandler {
    static let shared = OfflineDownloadStore()

    static let minimumFreeBytes: Int64 = 1 * 1024 * 1024 * 1024

    private(set) var records: [OfflineDownloadRecord] = []
    private(set) var loadState: LoadState = .idle
    private(set) var loadErrorMessage: String?
    private(set) var activeItemIDs: Set<String> = []
    private(set) var activities: [String: DownloadActivity] = [:]
    private var lastCheckpoint: [String: Date] = [:]
    private var resolvingGenerations: [String: Date] = [:]
    private var artworkRequests: Set<String> = []
    static let deleteFinishedDefaultsKey = "downloads.deleteFinished"
    private let defaults: UserDefaults
    private(set) var errorMessage: String?

    private let fileStore: OfflineDownloadFileStore
    private let coordinator: DownloadSessionCoordinating
    private let progressStore: OfflinePlaybackProgressStore
    private let prepareFile: @Sendable (URL, String) async throws -> Void
    private let readCompletionRecord: @Sendable (String, OfflineDownloadFileStore) async throws -> OfflineDownloadRecord?
    private let availableCapacity: () -> Int64?
    private let logger = Logger(category: .downloads)
    private var loadedServerID: String?
    private var loadedUserID: String?

    init(fileStore: OfflineDownloadFileStore = .shared, coordinator: DownloadSessionCoordinating = DownloadSessionCoordinator.shared, defaults: UserDefaults = .standard, progressStore: OfflinePlaybackProgressStore = .shared, prepareFile: @escaping @Sendable (URL, String) async throws -> Void = { try await DownloadFilePreparation.shared.prepare($0, fileExtension: $1) }, readCompletionRecord: @escaping @Sendable (String, OfflineDownloadFileStore) async throws -> OfflineDownloadRecord? = { try await DownloadFilePreparation.shared.record(id: $0, in: $1) }, availableCapacity: (() -> Int64?)? = nil) {
        self.fileStore = fileStore
        self.defaults = defaults
        self.coordinator = coordinator
        self.progressStore = progressStore
        self.prepareFile = prepareFile
        self.readCompletionRecord = readCompletionRecord
        self.availableCapacity = availableCapacity ?? { fileStore.availableCapacity() }
        coordinator.setEventHandler(self)
    }

    func bootstrapBackgroundTransfers() {
        coordinator.setEventHandler(self)
        coordinator.reconnectActiveTasks()
    }

    func load(serverID: String, userID: String) {
        if loadedServerID != serverID || loadedUserID != userID {
            records = []
        }
        loadedServerID = serverID
        loadedUserID = userID
        loadState = .loading
        reloadRecords(serverID: serverID, userID: userID)
        coordinator.reconnectActiveTasks()
    }

    private func reloadRecords(serverID: String, userID: String) {
        do {
            let loaded = try fileStore.readRecords(serverID: serverID, userID: userID)
            records = loaded.map { record in
                latestInactiveRecord(for: record)
            }
            loadState = .loaded
            loadErrorMessage = nil
        } catch {
            let message = String(localized: "Your downloads could not be read. The saved files and metadata have been preserved. Try loading them again.")
            loadErrorMessage = message
            loadState = .failed(message)
        }
        for record in records where activities[record.id] == nil {
            if var activity = record.activity {
                activity.resetTransferSampling()
                activities[record.id] = activity
            }
        }
        activeItemIDs = Set(records.compactMap { record in
            record.status.isActive ? record.item.id : nil
        })
    }

    func record(for item: MediaItem, serverID: String, userID: String, mediaSourceID: String? = nil) -> OfflineDownloadRecord? {
        guard let itemID = item.id,
              let record = fileStore.record(forItemID: itemID, serverID: serverID, userID: userID),
              mediaSourceID == nil || record.mediaSourceID == mediaSourceID else { return nil }
        return record
    }

    func localFileURL(for item: MediaItem, serverID: String, userID: String, mediaSourceID: String? = nil) -> URL? {
        guard let record = record(for: item, serverID: serverID, userID: userID, mediaSourceID: mediaSourceID) else { return nil }
        return fileStore.localFileURL(for: record)
    }

    func completedRecords(serverID: String, userID: String) -> [OfflineDownloadRecord] {
        records.filter { $0.serverID == serverID && $0.userID == userID && fileStore.localFileURL(for: $0) != nil }
    }

    func localArtworkURL(for item: MediaItem, serverID: String, userID: String) -> URL? {
        guard let record = record(for: item, serverID: serverID, userID: userID) else { return nil }
        return fileStore.localArtworkURL(for: record)
    }

    func totalByteCount(serverID: String, userID: String) -> Int64 {
        fileStore.totalByteCount(serverID: serverID, userID: userID)
    }

    func clearError() {
        errorMessage = nil
    }

    func download(_ request: PlaybackRequest, session: SessionStore) async {
        do {
            _ = try fileStore.readRecords(serverID: session.server.id, userID: session.user.id)
        } catch {
            load(serverID: session.server.id, userID: session.user.id)
            errorMessage = loadErrorMessage
            return
        }
        let saved = request.item
        let item: MediaItem
        do {
            item = try await session.references.currentItem(saved)
            try Task.checkCancellation()
            guard ContentRatingGate.admitsStored(item) else { throw GusError.notFound }
        } catch {
            errorMessage = GusError(from: error).localizedDescription
            return
        }
        guard DownloadsAvailability.isSupported, session.mediaProvider.capabilities.supportsDownloads else { return }
        guard let itemID = item.id, OfflineDownloadEligibility.canDownload(item) else {
            errorMessage = String(localized: "This item is not available for download.", comment: "Download unavailable message")
            return
        }
        guard session.isActive, !activeItemIDs.contains(itemID) else { return }
        if let existing = fileStore.record(forItemID: itemID, serverID: session.server.id, userID: session.user.id),
           existing.status.isComplete
        {
            if let sourceID = request.streamSelection.mediaSourceID, existing.mediaSourceID != sourceID {
                errorMessage = String(localized: "Another version is already downloaded. Delete it before downloading this version.")
                return
            }
            if fileStore.localFileURL(for: existing) != nil {
                return
            }
        }
        let selectedSource = request.streamSelection.mediaSourceID.flatMap { id in item.mediaSources.first { $0.id == id } } ?? (request.streamSelection.mediaSourceID == nil ? item.mediaSources.first : nil)
        let selection = selectedSource.map { request.selection(in: $0) } ?? request.streamSelection

        var generation: Date?
        do {
            errorMessage = nil
            if loadedServerID == nil || loadedUserID == nil {
                load(serverID: session.server.id, userID: session.user.id)
            }
            let restartingID = OfflineDownloadFileStore.recordID(itemID: itemID, serverID: session.server.id, userID: session.user.id)
            #if os(watchOS)
                guard totalByteCount(serverID: session.server.id, userID: session.user.id) < DownloadsAvailability.accountStorageLimitBytes else {
                    throw GusError.server(String(localized: "You’ve reached the download storage limit for this account. Delete a download to make room.", comment: "Download storage limit reached"))
                }
            #endif
            try ensureDiskSpace(excluding: restartingID)
            activeItemIDs.insert(itemID)

            coordinator.cancel(recordID: restartingID)
            var record = fileStore.prepareDownloadRecord(
                item: item, serverID: session.server.id, userID: session.user.id,
                fileExtension: selectedSource?.container?.split(separator: ",").first.map(String.init) ?? "mp4",
                status: .queued, progress: 0, mediaSourceID: selectedSource?.id
            )
            generation = record.downloadedAt
            record.activity = DownloadActivity(phase: .resolving)
            try fileStore.persist(record)
            activities[record.id] = record.activity
            resolvingGenerations[record.id] = record.downloadedAt
            defer {
                if resolvingGenerations[record.id] == generation {
                    resolvingGenerations.removeValue(forKey: record.id)
                }
            }
            refreshDisplayedRecords()
            let source = try await session.mediaProvider.downloadSource(for: item, streamSelection: selection)
            // Deletion or account switching may happen while source resolution awaits.
            guard session.isActive, !Task.isCancelled, let pending = fileStore.record(forRecordID: record.id), pending.status == .queued,
                  pending.downloadedAt == record.downloadedAt else { return }
            try ensureDiskSpace(excluding: record.id, remainingBytes: source.estimatedByteCount ?? 0)
            record = fileStore.prepareDownloadRecord(
                item: item, serverID: session.server.id, userID: session.user.id,
                fileExtension: source.fileExtension, status: .downloading(0), progress: 0, downloadedAt: record.downloadedAt, mediaSourceID: source.mediaSourceID
            )
            record.activity = DownloadActivity(phase: .waitingForServer, sourceOperation: source.operation)
            record.estimatedByteCount = source.estimatedByteCount
            try fileStore.persist(record)
            activities[record.id] = record.activity
            refreshDisplayedRecords()
            Task { await cacheArtwork(for: record, session: session) }

            DiagnosticsHub.shared.record(.downloadQueued)
            coordinator.startDownload(from: source.url, recordID: record.id)
        } catch {
            let currentID = OfflineDownloadFileStore.recordID(itemID: itemID, serverID: session.server.id, userID: session.user.id)
            let current = fileStore.record(forRecordID: currentID)
            guard generation == nil || current == nil || current?.downloadedAt == generation else { return }
            activeItemIDs.remove(itemID)
            if current == nil {
                refreshDisplayedRecords()
            }
            let gusError = Self.downloadError(from: error)
            let recordID = OfflineDownloadFileStore.recordID(itemID: itemID, serverID: session.server.id, userID: session.user.id)
            if var failed = fileStore.record(forRecordID: recordID), failed.downloadedAt == generation {
                failed.status = .failed(gusError.localizedDescription)
                failed.activity?.transition(to: .failed)
                guard persistObservedRecord(failed) == .persisted else { return }
            }
            guard !gusError.isCancellation else { return }
            logger.error("Download failed: \(gusError.localizedDescription, privacy: .private)")
            if loadedServerID == session.server.id, loadedUserID == session.user.id,
               current == nil || current?.downloadedAt == generation || generation == nil
            {
                errorMessage = gusError.localizedDescription
            }
        }
    }

    func pause(itemID: String) async {
        guard let record = records.first(where: { $0.item.id == itemID }) else { return }

        await withCheckedContinuation { continuation in
            coordinator.pause(recordID: record.id) { [weak self] resumeData in
                Task { @MainActor in
                    guard let self else {
                        continuation.resume()
                        return
                    }
                    var paused = self.fileStore.record(forRecordID: record.id) ?? record
                    guard let latest = self.fileStore.record(forRecordID: record.id), !latest.status.isComplete,
                          latest.downloadedAt == record.downloadedAt else { continuation.resume(); return }
                    paused.activity = self.activities[record.id] ?? paused.activity
                    paused.activity?.transition(to: .paused)
                    paused.status = .paused
                    paused.resumeData = resumeData
                    paused.progress = paused.activity?.progress ?? record.progress
                    guard self.persistObservedRecord(paused) != .declined else { continuation.resume(); return }
                    DiagnosticsHub.shared.record(.downloadPaused)
                    continuation.resume()
                }
            }
        }
    }

    func resume(_ snapshot: OfflineDownloadRecord, session: SessionStore) async {
        guard session.isActive, var record = fileStore.record(forRecordID: snapshot.id),
              record.downloadedAt == snapshot.downloadedAt, record.mediaSourceID == snapshot.mediaSourceID,
              !record.status.isComplete,
              record.serverID == session.server.id, record.userID == session.user.id,
              loadedServerID == session.server.id, loadedUserID == session.user.id else { return }

        record = latestInactiveRecord(for: record)
        guard !record.status.isActive else { return }

        do {
            let activity = activities[record.id] ?? record.activity
            // A restart goes through download(), which checks the full source size.
            let remaining = record.resumeData == nil ? 0 : Self.remainingBytes(for: record, activity: activity)
            try ensureDiskSpace(excluding: record.id, remainingBytes: remaining)
        } catch {
            errorMessage = Self.downloadError(from: error).localizedDescription
            return
        }
        errorMessage = nil
        if case .failed = record.status, coordinator.retryStagedDownload(recordID: record.id) {
            return
        }
        guard let resumeData = record.resumeData else {
            await download(PlaybackRequest(item: record.item, streamSelection: .init(audioStreamIndex: nil, subtitleStreamIndex: nil, mediaSourceID: record.mediaSourceID)), session: session)
            return
        }

        record.activity = activities[record.id] ?? record.activity ?? DownloadActivity()
        record.activity?.transition(to: .waitingForServer)
        record.status = .downloading(record.progress)
        record.progress = record.activity?.progress ?? record.progress
        record.resumeData = nil
        do {
            guard try fileStore.updateExisting(record, when: .incomplete) else { return }
        } catch {
            reportPersistenceFailure(error, record: record)
            return
        }
        errorMessage = nil
        activities[record.id] = record.activity
        publishRecord(record)
        refreshDisplayedRecords()
        coordinator.resumeDownload(with: resumeData, recordID: record.id)
    }

    /// Only the captured generation can be removed: a stale confirmation or player
    /// must never delete a replacement download or another account's file.
    func delete(_ record: OfflineDownloadRecord, serverID: String, userID: String) {
        guard record.serverID == serverID, record.userID == userID,
              let current = fileStore.record(forRecordID: record.id),
              current.downloadedAt == record.downloadedAt else { return }
        do {
            coordinator.cancel(recordID: record.id)
            try fileStore.delete(current)
            activities.removeValue(forKey: record.id)
            lastCheckpoint.removeValue(forKey: record.id)
            if let itemID = record.item.id {
                activeItemIDs.remove(itemID)
            }
            refreshDisplayedRecords()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Called only for a natural media end or a reader closed at its final location.
    /// No historical played flags or partial progress trigger this opt-in policy.
    func deleteAfterCompletion(_ record: OfflineDownloadRecord?) {
        guard defaults.bool(forKey: Self.deleteFinishedDefaultsKey),
              let record, record.status.isComplete else { return }
        delete(record, serverID: record.serverID, userID: record.userID)
    }

    func delete(_ selected: [OfflineDownloadRecord], serverID: String, userID: String) {
        for record in selected {
            delete(record, serverID: serverID, userID: userID)
        }
    }

    func deleteAll(serverID: String, userID: String) {
        do {
            let scopedRecords = fileStore.records(serverID: serverID, userID: userID)
            for record in scopedRecords {
                coordinator.cancel(recordID: record.id)
                activities.removeValue(forKey: record.id)
                lastCheckpoint.removeValue(forKey: record.id)
            }
            try fileStore.deleteRecords(serverID: serverID, userID: userID)

            if loadedServerID == serverID, loadedUserID == userID {
                records = []
                activeItemIDs = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func downloadSessionCoordinator(
        _ coordinator: DownloadSessionCoordinating,
        didReconnectActiveRecordIDs recordIDs: Set<String>
    ) {
        for var record in records where record.status.isActive && !recordIDs.contains(record.id) && resolvingGenerations[record.id] == nil {
            // Staged completions are replayed before this callback. A missing task is
            // recoverable; a late completed-file callback can still finalize this record.
            record.status = .failed(String(localized: "Transfer interrupted. Resume or restart the download."))
            record.activity = activities[record.id] ?? record.activity
            record.activity?.transition(to: .failed)
            _ = persistObservedRecord(record)
        }
    }

    func downloadSessionCoordinator(
        _ coordinator: DownloadSessionCoordinating,
        didUpdateActivity activity: DownloadActivity,
        recordID: String
    ) {
        guard var record = records.first(where: { $0.id == recordID }) ?? fileStore.record(forRecordID: recordID), record.status.isActive else { return }
        var observed = activity
        if observed.phase == .waitingForServer, observed.receivedBytes == 0,
           let retained = activities[recordID] ?? record.activity
        {
            observed.receivedBytes = retained.receivedBytes
            observed.expectedBytes = retained.expectedBytes
        }
        observed.startedAt = activities[recordID]?.startedAt ?? record.activity?.startedAt ?? activity.startedAt
        observed.sourceOperation = activities[recordID]?.sourceOperation ?? record.activity?.sourceOperation ?? activity.sourceOperation
        record.activity = observed
        if let progress = observed.progress {
            record.progress = progress
        }
        if Date().timeIntervalSince(lastCheckpoint[recordID] ?? .distantPast) >= 5 {
            guard persistObservedRecord(record) != .declined else { return }
            lastCheckpoint[recordID] = Date()
        } else {
            publishRecord(record)
        }
    }

    func downloadSessionCoordinatorDidFinishBackgroundEvents(_ coordinator: DownloadSessionCoordinating) async {
        DownloadBackgroundEvents.shared.finish()
    }

    func downloadSessionCoordinator(
        _ coordinator: DownloadSessionCoordinating,
        finalizeDownloadedFileAt location: URL,
        recordID: String,
        ownership: DownloadCompletionOwnership
    ) async -> Bool {
        guard ownership.isCurrent else { return true }
        let record: OfflineDownloadRecord
        do {
            let current = try await readCompletionRecord(recordID, fileStore)
            guard ownership.isCurrent, let current, !current.status.isComplete else { return true }
            record = current
        } catch {
            guard ownership.isCurrent else { return true }
            errorMessage = String(localized: "The download could not be finalized. Its staged file has been preserved.")
            DiagnosticsHub.shared.record(.downloadFailed)
            return false
        }
        activities[recordID]?.transition(to: .saving)
        do {
            let fileExtension = URL(fileURLWithPath: record.filePath).pathExtension
            try await prepareFile(location, fileExtension)
            guard ownership.isCurrent,
                  let completed = try await DownloadFilePreparation.shared.finalize(location, expected: record, ownership: ownership, in: fileStore),
                  ownership.isCurrent else { return true }
            publishRecord(completed)
            DiagnosticsHub.shared.record(.downloadCompleted)
            return true
        } catch {
            guard ownership.isCurrent else { return true }
            let failure = Self.downloadError(from: error)
            // Keep the coordinator's staged source until failure metadata is durable.
            if let failed = try? await DownloadFilePreparation.shared.fail(expected: record, ownership: ownership, message: failure.localizedDescription, in: fileStore), ownership.isCurrent {
                publishRecord(failed)
            } else if ownership.isCurrent, failure == Self.storageFullError {
                // A full volume can also prevent writing the failure checkpoint.
                var failed = record
                failed.status = .failed(failure.localizedDescription)
                failed.activity?.transition(to: .failed)
                publishRecord(failed)
            }
            guard ownership.isCurrent else { return true }
            if loadedServerID == record.serverID, loadedUserID == record.userID {
                errorMessage = failure.localizedDescription
            }
            DiagnosticsHub.shared.record(.downloadFailed)
            return false
        }
    }

    /// Track live bytes across accounts and update the matching visible generation.
    private func publishRecord(_ record: OfflineDownloadRecord) {
        if record.status.isComplete {
            activities.removeValue(forKey: record.id)
        } else {
            activities[record.id] = record.activity
        }
        if !record.status.isActive {
            lastCheckpoint.removeValue(forKey: record.id)
        }
        guard let index = records.firstIndex(where: { $0.id == record.id && $0.downloadedAt == record.downloadedAt }) else { return }
        records[index] = record
        if let itemID = record.item.id {
            activeItemIDs.remove(itemID)
            if record.status.isActive {
                activeItemIDs.insert(itemID)
            }
        }
    }

    private enum RecordPersistenceResult { case persisted, declined, failed }

    /// Paused/failed/progress callbacks describe the native task's observed state.
    /// A storage error must remain visible and must not discard fresh resume data.
    @discardableResult
    private func persistObservedRecord(_ record: OfflineDownloadRecord) -> RecordPersistenceResult {
        do {
            guard try fileStore.updateExisting(record, when: .incomplete) else { return .declined }
            publishRecord(record)
            return .persisted
        } catch {
            publishRecord(record)
            reportPersistenceFailure(error, record: record)
            return .failed
        }
    }

    private func reportPersistenceFailure(_ error: Error, record: OfflineDownloadRecord) {
        logger.error("Download metadata could not be saved: \(error.localizedDescription, privacy: .private)")
        if loadedServerID == record.serverID, loadedUserID == record.userID {
            errorMessage = Self.downloadError(from: error).localizedDescription
        }
    }

    func downloadSessionCoordinator(
        _ coordinator: DownloadSessionCoordinating,
        didFailWith error: Error,
        resumeData: Data?,
        recordID: String
    ) {
        guard var record = record(forRecordID: recordID), !record.status.isComplete else { return }
        let gusError = Self.downloadError(from: error)
        record.activity = activities[recordID] ?? record.activity
        record.activity?.transition(to: .failed)
        record.status = .failed(gusError.localizedDescription)
        record.resumeData = resumeData
        let persisted = persistObservedRecord(record)
        guard persisted != .declined else { return }
        DiagnosticsHub.shared.record(.downloadFailed)
        if persisted == .persisted || gusError == Self.storageFullError, loadedServerID == record.serverID, loadedUserID == record.userID {
            errorMessage = gusError.localizedDescription
        }
        if gusError == .unauthorized {
            let scope = AccountScope(serverID: record.serverID, userID: record.userID)
            Task { await AppModel.shared.verifyAuthentication(for: scope) }
        }
    }

    private func refreshDisplayedRecords() {
        guard let loadedServerID, let loadedUserID else { return }
        reloadRecords(serverID: loadedServerID, userID: loadedUserID)
    }

    /// Retry missing artwork for existing downloads on foreground entry, including
    /// records created before artwork caching existed. Local browsing stays file-only.
    func replaceRemoteReference(_ snapshot: OfflineDownloadRecord, with candidate: MediaItem, session: SessionStore) async -> Bool {
        let scope = session.references.scope
        guard snapshot.serverID == scope.serverID, snapshot.userID == scope.userID else { return false }
        do {
            let item = try await session.references.selectedReplacement(candidate)
            try Task.checkCancellation()
            guard session.references.isActive,
                  var record = fileStore.record(forRecordID: snapshot.id), record.downloadedAt == snapshot.downloadedAt,
                  loadedServerID == scope.serverID, loadedUserID == scope.userID else { return false }
            record.remoteReference = MediaReference(item: item, scope: scope)
            record.remoteUnavailable = false
            guard try fileStore.updateExisting(record, when: .complete) else { return false }
            session.references.recordReplacement(from: snapshot.remoteReference ?? MediaReference(item: snapshot.item, scope: scope), to: item)
            progressStore.offerTransfer(from: record.item.id, to: item, scope: scope, mediaSourceID: record.mediaSourceID)
            refreshDisplayedRecords()
            return true
        } catch { errorMessage = GusError(from: error).localizedDescription; return false }
    }

    func refreshRemoteReferences(session: SessionStore) async {
        let scope = session.references.scope
        for snapshot in completedRecords(serverID: scope.serverID, userID: scope.userID) {
            guard !Task.isCancelled else { return }
            do {
                let reference = snapshot.remoteReference ?? MediaReference(item: snapshot.item, scope: scope)
                let result = try await session.references.resolve(reference)
                try Task.checkCancellation()
                guard var record = fileStore.record(forRecordID: snapshot.id),
                      record.downloadedAt == snapshot.downloadedAt,
                      loadedServerID == scope.serverID, loadedUserID == scope.userID else { continue }
                guard case let .resolved(item) = result else {
                    record.remoteUnavailable = true
                    do { _ = try fileStore.updateExisting(record, when: .complete) }
                    catch { reportPersistenceFailure(error, record: record) }
                    continue
                }
                record.remoteReference = MediaReference(item: item, scope: scope)
                record.remoteUnavailable = false
                do { guard try fileStore.updateExisting(record, when: .complete) else { continue } }
                catch { reportPersistenceFailure(error, record: record); continue }
                if item.id != snapshot.item.id {
                    progressStore.offerTransfer(from: snapshot.item.id, to: item, scope: scope, mediaSourceID: snapshot.mediaSourceID)
                }
            } catch {
                if GusError(from: error) == .unauthorized {
                    session.handleUnauthorized(); return
                }
            }
        }
        refreshDisplayedRecords()
    }

    func repairMissingArtwork(session: SessionStore) async {
        let pending = fileStore.records(serverID: session.server.id, userID: session.user.id)
        for record in pending where record.status.isComplete {
            guard !Task.isCancelled, loadedServerID == session.server.id,
                  loadedUserID == session.user.id else { return }
            await cacheArtwork(for: record, session: session)
        }
    }

    private func cacheArtwork(for record: OfflineDownloadRecord, session: SessionStore) async {
        guard session.isActive, fileStore.localArtworkURL(for: record) == nil,
              fileStore.record(forRecordID: record.id)?.downloadedAt == record.downloadedAt,
              !artworkRequests.contains(record.id) else { return }
        let urls = session.mediaProvider.artworkURLs(for: record.remoteReference?.item ?? record.item, request: .init(role: .poster, maxWidth: 260))
        guard !urls.isEmpty else { return }
        artworkRequests.insert(record.id)
        defer { artworkRequests.remove(record.id) }
        for url in urls {
            guard session.isActive, !Task.isCancelled else { return }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                if let token = session.client.accessToken {
                    request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")
                }
                let (data, response) = try await session.artworkTransport.session.data(for: request)
                guard session.isActive, !Task.isCancelled else { return }
                guard let http = response as? HTTPURLResponse else { continue }
                if http.statusCode == 401 {
                    session.handleUnauthorized(); return
                }
                guard (200 ..< 300).contains(http.statusCode), http.mimeType?.hasPrefix("image/") == true,
                      data.count <= 4 * 1024 * 1024,
                      fileStore.record(forRecordID: record.id)?.downloadedAt == record.downloadedAt else { continue }
                try fileStore.persistArtwork(data, for: record)
                if fileStore.localArtworkURL(for: record) != nil {
                    refreshDisplayedRecords()
                    return
                }
            } catch {
                guard !Task.isCancelled, !GusError(from: error).isCancellation else { return }
                // A bad candidate must not prevent trying the next role-aware fallback.
            }
        }
        logger.debug("Download artwork remains unavailable")
    }

    private func latestInactiveRecord(for record: OfflineDownloadRecord) -> OfflineDownloadRecord {
        // A native pause or failure can be observed even if the index cannot be written.
        guard record.status.isActive,
              let observed = records.first(where: { $0.id == record.id && $0.downloadedAt == record.downloadedAt }),
              !observed.status.isActive, !observed.status.isComplete else { return record }
        return observed
    }

    private static func remainingBytes(for record: OfflineDownloadRecord, activity: DownloadActivity?) -> Int64 {
        let expected = max(0, activity?.expectedBytes ?? record.estimatedByteCount ?? 0)
        return expected - min(expected, max(0, activity?.receivedBytes ?? 0))
    }

    private func ensureDiskSpace(excluding recordID: String, remainingBytes: Int64 = 0) throws {
        guard let available = availableCapacity() else { return }
        let error = GusError.server(String(localized: "There isn’t enough free space for this download. Free up space on this device and try again.", comment: "Low disk space download error"))
        guard available >= Self.minimumFreeBytes else { throw error }
        var uncommitted = available - Self.minimumFreeBytes
        for saved in try fileStore.readRecords() where saved.id != recordID {
            let record = latestInactiveRecord(for: saved)
            guard record.status.isActive else { continue }
            let needed = Self.remainingBytes(for: record, activity: activities[record.id] ?? record.activity)
            guard needed <= uncommitted else { throw error }
            uncommitted -= needed
        }
        guard remainingBytes <= uncommitted else { throw error }
    }

    private static var storageFullError: GusError {
        .server(String(localized: "This download ran out of storage space. Free up space on this device and try again.", comment: "Download failed because the volume is full"))
    }

    private static func downloadError(from error: Error) -> GusError {
        var underlying: NSError? = error as NSError
        while let cause = underlying {
            if (cause.domain == NSCocoaErrorDomain && cause.code == CocoaError.fileWriteOutOfSpace.rawValue)
                || (cause.domain == NSPOSIXErrorDomain && cause.code == Int(POSIXErrorCode.ENOSPC.rawValue))
            {
                return storageFullError
            }
            underlying = cause.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return GusError(from: error)
    }

    private func record(forRecordID recordID: String) -> OfflineDownloadRecord? {
        fileStore.record(forRecordID: recordID)
    }
}
