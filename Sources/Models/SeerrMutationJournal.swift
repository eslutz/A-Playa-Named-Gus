import Foundation

/// An unresolved write survives sheet dismissal and process termination. Contains no credentials.
struct SeerrPendingRequest: Codable, Sendable {
    let payload: SeerrRequestPayload
    let baselineIDs: Set<Int>
}
