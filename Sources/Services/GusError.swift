import Foundation

/// A small, typed error surface for A Playa Named Gus. Lower-level errors (cancellation, URL/network
/// failures, and anything the Jellyfin SDK throws) are mapped into user-presentable
/// messages via `init(from:)`.
///
/// Note: we deliberately do **not** import `Get` (the SDK's transport package) to pattern
/// match its `APIError` — the native-first mandate keeps `jellyfin-sdk-swift` the only
/// declared dependency. HTTP-status nuance (e.g. 401) is mapped where we hold an
/// `HTTPURLResponse`; the generic network/unknown paths cover thrown SDK errors.
enum GusError: LocalizedError, Equatable {
    case network(String)
    case offline
    case timeout
    case unauthorized
    case server(String)
    case notFound
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case let .network(detail):
            return String(localized: "Couldn't reach the server. \(detail)", comment: "Network error with detail")
        case .offline:
            return String(localized: "The server appears to be offline. Check your connection and try again.", comment: "Offline network error")
        case .timeout:
            return String(localized: "The server took too long to respond. Try again in a moment.", comment: "Timeout network error")
        case .unauthorized:
            return String(localized: "Your session has expired. Please sign in again.", comment: "401 / unauthorized error")
        case let .server(message):
            return message
        case .notFound:
            return String(localized: "That content couldn't be found.", comment: "404 / not found error")
        case .cancelled:
            return String(localized: "The request was cancelled.", comment: "Cancelled request")
        case let .unknown(detail):
            return detail
        }
    }

    /// Cancellations are a normal consequence of navigating away mid-load; UI should ignore
    /// them rather than render an error.
    var isCancellation: Bool {
        self == .cancelled
    }

    init(from error: Error) {
        if error is CancellationError {
            self = .cancelled
        } else if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                self = .cancelled
            case .timedOut:
                self = .timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                self = .offline
            default:
                self = .network(urlError.localizedDescription)
            }
        } else if let gusError = error as? GusError {
            self = gusError
        } else {
            self = .unknown(error.localizedDescription)
        }
    }
}
