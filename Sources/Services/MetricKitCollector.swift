import Foundation
import OSLog

// MetricKit imports on tvOS but every type is marked unavailable there, so the guard
// must exclude tvOS explicitly rather than relying on canImport alone.
#if canImport(MetricKit) && !os(tvOS)
    import MetricKit
#endif

extension DiagnosticsHub {
    /// Starts MetricKit collection where the platform supports it.
    ///
    /// tvOS has no MetricKit; that gap is documented in
    /// `Documentation/AppStore/diagnostics-reliability.md` rather than papered over with
    /// a third-party SDK. macOS delivers diagnostic payloads only.
    func startMetricCollection() {
        #if canImport(MetricKit) && !os(tvOS)
            MetricKitCollector.shared.start()
        #endif
    }
}

#if canImport(MetricKit) && !os(tvOS)
    /// Subscribes to `MXMetricManager` and normalizes payloads into app-owned
    /// `DiagnosticSummary` records so nothing else in the app touches MetricKit types.
    final class MetricKitCollector: NSObject, MXMetricManagerSubscriber {
        static let shared = MetricKitCollector()

        private let logger = Logger(category: .diagnostics)
        private let summaryStore: DiagnosticSummaryStore

        init(summaryStore: DiagnosticSummaryStore = .shared) {
            self.summaryStore = summaryStore
        }

        func start() {
            MXMetricManager.shared.add(self)
        }

        #if os(iOS) || os(visionOS)
            /// Metric payloads are not delivered on macOS; diagnostics below cover it.
            func didReceive(_ payloads: [MXMetricPayload]) {
                let summaries = payloads.map(Self.summary(from:))
                summaryStore.append(summaries)
                logger.info("Stored \(summaries.count, privacy: .public) MetricKit metric summaries")
            }
        #endif

        func didReceive(_ payloads: [MXDiagnosticPayload]) {
            let summaries = payloads.map(Self.summary(from:))
            summaryStore.append(summaries)
            logger.info("Stored \(summaries.count, privacy: .public) MetricKit diagnostic summaries")
        }

        // MARK: - Normalization

        private static var platformName: String {
            #if os(iOS)
                return "iOS"
            #elseif os(visionOS)
                return "visionOS"
            #elseif os(macOS)
                return "macOS"
            #else
                return "unknown"
            #endif
        }

        #if os(iOS) || os(visionOS)
            static func summary(from payload: MXMetricPayload) -> DiagnosticSummary {
                var summary = DiagnosticSummary(
                    capturedAt: payload.timeStampEnd,
                    kind: .metrics,
                    platform: platformName
                )
                summary.appVersion = payload.latestApplicationVersion

                if let launch = payload.applicationLaunchMetrics {
                    summary.launchTimeToFirstDrawAverageMS = HistogramMath.weightedAverage(
                        of: buckets(from: launch.histogrammedTimeToFirstDraw, unit: UnitDuration.milliseconds)
                    )
                }
                if let responsiveness = payload.applicationResponsivenessMetrics {
                    summary.hangTimeTotalSeconds = HistogramMath.weightedTotal(
                        of: buckets(from: responsiveness.histogrammedApplicationHangTime, unit: UnitDuration.seconds)
                    )
                }
                if let memory = payload.memoryMetrics {
                    summary.peakMemoryMB = memory.peakMemoryUsage.converted(to: .megabytes).value
                }
                if let cpu = payload.cpuMetrics {
                    summary.cpuTimeSeconds = cpu.cumulativeCPUTime.converted(to: .seconds).value
                }
                if let disk = payload.diskIOMetrics {
                    summary.cumulativeDiskWritesMB = disk.cumulativeLogicalWrites.converted(to: .megabytes).value
                }
                if let network = payload.networkTransferMetrics {
                    summary.cumulativeNetworkTransferMB = network.cumulativeWifiUpload.converted(to: .megabytes).value
                        + network.cumulativeWifiDownload.converted(to: .megabytes).value
                        + network.cumulativeCellularUpload.converted(to: .megabytes).value
                        + network.cumulativeCellularDownload.converted(to: .megabytes).value
                }
                return summary
            }

            private static func buckets<UnitType: Dimension>(
                from histogram: MXHistogram<UnitType>,
                unit: UnitType
            ) -> [HistogramMath.Bucket] {
                var result: [HistogramMath.Bucket] = []
                let enumerator = histogram.bucketEnumerator
                while let bucket = enumerator.nextObject() as? MXHistogramBucket<UnitType> {
                    result.append(HistogramMath.Bucket(
                        start: bucket.bucketStart.converted(to: unit).value,
                        end: bucket.bucketEnd.converted(to: unit).value,
                        count: bucket.bucketCount
                    ))
                }
                return result
            }
        #endif

        static func summary(from payload: MXDiagnosticPayload) -> DiagnosticSummary {
            var summary = DiagnosticSummary(
                capturedAt: payload.timeStampEnd,
                kind: .diagnostics,
                platform: platformName
            )
            summary.crashCount = payload.crashDiagnostics?.count ?? 0
            summary.hangCount = payload.hangDiagnostics?.count ?? 0
            summary.cpuExceptionCount = payload.cpuExceptionDiagnostics?.count ?? 0
            summary.diskWriteExceptionCount = payload.diskWriteExceptionDiagnostics?.count ?? 0
            return summary
        }
    }
#endif
