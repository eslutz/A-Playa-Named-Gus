import Foundation
@testable import Gus
import Testing

@Suite("Diagnostics")
struct DiagnosticsTests {
    @Test("event names are stable and unique")
    func eventNamesAreStableAndUnique() {
        let events: [DiagnosticEvent] = [
            .appLaunched,
            .sessionRestored,
            .serverConnectStarted,
            .serverConnectSucceeded,
            .serverConnectFailed,
            .libraryLoadStarted,
            .libraryLoadFinished(itemCount: 1),
            .libraryLoadFailed,
            .searchRequested,
            .playbackStartRequested,
            .playbackStarted(usingTranscoding: false, usingLocalFile: false),
            .playbackFailed,
            .downloadQueued,
            .downloadPaused,
            .downloadCompleted,
            .downloadFailed,
        ]

        let names = events.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(DiagnosticEvent.appLaunched.name == "app.launched")
        #expect(DiagnosticEvent.playbackStarted(usingTranscoding: true, usingLocalFile: false).name == "playback.started")
    }

    @Test("event attributes carry only numeric or boolean values")
    func eventAttributesAreNumericOrBoolean() {
        let events: [DiagnosticEvent] = [
            .libraryLoadFinished(itemCount: 42),
            .playbackStarted(usingTranscoding: true, usingLocalFile: false),
        ]

        for event in events {
            for value in event.attributes.values {
                let isNumeric = Double(value) != nil
                let isBoolean = value == "true" || value == "false"
                #expect(isNumeric || isBoolean, "attribute value \(value) must be numeric or boolean")
            }
        }
    }

    @Test("recent events ring buffer keeps only the newest records")
    func recentEventsRingBufferCaps() {
        let hub = DiagnosticsHub()
        let overflow = 50

        for index in 0 ..< (DiagnosticsHub.maxRecentEvents + overflow) {
            hub.record(.libraryLoadFinished(itemCount: index))
        }

        let events = hub.recentEvents()
        #expect(events.count == DiagnosticsHub.maxRecentEvents)
        #expect(events.last?.attributes["itemCount"] == String(DiagnosticsHub.maxRecentEvents + overflow - 1))
        #expect(events.first?.attributes["itemCount"] == String(overflow))
    }

    @Test("histogram math averages and totals bucket midpoints by count")
    func histogramMathAveragesAndTotals() {
        let buckets = [
            HistogramMath.Bucket(start: 0, end: 100, count: 3),
            HistogramMath.Bucket(start: 100, end: 300, count: 1),
        ]

        #expect(HistogramMath.weightedAverage(of: buckets) == 87.5)
        #expect(HistogramMath.weightedTotal(of: buckets) == 350.0)
        #expect(HistogramMath.weightedAverage(of: []) == nil)
        #expect(HistogramMath.weightedTotal(of: []) == nil)
    }

    @Test("diagnostic summaries round-trip through Codable")
    func diagnosticSummaryCodableRoundTrip() throws {
        var summary = DiagnosticSummary(capturedAt: Date(timeIntervalSince1970: 1000), kind: .metrics, platform: "iOS")
        summary.appVersion = "1.0"
        summary.launchTimeToFirstDrawAverageMS = 420
        summary.peakMemoryMB = 256.5
        summary.crashCount = 2

        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(DiagnosticSummary.self, from: data)

        #expect(decoded == summary)
    }

    @Test("summary store appends and caps stored summaries")
    func summaryStoreAppendsAndCaps() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gus-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiagnosticSummaryStore(directory: directory)

        let overflow = 5
        let summaries = (0 ..< (DiagnosticSummaryStore.maxStoredSummaries + overflow)).map { index in
            DiagnosticSummary(
                capturedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                kind: .metrics,
                platform: "iOS"
            )
        }
        store.append(summaries)

        let loaded = store.loadSummaries()
        #expect(loaded.count == DiagnosticSummaryStore.maxStoredSummaries)
        #expect(loaded.last?.capturedAt == summaries.last?.capturedAt)
        #expect(loaded.first?.capturedAt == Date(timeIntervalSince1970: TimeInterval(overflow)))
    }
}
