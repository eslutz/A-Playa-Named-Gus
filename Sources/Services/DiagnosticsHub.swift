import Foundation
import os
import OSLog

/// A privacy-safe app lifecycle marker used to interpret diagnostics.
///
/// Cases carry only numeric or boolean payloads by construction — never names, URLs,
/// titles, tokens, or other values that could identify a person, server, or media item.
/// Keep new cases to that contract; it is what satisfies the redaction requirement in
/// `Documentation/AppStore/diagnostics-reliability.md`.
enum DiagnosticEvent: Equatable {
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
    case searchRequested
    case playbackStartRequested
    case playbackStarted(usingTranscoding: Bool, usingLocalFile: Bool)
    case playbackFailed
    /// Domain codes: 0 unknown, 1 URL, 2 AVFoundation, 3 OSStatus. Never raw error text.
    case playbackItemFailed(errorCode: Int, errorDomain: Int)
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
        case .searchRequested: return "search.requested"
        case .playbackStartRequested: return "playback.start.requested"
        case .playbackStarted: return "playback.started"
        case .playbackFailed: return "playback.failed"
        case .playbackItemFailed: return "playback.item.failed"
        case .downloadQueued: return "download.queued"
        case .downloadPaused: return "download.paused"
        case .downloadCompleted: return "download.completed"
        case .downloadFailed: return "download.failed"
        }
    }

    /// Numeric/boolean attributes only — see the type-level privacy contract.
    var attributes: [String: String] {
        switch self {
        case let .playbackItemFailed(errorCode, errorDomain):
            return ["errorCode": String(errorCode), "errorDomain": String((0 ... 3).contains(errorDomain) ? errorDomain : 0)]
        case let .libraryLoadFinished(itemCount):
            return ["itemCount": String(itemCount)]
        case let .playbackStarted(usingTranscoding, usingLocalFile):
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
struct DiagnosticEventRecord: Codable, Equatable {
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
/// `Documentation/AppStore/performance-baselines.md` are re-measured.
final class DiagnosticsHub: Sendable {
    static let shared = DiagnosticsHub(directory: AppStorageLocation.appDirectory())
    static let maxRecentEvents = 200

    private let logger = Logger(category: .diagnostics)
    private let signposter = OSSignposter(subsystem: Logger.subsystem, category: "Diagnostics")
    private let recentEventStorage: OSAllocatedUnfairLock<[DiagnosticEventRecord]>
    private let persistenceURL: URL?

    /// A nil directory gives tests an isolated, in-memory recorder.
    init(directory: URL? = nil) {
        persistenceURL = directory?.appendingPathComponent("client-events.json")
        let saved = persistenceURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([DiagnosticEventRecord].self, from: $0) } ?? []
        recentEventStorage = OSAllocatedUnfairLock(initialState: Array(saved.suffix(Self.maxRecentEvents)))
    }

    /// Records a lifecycle marker into the ring buffer and the unified log.
    func record(_ event: DiagnosticEvent, date: Date = .now) {
        let record = DiagnosticEventRecord(name: event.name, attributes: event.attributes, date: date)
        recentEventStorage.withLock { events in
            events.append(record)
            if events.count > Self.maxRecentEvents {
                events.removeFirst(events.count - Self.maxRecentEvents)
            }
            if let persistenceURL {
                do {
                    try FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(events).write(to: persistenceURL, options: .atomic)
                } catch {
                    logger.error("Client event persistence failed")
                }
            }
        }
        logger.debug("\(event.name, privacy: .public) \(event.attributes, privacy: .public)")
    }

    /// The most recent lifecycle markers, oldest first.
    func recentEvents() -> [DiagnosticEventRecord] {
        recentEventStorage.withLock { $0 }
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
