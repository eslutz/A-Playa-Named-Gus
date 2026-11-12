import Foundation
@testable import Gus
import Testing

struct WatchDiagnosticSnapshotTests {
    private func data(date: Date = Date(timeIntervalSince1970: 100), events: [DiagnosticEventRecord] = []) throws -> Data {
        try JSONEncoder().encode(WatchDiagnosticSnapshot(formatVersion: 1, capturedAt: date, events: events))
    }

    @Test func retainsCaptureAndReceiptSeparately() throws {
        let store = WatchDiagnosticSnapshotStore()
        #expect(try store.receive(data(), now: Date(timeIntervalSince1970: 200)))
        #expect(store.latest()?.snapshot.capturedAt == Date(timeIntervalSince1970: 100))
        #expect(store.latest()?.receivedAt == Date(timeIntervalSince1970: 200))
        #expect(try !store.receive(data(), now: Date(timeIntervalSince1970: 300)))
        #expect(try !store.receive(data(date: Date(timeIntervalSince1970: 99))))
        #expect(store.latest()?.receivedAt == Date(timeIntervalSince1970: 200))
    }

    @Test func rejectsUnknownNamesAndPrivateAttributes() throws {
        let records = [
            DiagnosticEventRecord(name: "secret-token", attributes: [:], date: .now),
            DiagnosticEventRecord(name: "app.launched", attributes: ["token": "secret"], date: .now),
            DiagnosticEventRecord(name: "library.load.finished", attributes: ["itemCount": "https://private"], date: .now),
            DiagnosticEventRecord(name: "playback.item.failed", attributes: ["errorCode": "-11800", "errorDomain": "4"], date: .now),
        ]
        for record in records {
            #expect(try WatchDiagnosticSnapshot.decode(data(events: [record])) == nil)
        }
    }

    @Test func boundsPayloadAndEventCount() throws {
        #expect(WatchDiagnosticSnapshot.decode(Data(repeating: 0, count: WatchDiagnosticSnapshot.maximumBytes + 1)) == nil)
        let record = DiagnosticEventRecord(name: "app.launched", attributes: [:], date: .now)
        #expect(try WatchDiagnosticSnapshot.decode(data(events: Array(repeating: record, count: 201))) == nil)
        #expect(try WatchDiagnosticSnapshot.decode(data(events: Array(repeating: record, count: 200))) != nil)
    }

    @Test func persistsOnlyLatestSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchDiagnosticSnapshotStore(directory: directory)
        #expect(try store.receive(data()))
        #expect(try store.receive(data(date: Date(timeIntervalSince1970: 300))))
        #expect(WatchDiagnosticSnapshotStore(directory: directory).latest()?.snapshot.capturedAt == Date(timeIntervalSince1970: 300))
    }
}
