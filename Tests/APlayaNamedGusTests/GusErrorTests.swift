import Foundation
import Get
@testable import Gus
import Testing

@Suite("GusError mapping")
struct GusErrorTests {
    @Test("CancellationError maps to .cancelled")
    func cancellationErrorMapping() {
        #expect(GusError(from: CancellationError()) == .cancelled)
    }

    @Test("URLError.timedOut maps to .timeout")
    func timeoutMapping() {
        #expect(GusError(from: URLError(.timedOut)) == .timeout)
    }

    @Test("URLError.notConnectedToInternet maps to .offline")
    func offlineMapping() {
        #expect(GusError(from: URLError(.notConnectedToInternet)) == .offline)
    }

    @Test("URLError.networkConnectionLost maps to .offline")
    func networkConnectionLostMapping() {
        #expect(GusError(from: URLError(.networkConnectionLost)) == .offline)
    }

    @Test("URLError.cannotConnectToHost maps to .offline")
    func cannotConnectToHostMapping() {
        #expect(GusError(from: URLError(.cannotConnectToHost)) == .offline)
    }

    @Test("URLError.cannotFindHost maps to .offline")
    func cannotFindHostMapping() {
        #expect(GusError(from: URLError(.cannotFindHost)) == .offline)
    }

    @Test("URLError.dnsLookupFailed maps to .offline")
    func dnsLookupFailedMapping() {
        #expect(GusError(from: URLError(.dnsLookupFailed)) == .offline)
    }

    @Test("URLError.cancelled maps to .cancelled")
    func urlErrorCancelledMapping() {
        #expect(GusError(from: URLError(.cancelled)) == .cancelled)
    }

    @Test("Unrecognized URLError maps to .network")
    func unknownURLErrorMapping() {
        let error = GusError(from: URLError(.badServerResponse))
        if case .network = error {
        } else {
            Issue.record("Expected .network for URLError.badServerResponse, got \(error)")
        }
    }

    @Test("401 status code maps to .unauthorized")
    func unauthorizedMapping() {
        let apiError = APIError.unacceptableStatusCode(401)
        #expect(GusError(from: apiError) == .unauthorized)
    }

    @Test("403 status code maps to .unauthorized")
    func forbiddenMapping() {
        let apiError = APIError.unacceptableStatusCode(403)
        #expect(GusError(from: apiError) == .unauthorized)
    }

    @Test("404 status code maps to .notFound")
    func notFoundMapping() {
        let apiError = APIError.unacceptableStatusCode(404)
        #expect(GusError(from: apiError) == .notFound)
    }

    @Test("500 status code maps to .server")
    func serverErrorMapping() {
        if case .server = GusError.fromHTTPStatusCode(500) {
        } else {
            Issue.record("Expected .server for 500")
        }
    }

    @Test("503 status code maps to .server")
    func serviceUnavailableMapping() {
        if case .server = GusError.fromHTTPStatusCode(503) {
        } else {
            Issue.record("Expected .server for 503")
        }
    }

    @Test("Non-success non-5xx code maps to .network")
    func genericHTTPErrorMapping() {
        if case .network = GusError.fromHTTPStatusCode(400) {
        } else {
            Issue.record("Expected .network for 400")
        }
    }

    @Test("isCancellation is true only for .cancelled")
    func isCancellationProperty() {
        #expect(GusError.cancelled.isCancellation == true)
        #expect(GusError.unauthorized.isCancellation == false)
        #expect(GusError.offline.isCancellation == false)
        #expect(GusError.timeout.isCancellation == false)
        #expect(GusError.notFound.isCancellation == false)
    }

    @Test("GusError wrapping preserves identity")
    func gusErrorWrapping() {
        #expect(GusError(from: GusError.offline) == .offline)
        #expect(GusError(from: GusError.cancelled) == .cancelled)
        #expect(GusError(from: GusError.unauthorized) == .unauthorized)
        #expect(GusError(from: GusError.notFound) == .notFound)
    }

    @Test("Unknown error maps to .unknown")
    func unknownErrorMapping() {
        struct SomeError: Error {}
        if case .unknown = GusError(from: SomeError()) {
        } else {
            Issue.record("Expected .unknown for unrecognized error type")
        }
    }
}
