import Foundation
import os
import OSLog

/// A privacy-safe app lifecycle marker used to interpret diagnostics.
///
/// Cases carry only numeric or boolean payloads by construction — never names, URLs,
/// titles, tokens, or other values that could identify a person, server, or media item.
/// Keep new cases to that contract; it is what satisfies the redaction requirement in
/// `Documentation/diagnostics-reliability.md`.
enum DiagnosticEvent: Equatable, Sendable {
    case referenceUnavailable
    case referenceReplaced
    case artworkFallback
    case appLaunched
    case sessionRestored
    case serverConnectStarted
    case serverConnectSucceeded
    case serverConnectFailed
    case libraryLoadStarted
    case libraryLoadFinished(itemCount: Int)
    case libraryLoadFailed
    case intelligenceAttempt(cloud: Bool, succeeded: Bool)
    case searchRequested
    case playbackStartRequested
    case playbackStarted(usingTranscoding: Bool, usingLocalFile: Bool)
    case playbackPrepared(usingTranscoding: Bool, usingLocalFile: Bool)
    case playbackFirstPlaying(elapsedMilliseconds: Int)
    case playbackFirstRender(elapsedMilliseconds: Int)
    case playbackReportResult(kind: Int, outcome: Int)
    case playbackResourceCleanup(succeeded: Bool)
    case playbackResourceCleanupUnconfirmed
    case playbackFailed
    /// Domain codes: 0 unknown, 1 URL, 2 AVFoundation, 3 OSStatus. Never raw error text.
    case playbackItemFailed(errorCode: Int, errorDomain: Int)
    /// Time-control codes: 0 paused, 1 waiting, 2 playing. Wait reasons: 0 none/unknown,
    /// 1 minimize stalls, 2 evaluate buffering, 3 no item. No raw framework strings.
    case playbackTimeControl(status: Int, reason: Int, positionMilliseconds: Int, bufferEmpty: Bool, likelyToKeepUp: Bool)
    case playbackStalled(positionMilliseconds: Int)
    case downloadQueued
    case downloadPaused
    case downloadCompleted
    case downloadFailed

    /// Stable event identifier used in logs and recent-event records.
    var name: String {
        switch self {
        case .referenceUnavailable: return "reference.unavailable"
        case .referenceReplaced: return "reference.replaced"
        case .artworkFallback: return "artwork.fallback"
        case .appLaunched: return "app.launched"
        case .sessionRestored: return "session.restored"
        case .serverConnectStarted: return "server.connect.started"
        case .serverConnectSucceeded: return "server.connect.succeeded"
        case .serverConnectFailed: return "server.connect.failed"
        case .libraryLoadStarted: return "library.load.started"
        case .libraryLoadFinished: return "library.load.finished"
        case .libraryLoadFailed: return "library.load.failed"
        case .intelligenceAttempt: return "intelligence.attempt"
        case .searchRequested: return "search.requested"
        case .playbackStartRequested: return "playback.start.requested"
        case .playbackStarted: return "playback.started"
        case .playbackPrepared: return "playback.prepared"
        case .playbackFirstPlaying: return "playback.first.playing"
        case .playbackFirstRender: return "playback.first.render"
        case .playbackReportResult: return "playback.report.result"
        case .playbackResourceCleanup: return "playback.resource.cleanup"
        case .playbackResourceCleanupUnconfirmed: return "playback.resource.cleanup.unconfirmed"
        case .playbackFailed: return "playback.failed"
        case .playbackItemFailed: return "playback.item.failed"
        case .playbackTimeControl: return "playback.time.control"
        case .playbackStalled: return "playback.stalled"
        case .downloadQueued: return "download.queued"
        case .downloadPaused: return "download.paused"
        case .downloadCompleted: return "download.completed"
        case .downloadFailed: return "download.failed"
        }
    }

    /// Numeric/boolean attributes only — see the type-level privacy contract.
    var attributes: [String: String] {
        switch self {
        case let .intelligenceAttempt(cloud, succeeded):
            return ["cloud": String(cloud), "succeeded": String(succeeded)]
        case let .playbackTimeControl(status, reason, positionMilliseconds, bufferEmpty, likelyToKeepUp):
            return [
                "status": String((0 ... 2).contains(status) ? status : 0),
                "reason": String((0 ... 3).contains(reason) ? reason : 0),
                "positionMilliseconds": String(max(0, positionMilliseconds)),
                "bufferEmpty": String(bufferEmpty),
                "likelyToKeepUp": String(likelyToKeepUp),
            ]
        case let .playbackStalled(positionMilliseconds):
            return ["positionMilliseconds": String(max(0, positionMilliseconds))]
        case let .playbackItemFailed(errorCode, errorDomain):
            return ["errorCode": String(errorCode), "errorDomain": String((0 ... 3).contains(errorDomain) ? errorDomain : 0)]
        case let .libraryLoadFinished(itemCount):
            return ["itemCount": String(itemCount)]
        case let .playbackFirstPlaying(elapsedMilliseconds), let .playbackFirstRender(elapsedMilliseconds):
            return ["elapsedMilliseconds": String(max(0, elapsedMilliseconds))]
        case let .playbackReportResult(kind, outcome):
            return ["kind": String(min(2, max(0, kind))), "outcome": String(min(2, max(0, outcome)))]
        case let .playbackResourceCleanup(succeeded):
            return ["succeeded": String(succeeded)]
        case let .playbackStarted(usingTranscoding, usingLocalFile), let .playbackPrepared(usingTranscoding, usingLocalFile):
            return [
                "transcoding": String(usingTranscoding),
                "localFile": String(usingLocalFile),
            ]
        default:
            return [:]
        }
    }
}

