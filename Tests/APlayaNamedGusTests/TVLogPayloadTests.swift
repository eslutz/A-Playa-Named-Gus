import Foundation
@testable import Gus
import Testing

struct TVLogPayloadTests {
    @Test func fragmentedInputRemainsBounded() throws {
        let first = Data(repeating: 1, count: 65536)
        let full = try TVLogPayload.appending(first, to: first)
        #expect(full.count == 131_072)
        #expect(throws: (any Error).self) { try TVLogPayload.appending(Data([1]), to: full) }
        #expect(try TVLogPayload.appending(Data(), to: full) == full)
    }

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
