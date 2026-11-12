import Foundation

/// Only explicitly typed, privacy-safe events and normalized metrics enter this bundle.
/// Do not export raw OSLog messages, request URLs, names, or credential-bearing errors.
struct ClientLogExport: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let platform: String
    let appVersion: String
    let build: String
    let events: [DiagnosticEventRecord]
    let performance: [DiagnosticSummary]

    static func snapshot() -> Self {
        Self(
            formatVersion: 1,
            exportedAt: .now,
            platform: DeviceIdentity.platformName,
            appVersion: DeviceIdentity.appVersion,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            events: DiagnosticsHub.shared.recentEvents(),
            performance: DiagnosticSummaryStore.shared.loadSummaries()
        )
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// One replaceable export; never accumulates unbounded support files.
    func save(directory: URL = AppStorageLocation.appDirectory()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Gus-client-logs.json")
        try encoded().write(to: url, options: .atomic)
        return url
    }
}
