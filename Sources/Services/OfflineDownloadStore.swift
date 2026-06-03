import Foundation
import Get
import JellyfinAPI
import Observation
import OSLog

enum DownloadStatus: Codable, Equatable {
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
}

struct OfflineDownloadRecord: Codable, Equatable, Identifiable {
    let id: String
    let item: BaseItemDto
    let filePath: String
    let byteCount: Int64
    let serverID: String
    let userID: String
    let downloadedAt: Date
    var status: DownloadStatus
    var progress: Double
    var resumeData: Data?

    private enum CodingKeys: String, CodingKey {
        case id
        case item
        case filePath
        case byteCount
        case serverID
        case userID
        case downloadedAt
        case status
        case progress
        case resumeData
    }

    init(
        id: String,
        item: BaseItemDto,
        filePath: String,
        byteCount: Int64,
        serverID: String,
        userID: String,
        downloadedAt: Date,
        status: DownloadStatus = .complete,
        progress: Double = 1,
        resumeData: Data? = nil
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        item = try container.decode(BaseItemDto.self, forKey: .item)
        filePath = try container.decode(String.self, forKey: .filePath)
        byteCount = try container.decode(Int64.self, forKey: .byteCount)
        serverID = try container.decode(String.self, forKey: .serverID)
        userID = try container.decode(String.self, forKey: .userID)
        downloadedAt = try container.decode(Date.self, forKey: .downloadedAt)
        status = try container.decodeIfPresent(DownloadStatus.self, forKey: .status) ?? .complete
        progress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? (status.isComplete ? 1 : 0)
        resumeData = try container.decodeIfPresent(Data.self, forKey: .resumeData)
    }

    var itemID: String? {
        item.id
    }

    var requiresTranscodingForDownload: Bool {
        item.mediaSources?.contains(where: OfflineDownloadEligibility.isAVPlayerPlayable) != true
    }
}

enum OfflineDownloadEligibility {
    private static let playableContainers: Set<String> = ["mp4", "m4v", "mov"]
    private static let playableVideoCodecs: Set<String> = ["h264", "hevc"]
    private static let playableAudioCodecs: Set<String> = ["aac", "mp3", "ac3", "eac3", "alac", "flac"]

    static func canDownload(_ item: BaseItemDto) -> Bool {
        item.canDownload == true
    }

    static func isAVPlayerPlayable(_ source: MediaSourceInfo) -> Bool {
        guard source.videoType == nil || source.videoType == .videoFile else { return false }
        let containers = source.container?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } ?? []
        guard containers.contains(where: { playableContainers.contains($0) }) else { return false }

        let streams = source.mediaStreams ?? []
        let videoStreams = streams.filter { $0.type == .video }
        let audioStreams = streams.filter { $0.type == .audio }
        let videoPlayable = videoStreams.isEmpty || videoStreams.allSatisfy { codec in
            guard let codec = codec.codec?.lowercased() else { return false }
            return playableVideoCodecs.contains(codec)
        }
        let audioPlayable = audioStreams.isEmpty || audioStreams.allSatisfy { codec in
            guard let codec = codec.codec?.lowercased() else { return false }
            return playableAudioCodecs.contains(codec)
        }
        return videoPlayable && audioPlayable
    }
}

struct OfflineDownloadFileStore {
    static let shared = OfflineDownloadFileStore()

    private let directory: URL
    private let recordsFileName = "records.json"

    init(directory: URL = Self.defaultDirectory()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func records(serverID: String, userID: String) -> [OfflineDownloadRecord] {
        loadRecords().filter { $0.serverID == serverID && $0.userID == userID }
    }

    func record(forItemID itemID: String, serverID: String, userID: String) -> OfflineDownloadRecord? {
        records(serverID: serverID, userID: userID).first { $0.item.id == itemID }
    }

    func localFileURL(for record: OfflineDownloadRecord) -> URL? {
        guard record.status.isComplete else { return nil }
        let url = URL(fileURLWithPath: record.filePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func totalByteCount(serverID: String, userID: String) -> Int64 {
        records(serverID: serverID, userID: userID).reduce(0) { $0 + $1.byteCount }
    }

    func persistDownloadedFile(
        _ sourceURL: URL,
        item: BaseItemDto,
        serverID: String,
        userID: String,
        fileExtension: String? = nil,
        downloadedAt: Date = Date()
    ) throws -> OfflineDownloadRecord {
        guard let itemID = item.id else { throw CocoaError(.fileNoSuchFile) }
        let resolvedExtension = fileExtension ?? (sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension)
        let destination = try destinationURL(itemID: itemID, serverID: serverID, userID: userID, fileExtension: resolvedExtension)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: sourceURL, to: destination)
        try excludeFromBackup(destination)

        let values = try destination.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = Int64(values.fileSize ?? 0)
        let record = OfflineDownloadRecord(
            id: Self.recordID(itemID: itemID, serverID: serverID, userID: userID),
            item: item,
            filePath: destination.path,
            byteCount: byteCount,
            serverID: serverID,
            userID: userID,
            downloadedAt: downloadedAt,
            status: .complete,
            progress: 1
        )
        upsert(record)
        return record
    }

    @discardableResult
    func prepareDownloadRecord(
        item: BaseItemDto,
        serverID: String,
        userID: String,
        fileExtension: String,
        status: DownloadStatus,
        progress: Double,
        resumeData: Data? = nil,
        downloadedAt: Date = Date()
    ) -> OfflineDownloadRecord {
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
                resumeData: resumeData
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
            resumeData: resumeData
        )
        upsert(record)
        return record
    }

    func update(_ record: OfflineDownloadRecord) {
        upsert(record)
    }

    func delete(_ record: OfflineDownloadRecord) throws {
        if let fileURL = localFileURL(for: record) {
            try FileManager.default.removeItem(at: fileURL)
        }
        var records = loadRecords()
        records.removeAll { $0.id == record.id }
        saveRecords(records)
    }

    static func recordID(itemID: String, serverID: String, userID: String) -> String {
        "\(serverID):\(userID):\(itemID)"
    }

    private static func defaultDirectory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Gus/Downloads", isDirectory: true)
    }

