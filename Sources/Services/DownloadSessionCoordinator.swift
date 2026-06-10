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
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didFinishDownloadingTo location: URL, recordID: String)
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didFailWith error: Error, resumeData: Data?, recordID: String)
}

extension DownloadSessionCoordinatorEventHandler {
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didReconnectActiveRecordIDs recordIDs: Set<String>) {}
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didUpdateProgress progress: Double, recordID: String) {}
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didFinishDownloadingTo location: URL, recordID: String) {}
    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didFailWith error: Error, resumeData: Data?, recordID: String) {}
}

final class DownloadSessionCoordinator: NSObject, DownloadSessionCoordinating, URLSessionDownloadDelegate {
    static let shared = DownloadSessionCoordinator()
    static let backgroundIdentifier = "dev.ericslutz.gus.downloads"

    weak var eventHandler: DownloadSessionCoordinatorEventHandler?

    private let logger = Logger(category: .downloads)
    private let lock = NSLock()
    private var tasksByRecordID: [String: URLSessionDownloadTask] = [:]
    private var recordIDByTaskID: [Int: String] = [:]
    private var pauseCompletions: [String: (Data?) -> Void] = [:]
    private var pausingRecordIDs: Set<String> = []

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundIdentifier)
        // We intentionally keep a pure SwiftUI lifecycle (no AppDelegate), so we do not
        // service `handleEventsForBackgroundURLSession` background relaunches. Transfers
        // still complete in the system daemon while suspended/terminated; completed events
        // are replayed via `reconnectActiveTasks()` on the next launch. Disabling launch
        // events avoids the system spinning the app up only to find no handler.
        configuration.sessionSendsLaunchEvents = false
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 60 * 6
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func setEventHandler(_ eventHandler: DownloadSessionCoordinatorEventHandler?) {
        self.eventHandler = eventHandler
    }

    func startDownload(from url: URL, recordID: String) {
        let task = session.downloadTask(with: url)
        track(task, recordID: recordID)
        task.resume()
    }

    func resumeDownload(with resumeData: Data, recordID: String) {
        let task = session.downloadTask(withResumeData: resumeData)
        track(task, recordID: recordID)
        task.resume()
    }

    func pause(recordID: String, completion: @escaping (Data?) -> Void) {
        guard let task = task(for: recordID) else {
            completion(nil)
            return
        }

        lock.withLock {
            pauseCompletions[recordID] = completion
            pausingRecordIDs.insert(recordID)
        }

        task.cancel { [weak self] resumeData in
            guard let self else { return }
            let completion = self.lock.withLock { self.pauseCompletions.removeValue(forKey: recordID) }
            removeTask(recordID: recordID)
            completion?(resumeData)
        }
    }

    func cancel(recordID: String) {
        guard let task = task(for: recordID) else { return }
        lock.withLock {
            pausingRecordIDs.remove(recordID)
            pauseCompletions.removeValue(forKey: recordID)
        }
        task.cancel()
        removeTask(recordID: recordID)
    }

    func reconnectActiveTasks() {
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            var activeRecordIDs = Set<String>()
            for task in tasks {
                guard let downloadTask = task as? URLSessionDownloadTask,
                      let recordID = downloadTask.taskDescription
                else { continue }
                track(downloadTask, recordID: recordID)
                activeRecordIDs.insert(recordID)
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                eventHandler?.downloadSessionCoordinator(self, didReconnectActiveRecordIDs: activeRecordIDs)
            }
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
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        Task { @MainActor [weak self] in
            guard let self else { return }
            eventHandler?.downloadSessionCoordinator(self, didUpdateProgress: min(max(progress, 0), 1), recordID: recordID)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let recordID = recordID(for: downloadTask) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            eventHandler?.downloadSessionCoordinator(self, didFinishDownloadingTo: location, recordID: recordID)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let recordID = recordID(for: task) else { return }
        defer { removeTask(recordID: recordID) }

        guard let error else { return }

        let wasPauseCancellation = lock.withLock { pausingRecordIDs.remove(recordID) != nil }
        if wasPauseCancellation, (error as NSError).code == NSURLErrorCancelled {
            return
        }

        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        logger.error("Background download failed for \(recordID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            eventHandler?.downloadSessionCoordinator(self, didFailWith: error, resumeData: resumeData, recordID: recordID)
        }
    }

    private func track(_ task: URLSessionDownloadTask, recordID: String) {
        task.taskDescription = recordID
        lock.withLock {
            tasksByRecordID[recordID] = task
            recordIDByTaskID[task.taskIdentifier] = recordID
        }
    }

    private func task(for recordID: String) -> URLSessionDownloadTask? {
        lock.withLock { tasksByRecordID[recordID] }
    }

    private func recordID(for task: URLSessionTask) -> String? {
        if let taskDescription = task.taskDescription {
            return taskDescription
        }
        return lock.withLock { recordIDByTaskID[task.taskIdentifier] }
    }

    private func removeTask(recordID: String) {
        lock.withLock {
            if let task = tasksByRecordID.removeValue(forKey: recordID) {
                recordIDByTaskID.removeValue(forKey: task.taskIdentifier)
            }
        }
    }
}
