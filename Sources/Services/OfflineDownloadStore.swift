import Foundation
import ImageIO
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
    let item: MediaItem
    let filePath: String
    let byteCount: Int64
    let serverID: String
    let userID: String
    let downloadedAt: Date
    var remoteReference: MediaReference? = nil
    var remoteUnavailable: Bool? = nil
    var status: DownloadStatus
    var progress: Double
    var resumeData: Data?
    var activity: DownloadActivity?

    private enum CodingKeys: String, CodingKey {
        case id
        case item
        case filePath
        case byteCount
        case serverID
        case userID
        case downloadedAt
        case remoteUnavailable
        case remoteReference
        case status
        case progress
        case resumeData
        case activity
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
        activity: DownloadActivity? = nil
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
        status = try container.decode(DownloadStatus.self, forKey: .status)
        progress = try container.decode(Double.self, forKey: .progress)
        resumeData = try container.decodeIfPresent(Data.self, forKey: .resumeData)
        activity = try container.decodeIfPresent(DownloadActivity.self, forKey: .activity)
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

struct OfflineDownloadFileStore {
    static let shared = OfflineDownloadFileStore()

    private let directory: URL
    private let recordsFileName = "records.json"

    init(directory: URL = Self.defaultDirectory()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    init(applicationSupportDirectory: URL) {
        self.init(directory: Self.defaultDirectory(applicationSupportDirectory: applicationSupportDirectory))
    }

    func records(serverID: String, userID: String) -> [OfflineDownloadRecord] {
        loadRecords().filter { $0.serverID == serverID && $0.userID == userID }
    }

    func record(forItemID itemID: String, serverID: String, userID: String) -> OfflineDownloadRecord? {
        records(serverID: serverID, userID: userID).first { $0.item.id == itemID }
    }

    func record(forRecordID id: String) -> OfflineDownloadRecord? {
        loadRecords().first { $0.id == id }
    }

    func localArtworkURL(for record: OfflineDownloadRecord) -> URL? {
        let url = artworkURL(for: record)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { return nil }
        return url
    }

    func persistArtwork(_ data: Data, for record: OfflineDownloadRecord) throws {
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
        records(serverID: serverID, userID: userID).reduce(0) { $0 + $1.byteCount }
    }

    func persistDownloadedFile(
        _ sourceURL: URL,
        item: MediaItem,
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
        do {
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

    @discardableResult
    func prepareDownloadRecord(
        item: MediaItem,
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

    /// Throwing persistence is required before acknowledging system background events.
    func persist(_ record: OfflineDownloadRecord) throws {
        var records = loadRecords()
        records.removeAll { $0.id == record.id }
        records.append(record)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records.sorted { $0.downloadedAt > $1.downloadedAt })
        try data.write(to: recordsURL, options: .atomic)
    }

    func update(_ record: OfflineDownloadRecord) {
        upsert(record)
    }

    func delete(_ record: OfflineDownloadRecord) throws {
        if let fileURL = localFileURL(for: record) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try? FileManager.default.removeItem(at: artworkURL(for: record))
        var records = loadRecords()
        records.removeAll { $0.id == record.id }
        saveRecords(records)
    }

    func deleteRecords(serverID: String, userID: String) throws {
        var records = loadRecords()
        records.removeAll { $0.serverID == serverID && $0.userID == userID }
        saveRecords(records)

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
    static let shared = OfflineDownloadStore()
    static var softCapBytes: Int64 {
        DownloadsAvailability.softCapBytes
    }

    static let minimumFreeBytes: Int64 = 1 * 1024 * 1024 * 1024

    private(set) var records: [OfflineDownloadRecord] = []
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
    private let logger = Logger(category: .downloads)
    private var loadedServerID: String?
    private var loadedUserID: String?

    init(fileStore: OfflineDownloadFileStore = .shared, coordinator: DownloadSessionCoordinating = DownloadSessionCoordinator.shared, defaults: UserDefaults = .standard) {
        self.fileStore = fileStore
        self.defaults = defaults
        self.coordinator = coordinator
        coordinator.setEventHandler(self)
    }

    func bootstrapBackgroundTransfers() {
        coordinator.setEventHandler(self)
        coordinator.reconnectActiveTasks()
    }

    func load(serverID: String, userID: String) {
        loadedServerID = serverID
        loadedUserID = userID
        reloadRecords(serverID: serverID, userID: userID)
        coordinator.reconnectActiveTasks()
    }

    private func reloadRecords(serverID: String, userID: String) {
        records = fileStore.records(serverID: serverID, userID: userID)
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

    func record(for item: MediaItem, serverID: String, userID: String) -> OfflineDownloadRecord? {
        guard let itemID = item.id else { return nil }
        return fileStore.record(forItemID: itemID, serverID: serverID, userID: userID)
    }

    func localFileURL(for item: MediaItem, serverID: String, userID: String) -> URL? {
        guard let record = record(for: item, serverID: serverID, userID: userID) else { return nil }
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

    func download(_ saved: MediaItem, session: SessionStore) async {
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
        guard !activeItemIDs.contains(itemID) else { return }

        var generation: Date?
        do {
            errorMessage = nil
            try ensureDiskBudget(serverID: session.server.id, userID: session.user.id)
            if loadedServerID == nil || loadedUserID == nil {
                load(serverID: session.server.id, userID: session.user.id)
            }
            activeItemIDs.insert(itemID)

            let restartingID = OfflineDownloadFileStore.recordID(itemID: itemID, serverID: session.server.id, userID: session.user.id)
            coordinator.cancel(recordID: restartingID)
            var record = fileStore.prepareDownloadRecord(
                item: item, serverID: session.server.id, userID: session.user.id,
                fileExtension: item.mediaSources.first?.container?.split(separator: ",").first.map(String.init) ?? "mp4",
                status: .queued, progress: 0
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
            let source = try await session.mediaProvider.downloadSource(for: item)
            // Deletion or account switching may happen while source resolution awaits.
            guard let pending = fileStore.record(forRecordID: record.id), pending.status == .queued,
                  pending.downloadedAt == record.downloadedAt else { return }
            record = fileStore.prepareDownloadRecord(
                item: item, serverID: session.server.id, userID: session.user.id,
                fileExtension: source.fileExtension, status: .downloading(0), progress: 0, downloadedAt: record.downloadedAt
            )
            record.activity = DownloadActivity(phase: .waitingForServer, sourceOperation: source.operation)
            try fileStore.persist(record)
            activities[record.id] = record.activity
            refreshDisplayedRecords()
            Task { await cacheArtwork(for: record, session: session) }

            DiagnosticsHub.shared.record(.downloadQueued)
            coordinator.startDownload(from: source.url, recordID: record.id)
        } catch {
            let currentID = OfflineDownloadFileStore.recordID(itemID: itemID, serverID: session.server.id, userID: session.user.id)
            guard generation == nil || fileStore.record(forRecordID: currentID)?.downloadedAt == generation else { return }
            activeItemIDs.remove(itemID)
            let gusError = GusError(from: error)
            let recordID = OfflineDownloadFileStore.recordID(itemID: itemID, serverID: session.server.id, userID: session.user.id)
            if var failed = fileStore.record(forRecordID: recordID), failed.downloadedAt == generation {
                failed.status = .failed(gusError.localizedDescription)
                failed.activity?.transition(to: .failed)
                fileStore.update(failed)
                activities[recordID] = failed.activity
                refreshDisplayedRecords()
            }
            guard !gusError.isCancellation else { return }
            logger.error("Download failed: \(gusError.localizedDescription, privacy: .private)")
            if loadedServerID == session.server.id, loadedUserID == session.user.id,
               fileStore.record(forRecordID: recordID)?.downloadedAt == generation || generation == nil
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
                    self.activities[record.id] = paused.activity
                    paused.status = .paused
                    paused.resumeData = resumeData
                    paused.progress = paused.activity?.progress ?? record.progress
                    self.fileStore.update(paused)
                    self.refreshDisplayedRecords()
                    DiagnosticsHub.shared.record(.downloadPaused)
                    continuation.resume()
                }
            }
        }
    }

    func resume(itemID: String, session: SessionStore) async {
        guard var record = records.first(where: { $0.item.id == itemID }),
              record.serverID == session.server.id, record.userID == session.user.id,
              loadedServerID == session.server.id, loadedUserID == session.user.id else { return }

        guard let resumeData = record.resumeData else {
            errorMessage = String(localized: "Not enough resume data — restarting download.", comment: "Download resume fallback message")
            await download(record.item, session: session)
            return
        }

        record.activity = activities[record.id] ?? record.activity ?? DownloadActivity()
        record.activity?.transition(to: .waitingForServer)
        activities[record.id] = record.activity
        record.status = .downloading(record.progress)
        record.progress = record.activity?.progress ?? record.progress
        record.resumeData = nil
        fileStore.update(record)
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
            activities[record.id] = record.activity
            fileStore.update(record)
        }
        refreshDisplayedRecords()
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
        activities[recordID] = observed
        record.activity = observed
        if let progress = observed.progress {
            record.progress = progress
        }
        if let index = records.firstIndex(where: { $0.id == recordID }) {
            records[index] = record
        }
        if Date().timeIntervalSince(lastCheckpoint[recordID] ?? .distantPast) >= 5 {
            fileStore.update(record)
            lastCheckpoint[recordID] = Date()
        }
    }

    func downloadSessionCoordinatorDidFinishBackgroundEvents(_ coordinator: DownloadSessionCoordinating) async {
        DownloadBackgroundEvents.shared.finish()
    }

    func downloadSessionCoordinator(
        _ coordinator: DownloadSessionCoordinating,
        finalizeDownloadedFileAt location: URL,
        recordID: String
    ) -> Bool {
        guard var record = fileStore.record(forRecordID: recordID) else { return true }
        if record.status.isComplete || record.status == .paused {
            return true
        }
        // A retained staged file can be retried after a failed finalization.
        if case .failed = record.status {
            record.status = .downloading(record.progress)
            fileStore.update(record)
        }
        downloadSessionCoordinator(coordinator, didFinishDownloadingTo: location, recordID: recordID)
        return fileStore.record(forRecordID: recordID)?.status.isComplete == true
    }

    func downloadSessionCoordinator(
        _ coordinator: DownloadSessionCoordinating,
        didFinishDownloadingTo location: URL,
        recordID: String
    ) {
        guard let record = record(forRecordID: recordID), record.status.isActive else { return }
        activities[recordID]?.transition(to: .saving)
        do {
            let fileExtension = URL(fileURLWithPath: record.filePath).pathExtension
            if ["mp4", "m4v", "mov"].contains(fileExtension.lowercased()) {
                try OfflineMP4Compatibility.normalizeHEVCTag(in: location)
            }
            _ = try fileStore.persistDownloadedFile(
                location,
                item: record.item,
                serverID: record.serverID,
                userID: record.userID,
                fileExtension: fileExtension.isEmpty ? "mp4" : fileExtension,
                downloadedAt: record.downloadedAt
            )
            if let itemID = record.item.id {
                activeItemIDs.remove(itemID)
            }
            activities.removeValue(forKey: recordID)
            lastCheckpoint.removeValue(forKey: recordID)
            refreshDisplayedRecords()
            DiagnosticsHub.shared.record(.downloadCompleted)
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
        guard var record = record(forRecordID: recordID), !record.status.isComplete else { return }
        let gusError = GusError(from: error)
        record.activity = activities[recordID] ?? record.activity
        record.activity?.transition(to: .failed)
        activities[recordID] = record.activity
        record.status = .failed(gusError.localizedDescription)
        record.resumeData = resumeData
        fileStore.update(record)
        if let itemID = record.item.id {
            activeItemIDs.remove(itemID)
        }
        refreshDisplayedRecords()
        DiagnosticsHub.shared.record(.downloadFailed)
        if loadedServerID == record.serverID, loadedUserID == record.userID {
            errorMessage = gusError.localizedDescription
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
            try fileStore.persist(record)
            session.references.recordReplacement(from: snapshot.remoteReference ?? MediaReference(item: snapshot.item, scope: scope), to: item)
            OfflinePlaybackProgressStore.shared.offerTransfer(from: record.item.id, to: item, scope: scope)
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
                    try fileStore.persist(record)
                    continue
                }
                record.remoteReference = MediaReference(item: item, scope: scope)
                record.remoteUnavailable = false
                try fileStore.persist(record)
                if item.id != snapshot.item.id {
                    OfflinePlaybackProgressStore.shared.offerTransfer(from: snapshot.item.id, to: item, scope: scope)
                }
            } catch {
                if GusError(from: error) == .unauthorized {
                    session.onUnauthorized(); return
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
        guard fileStore.localArtworkURL(for: record) == nil,
              fileStore.record(forRecordID: record.id)?.downloadedAt == record.downloadedAt,
              !artworkRequests.contains(record.id),
              let url = session.mediaProvider.primaryImageURL(for: record.remoteReference?.item ?? record.item, context: .posterRail) else { return }
        artworkRequests.insert(record.id)
        defer { artworkRequests.remove(record.id) }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            if let token = session.client.accessToken {
                request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
                  http.mimeType?.hasPrefix("image/") == true,
                  fileStore.record(forRecordID: record.id)?.downloadedAt == record.downloadedAt else { return }
            try fileStore.persistArtwork(data, for: record)
            refreshDisplayedRecords()
        } catch {
            // A failed thumbnail never invalidates downloaded media. Foreground entry retries.
            logger.debug("Download artwork remains unavailable")
        }
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
            // watchOS has no "important usage" capacity query; plain volume capacity is
            // the closest available signal there.
            #if os(watchOS)
                let values = try supportURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
                let available = values.volumeAvailableCapacity.map(Int64.init)
            #else
                let values = try supportURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                let available = values.volumeAvailableCapacityForImportantUsage
            #endif
            if let available, available < Self.minimumFreeBytes {
                throw GusError.server(String(localized: "Not enough free space to start another download.", comment: "Low disk space download error"))
            }
        #endif
    }

    private func record(forRecordID recordID: String) -> OfflineDownloadRecord? {
        fileStore.record(forRecordID: recordID)
    }
}