    private var recordsURL: URL {
        directory.appendingPathComponent(recordsFileName)
    }

    private func destinationURL(itemID: String, serverID: String, userID: String, fileExtension: String) throws -> URL {
        let destinationDirectory = directory
            .appendingPathComponent(safePathComponent(serverID), isDirectory: true)
            .appendingPathComponent(safePathComponent(userID), isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        return destinationDirectory
            .appendingPathComponent(safePathComponent(itemID))
            .appendingPathExtension(fileExtension)
    }

    private func loadRecords() -> [OfflineDownloadRecord] {
        guard let data = try? Data(contentsOf: recordsURL) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([OfflineDownloadRecord].self, from: data)) ?? []
    }

    private func saveRecords(_ records: [OfflineDownloadRecord]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: recordsURL, options: .atomic)
    }

    private func upsert(_ record: OfflineDownloadRecord) {
        var records = loadRecords()
        records.removeAll { $0.id == record.id }
        records.append(record)
        saveRecords(records.sorted { $0.downloadedAt > $1.downloadedAt })
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
    static let softCapBytes: Int64 = 20 * 1024 * 1024 * 1024
    static let minimumFreeBytes: Int64 = 1 * 1024 * 1024 * 1024

    private(set) var records: [OfflineDownloadRecord] = []
    private(set) var activeItemIDs: Set<String> = []
    private(set) var errorMessage: String?

    private let fileStore: OfflineDownloadFileStore
    private let coordinator: DownloadSessionCoordinating
    private let logger = Logger(category: .downloads)

    init(fileStore: OfflineDownloadFileStore = .shared, coordinator: DownloadSessionCoordinating = DownloadSessionCoordinator.shared) {
        self.fileStore = fileStore
        self.coordinator = coordinator
        coordinator.setEventHandler(self)
    }

    func load(serverID: String, userID: String) {
        reloadRecords(serverID: serverID, userID: userID)
        coordinator.reconnectActiveTasks()
    }

    private func reloadRecords(serverID: String, userID: String) {
        records = fileStore.records(serverID: serverID, userID: userID)
        activeItemIDs = Set(records.compactMap { record in
            record.status.isActive ? record.item.id : nil
        })
    }

    func record(for item: BaseItemDto, serverID: String, userID: String) -> OfflineDownloadRecord? {
        guard let itemID = item.id else { return nil }
        return records.first { $0.item.id == itemID && $0.serverID == serverID && $0.userID == userID }
    }

    func localFileURL(for item: BaseItemDto, serverID: String, userID: String) -> URL? {
        guard let record = record(for: item, serverID: serverID, userID: userID) else { return nil }
        return fileStore.localFileURL(for: record)
    }

    func totalByteCount(serverID: String, userID: String) -> Int64 {
        fileStore.totalByteCount(serverID: serverID, userID: userID)
    }

    func clearError() {
        errorMessage = nil
    }

    func download(_ item: BaseItemDto, session: SessionStore) async {
        guard DownloadsAvailability.isSupported else { return }
        guard let itemID = item.id, OfflineDownloadEligibility.canDownload(item) else {
            errorMessage = String(localized: "This item is not available for download.", comment: "Download unavailable message")
            return
        }
        guard !activeItemIDs.contains(itemID) else { return }

        do {
            errorMessage = nil
            try ensureDiskBudget(serverID: session.server.id, userID: session.user.id)
            activeItemIDs.insert(itemID)

            let resolver = DownloadSourceResolver(client: session.client, userID: session.user.id)
            let source = try await resolver.resolve(for: item)
            guard let url = session.client.url(with: source.request, queryAPIKey: true) else {
                throw DownloadSourceResolver.ResolverError.noMediaSource
            }

            var record = fileStore.prepareDownloadRecord(
                item: item,
                serverID: session.server.id,
                userID: session.user.id,
                fileExtension: source.fileExtension,
                status: .queued,
                progress: 0
            )
            reloadRecords(serverID: session.server.id, userID: session.user.id)

            record.status = .downloading(0)
            record.progress = 0
            record.resumeData = nil
            fileStore.update(record)
            reloadRecords(serverID: session.server.id, userID: session.user.id)
            coordinator.startDownload(from: url, recordID: record.id)
        } catch {
            activeItemIDs.remove(itemID)
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            logger.error("Download failed: \(gusError.localizedDescription, privacy: .public)")
            errorMessage = gusError.localizedDescription
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
                    var paused = record
                    paused.status = .paused
                    paused.resumeData = resumeData
                    paused.progress = record.progress
                    self.fileStore.update(paused)
                    self.reloadRecords(serverID: paused.serverID, userID: paused.userID)
                    continuation.resume()
                }
            }
        }
    }

    func resume(itemID: String, session: SessionStore) async {
        guard var record = records.first(where: { $0.item.id == itemID }) else { return }

        guard let resumeData = record.resumeData else {
            errorMessage = String(localized: "Not enough resume data — restarting download.", comment: "Download resume fallback message")
            await download(record.item, session: session)
            return
        }

        record.status = .downloading(0)
        record.progress = 0
        record.resumeData = nil
        fileStore.update(record)
        reloadRecords(serverID: record.serverID, userID: record.userID)
        coordinator.resumeDownload(with: resumeData, recordID: record.id)
    }

    func delete(_ record: OfflineDownloadRecord, serverID: String, userID: String) {
        do {
            coordinator.cancel(recordID: record.id)
            try fileStore.delete(record)
            if let itemID = record.item.id {
                activeItemIDs.remove(itemID)
            }
            reloadRecords(serverID: serverID, userID: userID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func downloadSessionCoordinator(
        _ coordinator: DownloadSessionCoordinating,
        didReconnectActiveRecordIDs recordIDs: Set<String>
    ) {
        activeItemIDs.formUnion(records.compactMap { record in
            recordIDs.contains(record.id) ? record.item.id : nil
        })
    }

    func downloadSessionCoordinator(
        _ coordinator: DownloadSessionCoordinating,
        didUpdateProgress progress: Double,
        recordID: String
    ) {
        guard var record = record(forRecordID: recordID) else { return }
        record.status = .downloading(progress)
        record.progress = progress
        fileStore.update(record)
        reloadRecords(serverID: record.serverID, userID: record.userID)
    }

    func downloadSessionCoordinator(
        _ coordinator: DownloadSessionCoordinating,
        didFinishDownloadingTo location: URL,
        recordID: String
    ) {
        guard let record = record(forRecordID: recordID) else { return }
        do {
            let fileExtension = URL(fileURLWithPath: record.filePath).pathExtension
            _ = try fileStore.persistDownloadedFile(
                location,
                item: record.item,
                serverID: record.serverID,
                userID: record.userID,
                fileExtension: fileExtension.isEmpty ? "mp4" : fileExtension
            )
            if let itemID = record.item.id {
                activeItemIDs.remove(itemID)
            }
            reloadRecords(serverID: record.serverID, userID: record.userID)
        } catch {
            downloadSessionCoordinator(coordinator, didFailWith: error, resumeData: nil, recordID: recordID)
        }
    }

    func downloadSessionCoordinator(
        _ coordinator: DownloadSessionCoordinating,
        didFailWith error: Error,
        resumeData: Data?,
        recordID: String
    ) {
        guard var record = record(forRecordID: recordID) else { return }
        let gusError = GusError(from: error)
        guard !gusError.isCancellation else { return }
        record.status = .failed(gusError.localizedDescription)
        record.resumeData = resumeData
        fileStore.update(record)
        if let itemID = record.item.id {
            activeItemIDs.remove(itemID)
        }
        reloadRecords(serverID: record.serverID, userID: record.userID)
        errorMessage = gusError.localizedDescription
    }

    private func ensureDiskBudget(serverID: String, userID: String) throws {
        #if os(tvOS)
            return
        #else
            let total = totalByteCount(serverID: serverID, userID: userID)
            guard total < Self.softCapBytes else {
                throw GusError.server(String(localized: "Downloads are using the 20 GB soft cap. Delete a download before adding more.", comment: "Downloads soft cap error"))
            }

            let supportURL = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? FileManager.default.temporaryDirectory
            let values = try supportURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let available = values.volumeAvailableCapacityForImportantUsage, available < Self.minimumFreeBytes {
                throw GusError.server(String(localized: "Not enough free space to start another download.", comment: "Low disk space download error"))
            }
        #endif
    }

    private func record(forRecordID recordID: String) -> OfflineDownloadRecord? {
        records.first { $0.id == recordID }
    }
}
