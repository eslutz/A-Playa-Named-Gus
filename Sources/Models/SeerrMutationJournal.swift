import Foundation

/// An unresolved write survives sheet dismissal and process termination. Contains no credentials.
struct SeerrPendingRequest: Codable, Equatable, Sendable {
    // Older journals predate attempt identifiers and retain their original payload and baseline.
    var id: UUID? = nil
    let payload: SeerrRequestPayload
    let baselineIDs: Set<Int>
}
