import Foundation
import Get

/// A small, typed error surface for A Playa Named Gus. Lower-level errors (cancellation, URL/network
/// failures, and anything the Jellyfin SDK throws) are mapped into user-presentable
/// messages via `init(from:)`.
///
/// The Jellyfin SDK's existing Get transport exposes typed HTTP status errors.
enum GusError: LocalizedError, Equatable {
    case network(String)
    case offline
    case timeout
    case unauthorized
    case forbidden
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
        case .forbidden:
            return String(localized: "You do not have permission to do that.", comment: "403 / permission denied error")
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

    /// Requests identity-bound recovery for an expired or revoked session.
    @MainActor
    func handleIfUnauthorized(session: SessionStore) {
        if self == .unauthorized {
            session.handleUnauthorized()
        }
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
        } else if case let APIError.unacceptableStatusCode(statusCode) = error {
            self = Self.fromHTTPStatusCode(statusCode)
        } else if let gusError = error as? GusError {
            self = gusError
        } else {
            self = .unknown(error.localizedDescription)
        }
    }

    static func fromHTTPStatusCode(_ statusCode: Int) -> GusError {
        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 500...:
            return .server(String(
                localized: "The server reported an error (\(statusCode)). Try again in a moment.",
                comment: "Generic 5xx server error with status code"
            ))
        default:
            return .network(String(
                localized: "The server rejected the request (\(statusCode)).",
                comment: "Generic non-success HTTP status error"
            ))
        }
    }
}
