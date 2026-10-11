import Foundation
import OSLog

protocol DownloadSessionCoordinating: AnyObject {
    func setEventHandler(_ eventHandler: DownloadSessionCoordinatorEventHandler?)
    func startDownload(from url: URL, recordID: String)
    func resumeDownload(with resumeData: Data, recordID: String)
    func pause(recordID: String, completion: @escaping (Data?) -> Void)
    func cancel(recordID: String)
    func reconnectActiveTasks()
}

@MainActor
protocol DownloadSessionCoordinatorEventHandler: AnyObject {
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didReconnectActiveRecordIDs recordIDs: Set<String>)
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didUpdateProgress progress: Double, recordID: String)
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didUpdateActivity activity: DownloadActivity, recordID: String)
    func downloadSessionCoordinatorDidFinishBackgroundEvents(_ coordinator: DownloadSessionCoordinating) async
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didFinishDownloadingTo location: URL, recordID: String)
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, finalizeDownloadedFileAt location: URL, recordID: String) -> Bool
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didFailWith error: Error, resumeData: Data?, recordID: String)
}

extension DownloadSessionCoordinatorEventHandler {
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didReconnectActiveRecordIDs recordIDs: Set<String>) {}
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didUpdateProgress progress: Double, recordID: String) {}
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didUpdateActivity activity: DownloadActivity, recordID: String) {
        downloadSessionCoordinator(coordinator, didUpdateProgress: activity.progress ?? 0, recordID: recordID)
    }

    func downloadSessionCoordinatorDidFinishBackgroundEvents(_ coordinator: DownloadSessionCoordinating) async {}
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didFinishDownloadingTo location: URL, recordID: String) {}
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, finalizeDownloadedFileAt location: URL, recordID: String) -> Bool {
        downloadSessionCoordinator(coordinator, didFinishDownloadingTo: location, recordID: recordID)
        return true
    }

    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didFailWith error: Error, resumeData: Data?, recordID: String) {}
}

