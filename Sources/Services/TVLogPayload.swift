import Foundation

/// TV has no MetricKit reports. Restrict the wire format to validated event records.
struct TVLogPayload: Codable {
    let formatVersion: Int
    let capturedAt: Date
    let appVersion: String
    let build: String
    let events: [DiagnosticEventRecord]

    static func snapshot() -> Self {
        Self(
            formatVersion: 1,
            capturedAt: .now,
            appVersion: DeviceIdentity.appVersion,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            events: DiagnosticsHub.shared.recentEvents()
        )
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Keep fragmented input bounded before decoding or writing anything.
    static func appending(_ data: Data, to accumulated: Data) throws -> Data {
        guard accumulated.count <= 128 * 1024, data.count <= 128 * 1024 - accumulated.count else {
            throw CocoaError(.fileReadTooLarge)
        }
        return accumulated + data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 128 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(Self.self, from: data)
        guard value.formatVersion == 1,
              validVersion(value.appVersion), validVersion(value.build),
              value.events.count <= 200,
              value.capturedAt.timeIntervalSince1970.isFinite,
              WatchDiagnosticSnapshot.validEvents(value.events) else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }

    private static func validVersion(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 32 && text.utf8.allSatisfy { (48 ... 57).contains($0) || $0 == 46 }
    }

    /// Replace one explicitly received snapshot, never append incoming logs to local history.
    func save(directory: URL = AppStorageLocation.appDirectory()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Gus-Apple-TV-logs.json")
        try encoded().write(to: url, options: .atomic)
        return url
    }
}