/// A recorded diagnostic event with its capture time.
struct DiagnosticEventRecord: Codable, Equatable, Sendable {
    let name: String
    let attributes: [String: String]
    let date: Date
}

/// The app-owned diagnostics abstraction: feature code records privacy-safe lifecycle
/// markers and signpost intervals here instead of coupling to MetricKit directly.
///
/// Events land in a bounded in-memory ring buffer (for interpreting MetricKit summaries)
/// and the unified log; intervals emit `OSSignposter` ranges measurable in Instruments,
/// which is how the performance baselines in
/// `Documentation/diagnostics-reliability.md` are re-measured.
final class DiagnosticsHub: Sendable {
    static let shared = DiagnosticsHub(directory: AppStorageLocation.appDirectory())
    static let maxRecentEvents = 200

    private let logger = Logger(category: .diagnostics)
    private let signposter = OSSignposter(subsystem: Logger.subsystem, category: "Diagnostics")
    private struct Storage: Sendable {
        var events: [DiagnosticEventRecord]
        var pending: [DiagnosticEventRecord]?
        var isWriting = false
    }

    private let recentEventStorage: OSAllocatedUnfairLock<Storage>
    private let persistenceQueue = DispatchQueue(label: "dev.ericslutz.gus.diagnostics.persistence", qos: .utility)
    private let persistenceURL: URL?

    /// A nil directory gives tests an isolated, in-memory recorder.
    init(directory: URL? = nil) {
        persistenceURL = directory?.appendingPathComponent("client-events.json")
        let saved = persistenceURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([DiagnosticEventRecord].self, from: $0) } ?? []
        recentEventStorage = OSAllocatedUnfairLock(initialState: Storage(events: Array(saved.suffix(Self.maxRecentEvents))))
    }

    /// Records a lifecycle marker into the ring buffer and the unified log.
    func record(_ event: DiagnosticEvent, date: Date = .now) {
        let record = DiagnosticEventRecord(name: event.name, attributes: event.attributes, date: date)
        let schedule = recentEventStorage.withLock { storage in
            storage.events.append(record)
            if storage.events.count > Self.maxRecentEvents {
                storage.events.removeFirst(storage.events.count - Self.maxRecentEvents)
            }
            guard persistenceURL != nil else { return false }
            storage.pending = storage.events
            guard !storage.isWriting else { return false }
            storage.isWriting = true
            return true
        }
        if schedule {
            persistenceQueue.async { self.drainPendingSnapshots() }
        }
        logger.debug("\(event.name, privacy: .public) \(event.attributes, privacy: .public)")
    }

    /// The most recent lifecycle markers, oldest first.
    func recentEvents() -> [DiagnosticEventRecord] {
        recentEventStorage.withLock { $0.events }
    }

    /// Persists all events observed before this barrier completes. An abrupt
    /// process exit can still lose events which have not reached a flush barrier.
    func flush() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            persistenceQueue.async {
                do {
                    try self.persist(self.recentEvents())
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Only one worker exists. Producers replace its pending snapshot rather
    /// than enqueueing one disk write per event or waiting for disk under a lock.
    private func drainPendingSnapshots() {
        while let snapshot = recentEventStorage.withLock({ storage -> [DiagnosticEventRecord]? in
            guard let pending = storage.pending else {
                storage.isWriting = false
                return nil
            }
            storage.pending = nil
            return pending
        }) {
            do { try persist(snapshot) }
            catch { logger.error("Client event persistence failed") }
        }
    }

    private func persist(_ events: [DiagnosticEventRecord]) throws {
        guard let persistenceURL else { return }
        try FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(events).write(to: persistenceURL, options: .atomic)
    }

    /// Begins an Instruments-visible signpost interval; pair with `endInterval`.
    func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    /// Ends a signpost interval started with `beginInterval`.
    func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
}
