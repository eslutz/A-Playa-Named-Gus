import Foundation
import OSLog

/// An app-owned, privacy-safe normalization of a MetricKit payload.
///
/// Only aggregate numbers survive normalization — no identifiers, URLs, or stack traces.
/// Summaries are what the recurring diagnostics review in
/// `Documentation/AppStore/diagnostics-reliability.md` reads between releases.
struct DiagnosticSummary: Codable, Equatable {
    enum Kind: String, Codable {
        case metrics
        case diagnostics
    }

    var capturedAt: Date
    var kind: Kind
    var platform: String
    var appVersion: String?

    // Metric payload aggregates (nil when the payload omitted the metric).
    var launchTimeToFirstDrawAverageMS: Double?
    var hangTimeTotalSeconds: Double?
    var peakMemoryMB: Double?
    var cpuTimeSeconds: Double?
    var cumulativeDiskWritesMB: Double?
    var cumulativeNetworkTransferMB: Double?

    // Diagnostic payload counts.
    var crashCount: Int = 0
    var hangCount: Int = 0
    var cpuExceptionCount: Int = 0
    var diskWriteExceptionCount: Int = 0

    init(capturedAt: Date, kind: Kind, platform: String) {
        self.capturedAt = capturedAt
        self.kind = kind
        self.platform = platform
    }
}

/// Pure bucketed-histogram math, separated from MetricKit types so it stays testable.
enum HistogramMath {
    struct Bucket: Equatable {
        var start: Double
        var end: Double
        var count: Int
    }

    /// Count-weighted average of bucket midpoints; `nil` when the histogram is empty.
    static func weightedAverage(of buckets: [Bucket]) -> Double? {
        let totalCount = buckets.reduce(0) { $0 + $1.count }
        guard totalCount > 0 else { return nil }
        let weightedSum = buckets.reduce(0.0) { $0 + ($1.start + $1.end) / 2 * Double($1.count) }
        return weightedSum / Double(totalCount)
    }

    /// Sum of bucket midpoints times counts (e.g. total hang time); `nil` when empty.
    static func weightedTotal(of buckets: [Bucket]) -> Double? {
        let totalCount = buckets.reduce(0) { $0 + $1.count }
        guard totalCount > 0 else { return nil }
        return buckets.reduce(0.0) { $0 + ($1.start + $1.end) / 2 * Double($1.count) }
    }
}

/// Codable + `FileManager` persistence for recent `DiagnosticSummary` records, capped so
/// the file stays small. Mirrors the `ServerStore` JSON-in-Application-Support idiom.
struct DiagnosticSummaryStore {
    static let maxStoredSummaries = 60
    static let shared = DiagnosticSummaryStore()

    private let logger = Logger(category: .diagnostics)
    private let directory: URL

    init(directory: URL = AppStorageLocation.appDirectory()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var summariesURL: URL {
        directory.appendingPathComponent("diagnostic-summaries.json")
    }

    func loadSummaries() -> [DiagnosticSummary] {
        guard let data = try? Data(contentsOf: summariesURL) else { return [] }
        do {
            return try JSONDecoder().decode([DiagnosticSummary].self, from: data)
        } catch {
            logger.error("Failed to decode diagnostic summaries: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func append(_ summaries: [DiagnosticSummary]) {
        guard !summaries.isEmpty else { return }
        var all = loadSummaries()
        all.append(contentsOf: summaries)
        if all.count > Self.maxStoredSummaries {
            all.removeFirst(all.count - Self.maxStoredSummaries)
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(all)
            try data.write(to: summariesURL, options: .atomic)
        } catch {
            logger.error("Failed to write diagnostic summaries: \(error.localizedDescription, privacy: .public)")
        }
    }
}