/// URLSession invokes this delegate off the main actor. Mutable event/task state is
/// protected by `lock`; session creation has its own lock; UI delivery is main-actor
/// isolated. The unchecked conformance records this audited Foundation boundary rather
/// than pretending the delegate callbacks execute on the main actor.
final class DownloadSessionCoordinator: NSObject, DownloadSessionCoordinating, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = DownloadSessionCoordinator()
    static let backgroundIdentifier = "dev.ericslutz.gus.downloads"

    private weak var eventHandler: DownloadSessionCoordinatorEventHandler?
    private let logger = Logger(category: .downloads)
    private let lock = NSLock()
    private let sessionLock = NSLock()
    private var cachedSession: URLSession?
    private let stagingDirectory: URL
    private var tasksByRecordID: [String: URLSessionDownloadTask] = [:]
    private var recordIDByTaskID: [Int: String] = [:]
    private var pauseCompletions = DownloadPauseCompletionHandlers()
    private var pausingTaskIDs: Set<Int> = []
    private var cancelledTaskIDs: Set<Int> = []
    private var invalidatedRecordIDs: Set<String> = []
    private var activities: [String: DownloadActivity] = [:]
    private var pendingEvents: [Event] = []
    private var isDeliveringEvents = false
    private var queuedStagedURLs: Set<URL> = []

    private enum Event {
        case reconnected(Set<String>)
        case activity(DownloadActivity, String)
        case finished(URL, String)
        case failed(Error, Data?, String)
        case backgroundFinished
    }

    init(stagingDirectory: URL? = nil) {
        self.stagingDirectory = stagingDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DownloadStaging", isDirectory: true)
        super.init()
    }

    private var session: URLSession {
        sessionLock.withLock {
            if let cachedSession {
                return cachedSession
            }
            let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundIdentifier)
            configuration.sessionSendsLaunchEvents = true
            configuration.isDiscretionary = false
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60 * 60 * 6
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            cachedSession = session
            return session
        }
    }

    func setEventHandler(_ eventHandler: DownloadSessionCoordinatorEventHandler?) {
        lock.withLock { self.eventHandler = eventHandler }
        deliverPendingEvents()
    }

    func startDownload(from url: URL, recordID: String) {
        cancel(recordID: recordID)
        _ = lock.withLock { invalidatedRecordIDs.remove(recordID) }
        let task = session.downloadTask(with: url)
        track(task, recordID: recordID)
        updateActivity(recordID: recordID) { $0.transition(to: .waitingForServer) }
        task.resume()
    }

    func resumeDownload(with resumeData: Data, recordID: String) {
        let previousActivity = lock.withLock { activities[recordID] }
        cancel(recordID: recordID)
        _ = lock.withLock { invalidatedRecordIDs.remove(recordID) }
        if let previousActivity {
            lock.withLock { activities[recordID] = previousActivity }
        }
        let task = session.downloadTask(withResumeData: resumeData)
        track(task, recordID: recordID)
        updateActivity(recordID: recordID) { $0.transition(to: .waitingForServer) }
        task.resume()
    }

    func pause(recordID: String, completion: @escaping (Data?) -> Void) {
        guard let task = task(for: recordID) else {
            completion(nil)
            return
        }
        let shouldCancel = lock.withLock {
            let isFirstRequest = pauseCompletions.append(completion, recordID: recordID, taskID: task.taskIdentifier)
            pausingTaskIDs.insert(task.taskIdentifier)
            return isFirstRequest
        }
        guard shouldCancel else { return }
        updateActivity(recordID: recordID) { $0.transition(to: .paused) }
        task.cancel { [weak self] resumeData in
            guard let self else { return }
            let completion = self.lock.withLock { self.pauseCompletions.take(taskID: task.taskIdentifier) }
            self.removeTask(recordID: recordID, taskID: task.taskIdentifier)
            completion?(resumeData)
        }
    }

    func cancel(recordID: String) {
        let cancellation = lock.withLock { () -> (URLSessionDownloadTask?, ((Data?) -> Void)?, [URL]) in
            invalidatedRecordIDs.insert(recordID)
            let task = tasksByRecordID[recordID]
            if let task {
                pausingTaskIDs.remove(task.taskIdentifier)
                cancelledTaskIDs.insert(task.taskIdentifier)
            }
            let pauseCompletion = pauseCompletions.take(recordID: recordID)
            activities.removeValue(forKey: recordID)
            var stagedURLs: [URL] = []
            pendingEvents.removeAll { event in
                switch event {
                case let .activity(_, id), let .failed(_, _, id):
                    return id == recordID
                case let .finished(location, id):
                    if id == recordID {
                        stagedURLs.append(location)
                        queuedStagedURLs.remove(location)
                        return true
                    }
                    return false
                case .reconnected, .backgroundFinished:
                    return false
                }
            }
            return (task, pauseCompletion, stagedURLs)
        }
        cancellation.0?.cancel()
        if let task = cancellation.0 {
            removeTask(recordID: recordID, taskID: task.taskIdentifier)
        }
        cancellation.1?(nil)
        // Failed finalization may have left a file outside the current event queue.
        // Purge it synchronously before this deterministic record id is reused.
        var locations = Set(cancellation.2)
        if let files = try? FileManager.default.contentsOfDirectory(at: stagingDirectory, includingPropertiesForKeys: nil) {
            for manifest in files where manifest.pathExtension == "json" {
                guard let data = try? Data(contentsOf: manifest),
                      let id = try? JSONDecoder().decode(String.self, from: data), id == recordID
                else { continue }
                locations.insert(manifest.deletingPathExtension().appendingPathExtension("download"))
            }
        }
        for location in locations {
            try? FileManager.default.removeItem(at: location)
            try? FileManager.default.removeItem(at: manifestURL(for: location))
        }
    }

    func reconnectActiveTasks() {
        recoverStagedFiles()
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            var activeRecordIDs = Set<String>()
            var snapshots: [(String, URLSessionDownloadTask)] = []
            for task in tasks {
                guard let downloadTask = task as? URLSessionDownloadTask,
                      let recordID = downloadTask.taskDescription
                else { continue }
                guard self.track(downloadTask, recordID: recordID) else { continue }
                activeRecordIDs.insert(recordID)
                snapshots.append((recordID, downloadTask))
            }
            self.enqueue(.reconnected(activeRecordIDs))
            for (recordID, task) in snapshots {
                guard self.recordID(for: task) == recordID else { continue }
                self.updateActivity(recordID: recordID, taskID: task.taskIdentifier) { activity in
                    activity.resetTransferSampling()
                    activity.recordTransfer(receivedBytes: task.countOfBytesReceived, expectedBytes: task.countOfBytesExpectedToReceive)
                    if task.state == .suspended {
                        activity.transition(to: .paused)
                    } else if activity.receivedBytes == 0 {
                        activity.transition(to: .waitingForServer)
                    }
                }
            }
        }
    }

    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        guard let recordID = recordID(for: task) else { return }
        updateActivity(recordID: recordID, taskID: task.taskIdentifier) { $0.transition(to: .waitingForConnectivity) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        guard let recordID = recordID(for: downloadTask) else { return }
        updateActivity(recordID: recordID, taskID: downloadTask.taskIdentifier) { activity in
            activity.resetTransferSampling()
            activity.receivedBytes = max(0, fileOffset)
            activity.expectedBytes = expectedTotalBytes > 0 ? expectedTotalBytes : nil
            activity.transition(to: .waitingForServer)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let recordID = recordID(for: downloadTask) else { return }
        updateActivity(recordID: recordID, taskID: downloadTask.taskIdentifier) {
            $0.recordTransfer(receivedBytes: totalBytesWritten, expectedBytes: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let recordID = recordID(for: downloadTask) else { return }
        // URLSession reclaims its temporary URL on return. Persist the file and a
        // small record-id sidecar before scheduling main-actor finalization.
        let stagedURL = stagingDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("download")
        do {
            try Self.validateResponse(downloadTask.response)
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            var excludedDirectory = stagingDirectory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try excludedDirectory.setResourceValues(values)
            try JSONEncoder().encode(recordID).write(to: manifestURL(for: stagedURL), options: .atomic)
            try FileManager.default.moveItem(at: location, to: stagedURL)
            updateActivity(recordID: recordID, taskID: downloadTask.taskIdentifier) { activity in
                let bytes = (try? stagedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? activity.receivedBytes
                activity.receivedBytes = bytes
                activity.transition(to: .saving)
            }
            enqueueStagedFile(stagedURL, recordID: recordID, taskID: downloadTask.taskIdentifier)
        } catch {
            logger.error("Could not preserve completed download for \(recordID, privacy: .private): \(error.localizedDescription, privacy: .private)")
            updateActivity(recordID: recordID, taskID: downloadTask.taskIdentifier) { $0.transition(to: .failed) }
            enqueue(.failed(error, nil, recordID), taskID: downloadTask.taskIdentifier)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let recordID = recordID(for: task) else { return }
        defer { removeTask(recordID: recordID, taskID: task.taskIdentifier) }
        guard let error else { return }
        let wasPauseCancellation = lock.withLock { pausingTaskIDs.remove(task.taskIdentifier) != nil }
        if wasPauseCancellation, (error as NSError).code == NSURLErrorCancelled {
            return
        }
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        logger.error("Background download failed for \(recordID, privacy: .private): \(error.localizedDescription, privacy: .private)")
        updateActivity(recordID: recordID, taskID: task.taskIdentifier) { $0.transition(to: .failed) }
        enqueue(.failed(error, resumeData, recordID), taskID: task.taskIdentifier)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        enqueue(.backgroundFinished)
    }

    /// URLSession can successfully download an HTTP error document. It must not
    /// become local media merely because transporting the response body succeeded.
    static func validateResponse(_ response: URLResponse?) throws {
        guard let response = response as? HTTPURLResponse else { return }
        guard (200 ..< 300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
    }

    private func updateActivity(recordID: String, taskID: Int? = nil, update: (inout DownloadActivity) -> Void) {
        lock.withLock {
            guard !invalidatedRecordIDs.contains(recordID), taskID.map({ !cancelledTaskIDs.contains($0) }) ?? true else { return }
            var activity = activities[recordID] ?? DownloadActivity()
            update(&activity)
            activities[recordID] = activity
            pendingEvents.append(.activity(activity, recordID))
        }
        deliverPendingEvents()
    }

    private func enqueue(_ event: Event, taskID: Int? = nil) {
        lock.withLock {
            guard taskID.map({ !cancelledTaskIDs.contains($0) }) ?? true else { return }
            pendingEvents.append(event)
        }
        deliverPendingEvents()
    }

    /// One main-actor consumer preserves delegate order, including the OS completion
    /// signal. No staged file is discarded while the store handler is unavailable.
    private func deliverPendingEvents() {
        let shouldStart = lock.withLock {
            guard !isDeliveringEvents, eventHandler != nil, !pendingEvents.isEmpty else { return false }
            isDeliveringEvents = true
            return true
        }
        guard shouldStart else { return }
        Task { @MainActor [self] in
            while let (event, handler) = nextEvent() {
                switch event {
                case let .reconnected(ids):
                    // A foreground start may occur after getAllTasks took its
                    // snapshot. Include those mapped live tasks before reconciling.
                    let currentIDs = lock.withLock {
                        Set(tasksByRecordID.compactMap { id, task in
                            task.state == .running || task.state == .suspended ? id : nil
                        })
                    }
                    handler.downloadSessionCoordinator(self, didReconnectActiveRecordIDs: ids.union(currentIDs))
                case let .activity(activity, recordID):
                    handler.downloadSessionCoordinator(self, didUpdateActivity: activity, recordID: recordID)
                case let .finished(location, recordID):
                    if handler.downloadSessionCoordinator(self, finalizeDownloadedFileAt: location, recordID: recordID) {
                        try? FileManager.default.removeItem(at: location)
                        try? FileManager.default.removeItem(at: manifestURL(for: location))
                    }
                    _ = lock.withLock { queuedStagedURLs.remove(location) }
                case let .failed(error, resumeData, recordID):
                    handler.downloadSessionCoordinator(self, didFailWith: error, resumeData: resumeData, recordID: recordID)
                case .backgroundFinished:
                    await handler.downloadSessionCoordinatorDidFinishBackgroundEvents(self)
                }
            }
        }
    }

    private func nextEvent() -> (Event, DownloadSessionCoordinatorEventHandler)? {
        lock.withLock {
            guard let eventHandler, !pendingEvents.isEmpty else {
                isDeliveringEvents = false
                return nil
            }
            return (pendingEvents.removeFirst(), eventHandler)
        }
    }

    private func manifestURL(for stagedURL: URL) -> URL {
        stagedURL.deletingPathExtension().appendingPathExtension("json")
    }

    private func enqueueStagedFile(_ location: URL, recordID: String, taskID: Int? = nil) {
        let accepted = lock.withLock { () -> Bool in
            guard !invalidatedRecordIDs.contains(recordID),
                  taskID.map({ !cancelledTaskIDs.contains($0) }) ?? true,
                  FileManager.default.fileExists(atPath: location.path)
            else { return false }
            if queuedStagedURLs.insert(location).inserted {
                pendingEvents.append(.finished(location, recordID))
            }
            return true
        }
        if accepted {
            deliverPendingEvents()
        } else {
            try? FileManager.default.removeItem(at: location)
            try? FileManager.default.removeItem(at: manifestURL(for: location))
        }
    }

    private func recoverStagedFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: stagingDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "download" {
            guard let data = try? Data(contentsOf: manifestURL(for: file)),
                  let recordID = try? JSONDecoder().decode(String.self, from: data)
            else { continue }
            enqueueStagedFile(file, recordID: recordID)
        }
    }

    @discardableResult
    private func track(_ task: URLSessionDownloadTask, recordID: String) -> Bool {
        lock.withLock {
            guard !cancelledTaskIDs.contains(task.taskIdentifier), task.state != .canceling, task.state != .completed else { return false }
            if let activeTask = tasksByRecordID[recordID], activeTask.taskIdentifier != task.taskIdentifier {
                return false
            }
            task.taskDescription = recordID
            tasksByRecordID[recordID] = task
            recordIDByTaskID[task.taskIdentifier] = recordID
            return true
        }
    }

    private func task(for recordID: String) -> URLSessionDownloadTask? {
        lock.withLock { tasksByRecordID[recordID] }
    }

    private func recordID(for task: URLSessionTask) -> String? {
        lock.withLock {
            guard !cancelledTaskIDs.contains(task.taskIdentifier) else { return nil }
            guard let recordID = task.taskDescription ?? recordIDByTaskID[task.taskIdentifier] else { return nil }
            if let activeTask = tasksByRecordID[recordID], activeTask.taskIdentifier != task.taskIdentifier {
                return nil
            }
            return recordID
        }
    }

    private func removeTask(recordID: String, taskID: Int) {
        lock.withLock {
            recordIDByTaskID.removeValue(forKey: taskID)
            if tasksByRecordID[recordID]?.taskIdentifier == taskID {
                tasksByRecordID.removeValue(forKey: recordID)
            }
        }
    }
}

/// Multiple Pause requests share one native resume-data operation. Task identity
/// prevents a late cancellation callback from consuming a replacement task's waiters.
struct DownloadPauseCompletionHandlers {
    private struct Pending {
        let recordID: String
        var handlers: [(Data?) -> Void]
    }

    private var pending: [Int: Pending] = [:]

    /// Returns true only when the caller must begin native cancellation.
    mutating func append(_ handler: @escaping (Data?) -> Void, recordID: String, taskID: Int) -> Bool {
        if pending[taskID] != nil {
            pending[taskID]?.handlers.append(handler)
            return false
        }
        pending[taskID] = Pending(recordID: recordID, handlers: [handler])
        return true
    }

    mutating func take(taskID: Int) -> ((Data?) -> Void)? {
        Self.combined(pending.removeValue(forKey: taskID)?.handlers ?? [])
    }

    mutating func take(recordID: String) -> ((Data?) -> Void)? {
        let taskIDs = pending.filter { $0.value.recordID == recordID }.map(\.key)
        let handlers = taskIDs.flatMap { pending.removeValue(forKey: $0)?.handlers ?? [] }
        return Self.combined(handlers)
    }

    private static func combined(_ handlers: [(Data?) -> Void]) -> ((Data?) -> Void)? {
        guard !handlers.isEmpty else { return nil }
        return { resumeData in
            for handler in handlers {
                handler(resumeData)
            }
        }
    }
}
