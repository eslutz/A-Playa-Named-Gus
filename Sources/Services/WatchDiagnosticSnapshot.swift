import Foundation
import os

/// A bounded, credential-free snapshot from the paired Watch, not a live log stream.
struct WatchDiagnosticSnapshot: Codable, Equatable, Sendable {
    static let maximumBytes = 61440
    let formatVersion: Int
    let capturedAt: Date
    let events: [DiagnosticEventRecord]

    static func capture(now: Date = .now) -> Self {
        Self(formatVersion: 1, capturedAt: now, events: DiagnosticsHub.shared.recentEvents())
    }

    func encoded() throws -> Data {
        let data = try JSONEncoder().encode(self)
        guard Self.decode(data) != nil else { throw CocoaError(.coderInvalidValue) }
        return data
    }

    /// Validate the trust boundary again on receipt. Codable strings alone are not a
    /// privacy guarantee: reject unknown event names/attributes rather than exporting
    /// them. Unrecognized JSON envelope fields are discarded by typed decoding.
    static func decode(_ data: Data) -> Self? {
        guard data.count <= maximumBytes,
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.formatVersion == 1, value.capturedAt.timeIntervalSince1970.isFinite,
              value.events.count <= DiagnosticsHub.maxRecentEvents,
              validEvents(value.events)
        else { return nil }
        return value
    }

    static func validEvents(_ events: [DiagnosticEventRecord]) -> Bool {
        events.count <= DiagnosticsHub.maxRecentEvents && events.allSatisfy(validEvent)
    }

    private static func validEvent(_ record: DiagnosticEventRecord) -> Bool {
        let noAttributes = [
            "reference.unavailable", "reference.replaced", "artwork.fallback", "app.launched",
            "session.restored", "server.connect.started", "server.connect.succeeded", "server.connect.failed",
            "library.load.started", "library.load.failed", "search.requested", "playback.start.requested",
            "playback.failed", "download.queued", "download.paused", "download.completed", "download.failed",
        ]
        guard record.date.timeIntervalSince1970.isFinite else { return false }
        if noAttributes.contains(record.name) {
            return record.attributes.isEmpty
        }
        let fields: [String: Set<String>] = [
            "library.load.finished": ["itemCount"],
            "playback.started": ["transcoding", "localFile"],
            "playback.item.failed": ["errorCode", "errorDomain"],
            "playback.time.control": ["status", "reason", "positionMilliseconds", "bufferEmpty", "likelyToKeepUp"],
            "playback.stalled": ["positionMilliseconds"],
        ]
        guard let expected = fields[record.name], Set(record.attributes.keys) == expected else { return false }
        for (key, value) in record.attributes {
            if ["transcoding", "localFile", "bufferEmpty", "likelyToKeepUp"].contains(key) {
                guard value == "true" || value == "false" else { return false }
            } else {
                guard let integer = Int(value), String(integer) == value else { return false }
                if key == "errorDomain" || key == "reason", !(0 ... 3).contains(integer) {
                    return false
                }
                if key == "status", !(0 ... 2).contains(integer) {
                    return false
                }
                if key == "positionMilliseconds" || key == "itemCount", integer < 0 {
                    return false
                }
            }
        }
        return true
    }
}

struct ReceivedWatchDiagnostics: Codable, Equatable, Sendable {
    let snapshot: WatchDiagnosticSnapshot
    let receivedAt: Date
}

/// Retains only the latest paired-Watch snapshot, with honest capture/receipt dates.
final class WatchDiagnosticSnapshotStore: Sendable {
    static let shared = WatchDiagnosticSnapshotStore(directory: AppStorageLocation.appDirectory())
    private let url: URL?
    private let storage: OSAllocatedUnfairLock<ReceivedWatchDiagnostics?>

    init(directory: URL? = nil) {
        url = directory?.appendingPathComponent("watch-client-events.json")
        let saved = url.flatMap { try? Data(contentsOf: $0) }
        let decoded = saved.flatMap { data -> ReceivedWatchDiagnostics? in
            guard data.count <= WatchDiagnosticSnapshot.maximumBytes + 1024,
                  let value = try? JSONDecoder().decode(ReceivedWatchDiagnostics.self, from: data),
                  let snapshotData = try? JSONEncoder().encode(value.snapshot),
                  WatchDiagnosticSnapshot.decode(snapshotData) != nil,
                  value.receivedAt.timeIntervalSince1970.isFinite else { return nil }
            return value
        }
        storage = OSAllocatedUnfairLock(initialState: decoded)
    }

    func latest() -> ReceivedWatchDiagnostics? {
        storage.withLock { $0 }
    }

    @discardableResult
    func receive(_ data: Data, now: Date = .now) -> Bool {
        guard let snapshot = WatchDiagnosticSnapshot.decode(data) else { return false }
        return storage.withLock { existing in
            // Capture clocks are Watch-local: a backward Watch clock adjustment can
            // leave the prior snapshot retained until its capture date is surpassed.
            // The exported dates remain explicit rather than claiming freshness.
            // Delayed/out-of-order delivery must not replace a newer capture or make
            // an old identical snapshot appear freshly captured/received.
            if let existing, existing.snapshot.capturedAt >= snapshot.capturedAt {
                return false
            }
            let value = ReceivedWatchDiagnostics(snapshot: snapshot, receivedAt: now)
            if let url {
                do {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(value).write(to: url, options: .atomic)
                } catch { return false }
            }
            existing = value
            return true
        }
    }
}
