import Foundation

/// A small, typed error surface for Gus. Lower-level errors (cancellation, URL/network
/// failures, and anything the Jellyfin SDK throws) are mapped into user-presentable
/// messages via `init(from:)`.
///
/// Note: we deliberately do **not** import `Get` (the SDK's transport package) to pattern
/// match its `APIError` — the native-first mandate keeps `jellyfin-sdk-swift` the only
/// declared dependency. HTTP-status nuance (e.g. 401) is mapped where we hold an
/// `HTTPURLResponse`; the generic network/unknown paths cover thrown SDK errors.
enum GusError: LocalizedError, Equatable {
    case network(String)
    case unauthorized
    case server(String)
    case notFound
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case let .network(detail):
            return String(localized: "Couldn't reach the server. \(detail)", comment: "Network error with detail")
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
            self = urlError.code == .cancelled ? .cancelled : .network(urlError.localizedDescription)
        } else {
            self = .unknown(error.localizedDescription)
        }
    }
}
