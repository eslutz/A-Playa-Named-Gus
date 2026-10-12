import Foundation
@testable import Gus
import Testing

@Suite("Download activity")
struct DownloadActivityTests {
    private let origin = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("repeated pause requests share resume data and complete every waiter exactly once")
    func repeatedPauseCompletions() throws {
        var handlers = DownloadPauseCompletionHandlers()
        var results: [Data?] = []
        let first = handlers.append({ results.append($0) }, recordID: "record-1", taskID: 1)
        let second = handlers.append({ results.append($0) }, recordID: "record-1", taskID: 1)
        #expect(first)
        #expect(!second)
        let pendingCompletion = handlers.take(taskID: 1)
        let complete = try #require(pendingCompletion)
        let data = Data("resume data".utf8)
        complete(data)
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0 == data })
        let consumedCompletion = handlers.take(taskID: 1)
        #expect(consumedCompletion == nil)
    }

    @Test("cancel drains repeated pause waiters without stealing a restarted task's completion")
    func pauseCancellationAndReplacement() throws {
        var handlers = DownloadPauseCompletionHandlers()
        var cancelledResults: [Data?] = []
        var replacementResults: [Data?] = []
        _ = handlers.append({ cancelledResults.append($0) }, recordID: "record-1", taskID: 1)
        _ = handlers.append({ cancelledResults.append($0) }, recordID: "record-1", taskID: 1)
        let pendingCancellation = handlers.take(recordID: "record-1")
        let cancel = try #require(pendingCancellation)
        cancel(nil)
        #expect(cancelledResults.count == 2)
        #expect(cancelledResults.allSatisfy { $0 == nil })
        let firstReplacement = handlers.append({ replacementResults.append($0) }, recordID: "record-1", taskID: 2)
        #expect(firstReplacement)
        let oldTaskCompletion = handlers.take(taskID: 1)
        #expect(oldTaskCompletion == nil)
        let pendingReplacement = handlers.take(taskID: 2)
        let completeReplacement = try #require(pendingReplacement)
        let data = Data("replacement resume data".utf8)
        completeReplacement(data)
        #expect(replacementResults == [data])
        #expect(cancelledResults.count == 2)
    }

    @Test("unknown Content-Length exposes bytes without inventing a percentage or ETA")
    func unknownTotal() {
        var activity = DownloadActivity(startedAt: origin)
        activity.recordTransfer(receivedBytes: 4096, expectedBytes: NSURLSessionTransferSizeUnknown, at: origin)
        activity.recordTransfer(receivedBytes: 8192, expectedBytes: 0, at: origin.addingTimeInterval(1))
        #expect(activity.phase == .downloading)
        #expect(activity.receivedBytes == 8192)
        #expect(activity.expectedBytes == nil)
        #expect(activity.progress == nil)
        #expect(activity.bytesPerSecond(at: origin.addingTimeInterval(1)) == 4096)
        #expect(activity.estimatedTimeRemaining(at: origin.addingTimeInterval(10)) == nil)
        #expect(activity.preparationProgress == nil)
    }

    @Test("rate samples use one-second windows and ETA warms up for five seconds")
    func rateWindowsAndWarmup() {
        var activity = DownloadActivity(startedAt: origin)
        activity.recordTransfer(receivedBytes: 100, expectedBytes: 10000, at: origin)
        activity.recordTransfer(receivedBytes: 150, expectedBytes: 10000, at: origin.addingTimeInterval(0.5))
        #expect(activity.bytesPerSecond(at: origin.addingTimeInterval(0.5)) == nil)
        activity.recordTransfer(receivedBytes: 200, expectedBytes: 10000, at: origin.addingTimeInterval(1))
        #expect(activity.bytesPerSecond(at: origin.addingTimeInterval(1)) == 100)
        #expect(activity.estimatedTimeRemaining(at: origin.addingTimeInterval(4.9)) == nil)
        activity.recordTransfer(receivedBytes: 600, expectedBytes: 10000, at: origin.addingTimeInterval(5))
        #expect(activity.estimatedTimeRemaining(at: origin.addingTimeInterval(5)) == 94)
        #expect(activity.progress == 0.06)
    }

    @Test("stalled transfers hide stale speed and ETA")
    func stalledTransfer() {
        var activity = DownloadActivity(startedAt: origin)
        activity.recordTransfer(receivedBytes: 100, expectedBytes: 10000, at: origin)
        activity.recordTransfer(receivedBytes: 600, expectedBytes: 10000, at: origin.addingTimeInterval(5))
        #expect(activity.bytesPerSecond(at: origin.addingTimeInterval(25)) == 100)
        #expect(activity.bytesPerSecond(at: origin.addingTimeInterval(25.1)) == nil)
        #expect(activity.estimatedTimeRemaining(at: origin.addingTimeInterval(25.1)) == nil)
        #expect(activity.receivedBytes == 600)
    }

    @Test("pause and connectivity transitions reset estimates while retaining received bytes")
    func pausedAndResumed() {
        var activity = DownloadActivity(startedAt: origin)
        activity.recordTransfer(receivedBytes: 100, expectedBytes: 10000, at: origin)
        activity.recordTransfer(receivedBytes: 600, expectedBytes: 10000, at: origin.addingTimeInterval(5))
        activity.transition(to: .paused, at: origin.addingTimeInterval(6))
        #expect(activity.receivedBytes == 600)
        #expect(activity.bytesPerSecond(at: origin.addingTimeInterval(6)) == nil)
        activity.recordTransfer(receivedBytes: 700, expectedBytes: 10000, at: origin.addingTimeInterval(60))
        activity.recordTransfer(receivedBytes: 800, expectedBytes: 10000, at: origin.addingTimeInterval(61))
        #expect(activity.bytesPerSecond(at: origin.addingTimeInterval(61)) == 100)
        #expect(activity.estimatedTimeRemaining(at: origin.addingTimeInterval(61)) == nil)
        activity.transition(to: .waitingForConnectivity, at: origin.addingTimeInterval(62))
        #expect(activity.receivedBytes == 800)
        #expect(activity.bytesPerSecond(at: origin.addingTimeInterval(62)) == nil)
    }

    @Test("counter regression starts fresh sampling and known progress stays bounded")
    func restartAndBounds() {
        var activity = DownloadActivity(startedAt: origin)
        activity.recordTransfer(receivedBytes: 100, expectedBytes: 1000, at: origin)
        activity.recordTransfer(receivedBytes: 600, expectedBytes: 1000, at: origin.addingTimeInterval(5))
        activity.recordTransfer(receivedBytes: 20, expectedBytes: 1000, at: origin.addingTimeInterval(6))
        #expect(activity.bytesPerSecond(at: origin.addingTimeInterval(6)) == nil)
        activity.recordTransfer(receivedBytes: 1100, expectedBytes: 1000, at: origin.addingTimeInterval(7))
        #expect(activity.progress == 1)
        #expect(activity.estimatedTimeRemaining(at: origin.addingTimeInterval(15)) == nil)
    }

    @Test("activity including source intent and sampling survives Codable persistence")
    func persistenceRoundTrip() throws {
        var activity = DownloadActivity(startedAt: origin, sourceOperation: .remuxed)
        activity.recordTransfer(receivedBytes: 100, expectedBytes: nil, at: origin)
        activity.recordTransfer(receivedBytes: 600, expectedBytes: nil, at: origin.addingTimeInterval(5))
        let restored = try JSONDecoder().decode(DownloadActivity.self, from: JSONEncoder().encode(activity))
        #expect(restored == activity)
        #expect(restored.sourceOperation == .remuxed)
        #expect(restored.preparationProgress == nil)
    }

    @Test("HTTP error response bodies are rejected before offline media finalization", arguments: [401, 404, 500])
    func httpErrorResponses(status: Int) throws {
        let url = try #require(URL(string: "https://example.com/media"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        #expect(throws: URLError.self) { try DownloadSessionCoordinator.validateResponse(response) }
    }

    @Test("successful HTTP downloads and synthetic delegate callbacks can finalize", arguments: [200, 206])
    func successfulResponses(status: Int) throws {
        let url = try #require(URL(string: "https://example.com/media"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        try DownloadSessionCoordinator.validateResponse(response)
        try DownloadSessionCoordinator.validateResponse(nil)
    }

    @MainActor
    @Test("queued completion retains its file until a handler attaches and OS completion follows finalization")
    func backgroundFinalizationOrdering() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("CFNetworkDownload.tmp")
        let content = Data("completed media".utf8)
        try content.write(to: source)
        let staging = directory.appendingPathComponent("Staging")
        let coordinator = DownloadSessionCoordinator(stagingDirectory: staging)
        let task = try URLSession.shared.downloadTask(with: #require(URL(string: "https://example.com/media")))
        task.taskDescription = "record-1"
        coordinator.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: source)
        coordinator.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        let files = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
        let staged = try #require(files.first { $0.pathExtension == "download" })
        #expect(try Data(contentsOf: staged) == content)

        let handler = ActivityEventTestHandler()
        await withCheckedContinuation { continuation in
            handler.onBackgroundFinished = { continuation.resume() }
            coordinator.setEventHandler(handler)
        }
        #expect(handler.events == ["saving", "finished", "backgroundFinished"])
        #expect(handler.finishedData == content)
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    @MainActor
    @Test("failed finalization retains staged media and its recovery manifest")
    func failedFinalizationRetainsFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("CFNetworkDownload.tmp")
        let content = Data("completed media".utf8)
        try content.write(to: source)
        let staging = directory.appendingPathComponent("Staging")
        let coordinator = DownloadSessionCoordinator(stagingDirectory: staging)
        let handler = ActivityEventTestHandler()
        handler.finalizationSucceeds = false
        let task = try URLSession.shared.downloadTask(with: #require(URL(string: "https://example.com/media")))
        task.taskDescription = "record-1"
        await withCheckedContinuation { continuation in
            handler.onBackgroundFinished = { continuation.resume() }
            coordinator.setEventHandler(handler)
            coordinator.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: source)
            coordinator.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)
        }
        let files = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
        let staged = try #require(files.first { $0.pathExtension == "download" })
        let manifest = try #require(files.first { $0.pathExtension == "json" })
        #expect(try Data(contentsOf: staged) == content)
        #expect(try JSONDecoder().decode(String.self, from: Data(contentsOf: manifest)) == "record-1")
        #expect(handler.events == ["saving", "finished", "backgroundFinished"])
    }

    @MainActor
    @Test("cancel discards queued completion before a deleted record id can be reused")
    func cancelledStagedCompletionIsDiscarded() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("CFNetworkDownload.tmp")
        try Data("old generation".utf8).write(to: source)
        let staging = directory.appendingPathComponent("Staging")
        let coordinator = DownloadSessionCoordinator(stagingDirectory: staging)
        let task = try URLSession.shared.downloadTask(with: #require(URL(string: "https://example.com/media")))
        task.taskDescription = "record-1"
        coordinator.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: source)
        coordinator.cancel(recordID: "record-1")
        let handler = ActivityEventTestHandler()
        await withCheckedContinuation { continuation in
            handler.onBackgroundFinished = { continuation.resume() }
            coordinator.setEventHandler(handler)
            coordinator.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)
        }
        #expect(handler.events == ["backgroundFinished"])
        #expect(try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).isEmpty)
    }

    @MainActor
    @Test("a staging filesystem failure reports failure instead of discarding the callback")
    func stagingFailureIsReported() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("CFNetworkDownload.tmp")
        try Data("completed media".utf8).write(to: source)
        let blockedDirectory = directory.appendingPathComponent("Staging")
        try Data("a file occupies the staging directory".utf8).write(to: blockedDirectory)
        let coordinator = DownloadSessionCoordinator(stagingDirectory: blockedDirectory)
        let handler = ActivityEventTestHandler()
        let task = try URLSession.shared.downloadTask(with: #require(URL(string: "https://example.com/media")))
        task.taskDescription = "record-1"
        await withCheckedContinuation { continuation in
            handler.onFailure = { continuation.resume() }
            coordinator.setEventHandler(handler)
            coordinator.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: source)
        }
        #expect(handler.failure != nil)
        #expect(handler.events == ["failed", "failure"])
    }

    @MainActor
    @Test("resume offsets retain real received bytes when the total remains unknown")
    func resumeOffsetWithoutTotal() async throws {
        let coordinator = DownloadSessionCoordinator()
        let handler = ActivityEventTestHandler()
        let task = try URLSession.shared.downloadTask(with: #require(URL(string: "https://example.com/media")))
        task.taskDescription = "record-1"
        await withCheckedContinuation { continuation in
            handler.onActivity = { activity in
                #expect(activity.receivedBytes == 8192)
                #expect(activity.expectedBytes == nil)
                #expect(activity.phase == .waitingForServer)
                #expect(activity.bytesPerSecond() == nil)
                continuation.resume()
            }
            coordinator.setEventHandler(handler)
            coordinator.urlSession(.shared, downloadTask: task, didResumeAtOffset: 8192, expectedTotalBytes: NSURLSessionTransferSizeUnknown)
        }
    }

    @MainActor
    @Test("a transfer failure without resume data is still delivered with failed activity")
    func failureWithoutResumeData() async throws {
        let coordinator = DownloadSessionCoordinator()
        let handler = ActivityEventTestHandler()
        let task = try URLSession.shared.downloadTask(with: #require(URL(string: "https://example.com/media")))
        task.taskDescription = "record-1"
        await withCheckedContinuation { continuation in
            handler.onFailure = { continuation.resume() }
            coordinator.setEventHandler(handler)
            coordinator.urlSession(.shared, task: task, didCompleteWithError: URLError(.networkConnectionLost))
        }
        #expect(handler.events == ["failed", "failure"])
        #expect(handler.resumeData == nil)
    }
}

@MainActor
private final class ActivityEventTestHandler: DownloadSessionCoordinatorEventHandler {
    var events: [String] = []
    var finishedData: Data?
    var onBackgroundFinished: (() -> Void)?
    var onActivity: ((DownloadActivity) -> Void)?
    var onFailure: (() -> Void)?
    var failure: Error?
    var resumeData: Data?
    var finalizationSucceeds = true

    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didUpdateActivity activity: DownloadActivity, recordID: String) {
        events.append(activity.phase.rawValue)
        onActivity?(activity)
    }

    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didFinishDownloadingTo location: URL, recordID: String) {
        finishedData = try? Data(contentsOf: location)
        events.append("finished")
    }

    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, finalizeDownloadedFileAt location: URL, recordID: String) -> Bool {
        downloadSessionCoordinator(coordinator, didFinishDownloadingTo: location, recordID: recordID)
        return finalizationSucceeds
    }

    func downloadSessionCoordinator(_ coordinator: DownloadSessionCoordinating, didFailWith error: Error, resumeData: Data?, recordID: String) {
        failure = error
        self.resumeData = resumeData
        events.append("failure")
        onFailure?()
    }

    func downloadSessionCoordinatorDidFinishBackgroundEvents(_ coordinator: DownloadSessionCoordinating) async {
        events.append("backgroundFinished")
        onBackgroundFinished?()
    }
}
