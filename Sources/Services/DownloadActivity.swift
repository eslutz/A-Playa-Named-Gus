import Foundation

/// Observed transfer state. A requested conversion describes intent; it does not
/// establish that the server is preparing media or expose preparation progress.
struct DownloadActivity: Codable, Equatable {
    enum Phase: String, Codable, Equatable {
        case resolving, queued, waitingForServer, downloading, waitingForConnectivity
        case paused, saving, complete, failed
    }

    enum SourceOperation: String, Codable, Equatable {
        case original, remuxed, transcoded
    }

    var phase: Phase
    var receivedBytes: Int64
    var expectedBytes: Int64?
    var startedAt: Date
    var updatedAt: Date
    var sourceOperation: SourceOperation?
    /// Set only from telemetry correlated to this exact request, never from byte progress.
    var preparationProgress: Double?
    var preparationETA: TimeInterval?

    private(set) var smoothedBytesPerSecond: Double?
    private var sampleStartedAt: Date?
    private var sampleStartedBytes: Int64?
    private var transferStartedAt: Date?
    private var lastByteReceivedAt: Date?

    init(
        phase: Phase = .queued,
        receivedBytes: Int64 = 0,
        expectedBytes: Int64? = nil,
        startedAt: Date = Date(),
        updatedAt: Date? = nil,
        sourceOperation: SourceOperation? = nil,
        preparationProgress: Double? = nil,
        preparationETA: TimeInterval? = nil
    ) {
        self.phase = phase
        self.receivedBytes = max(0, receivedBytes)
        self.expectedBytes = expectedBytes.flatMap { $0 > 0 ? $0 : nil }
        self.startedAt = startedAt
        self.updatedAt = updatedAt ?? startedAt
        self.sourceOperation = sourceOperation
        self.preparationProgress = preparationProgress
        self.preparationETA = preparationETA
    }

    var progress: Double? {
        guard let expectedBytes, expectedBytes > 0 else { return nil }
        return min(max(Double(receivedBytes) / Double(expectedBytes), 0), 1)
    }

    /// Throughput uses completed windows of at least one second. Tiny callback
    /// intervals, pauses, restarts, and stale samples cannot manufacture an ETA.
    mutating func recordTransfer(receivedBytes: Int64, expectedBytes: Int64?, at date: Date = Date()) {
        let bytes = max(0, receivedBytes)
        let oldBytes = self.receivedBytes
        if bytes < oldBytes || phase != .downloading || lastByteReceivedAt.map({ date.timeIntervalSince($0) > 20 }) == true {
            resetTransferSampling()
        }
        self.receivedBytes = bytes
        self.expectedBytes = expectedBytes.flatMap { $0 > 0 ? $0 : nil }
        updatedAt = date
        guard bytes > 0 else { return }
        phase = .downloading
        if bytes > oldBytes {
            lastByteReceivedAt = date
        }
        if transferStartedAt == nil {
            transferStartedAt = date
        }
        guard let sampleStartedAt, let sampleStartedBytes else {
            self.sampleStartedAt = date
            self.sampleStartedBytes = bytes
            return
        }
        let duration = date.timeIntervalSince(sampleStartedAt)
        guard duration >= 1 else { return }
        let rate = Double(max(0, bytes - sampleStartedBytes)) / duration
        if rate > 0 {
            smoothedBytesPerSecond = smoothedBytesPerSecond.map { $0 * 0.65 + rate * 0.35 } ?? rate
        }
        self.sampleStartedAt = date
        self.sampleStartedBytes = bytes
    }

    mutating func transition(to phase: Phase, at date: Date = Date()) {
        if self.phase != phase {
            resetTransferSampling()
        }
        self.phase = phase
        updatedAt = date
    }

    mutating func resetTransferSampling() {
        smoothedBytesPerSecond = nil
        sampleStartedAt = nil
        sampleStartedBytes = nil
        transferStartedAt = nil
        lastByteReceivedAt = nil
    }

    func isStalled(at date: Date = Date()) -> Bool {
        guard phase == .downloading, let lastByteReceivedAt else { return false }
        return date.timeIntervalSince(lastByteReceivedAt) > 20
    }

    func bytesPerSecond(at date: Date = Date()) -> Double? {
        guard phase == .downloading,
              let lastByteReceivedAt,
              date.timeIntervalSince(lastByteReceivedAt) <= 20,
              let rate = smoothedBytesPerSecond, rate.isFinite, rate > 0
        else { return nil }
        return rate
    }

    func estimatedTimeRemaining(at date: Date = Date()) -> TimeInterval? {
        guard let expectedBytes, expectedBytes > receivedBytes,
              let transferStartedAt, date.timeIntervalSince(transferStartedAt) >= 5,
              let rate = bytesPerSecond(at: date)
        else { return nil }
        return Double(expectedBytes - receivedBytes) / rate
    }
}
