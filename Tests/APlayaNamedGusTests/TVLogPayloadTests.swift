import Foundation
@testable import Gus
import Testing

struct TVLogPayloadTests {
    @Test func roundTrip() throws {
        let value = TVLogPayload(formatVersion: 1, capturedAt: .now, appVersion: "1.0", build: "35", events: [])
        #expect(try TVLogPayload.decode(value.encoded()).build == "35")
    }

    @Test func rejectsPrivateStrings() throws {
        let value = TVLogPayload(formatVersion: 1, capturedAt: .now, appVersion: "https://private", build: "35", events: [])
        #expect(throws: (any Error).self) { try TVLogPayload.decode(value.encoded()) }
        let event = DiagnosticEventRecord(name: "private title", attributes: [:], date: .now)
        let badEvent = TVLogPayload(formatVersion: 1, capturedAt: .now, appVersion: "1.0", build: "35", events: [event])
        #expect(throws: (any Error).self) { try TVLogPayload.decode(badEvent.encoded()) }
    }

    @Test func rejectsOversizeAndUnknownFormat() throws {
        #expect(throws: (any Error).self) { try TVLogPayload.decode(Data(repeating: 32, count: 131_073)) }
        let value = TVLogPayload(formatVersion: 2, capturedAt: .now, appVersion: "1.0", build: "35", events: [])
        #expect(throws: (any Error).self) { try TVLogPayload.decode(value.encoded()) }
    }
}
