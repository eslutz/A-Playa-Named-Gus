import Foundation
import Get
import JellyfinAPI

/// Normalizes authenticated SDK failures once at the transport boundary. The client
/// retains this delegate; its recovery closure retains only a weak session reference.
final class SessionAuthentication: APIClientDelegate, @unchecked Sendable {
    private let userID: String
    private let lock = NSLock()
    private var recovery: (@MainActor @Sendable () -> Void)?

    init(userID: String) {
        self.userID = userID
    }

    @MainActor
    func bind(to session: SessionStore) {
        lock.withLock {
            recovery = { [weak session] in session?.handleUnauthorized() }
        }
    }

    func client(_ client: APIClient, shouldRetry task: URLSessionTask, error: any Error, attempts: Int) async throws -> Bool {
        guard !Task.isCancelled, GusError(from: error) == .unauthorized else { return false }

        // Jellyfin also uses 401 for deletion policy and disabled Quick Connect.
        // A canonical user read distinguishes permission denial from expired auth.
        if Self.requiresAuthenticationProbe(task.originalRequest) {
            do {
                _ = try await client.send(Paths.getUserByID(userID: userID))
                throw GusError.forbidden
            } catch {
                let failure = GusError(from: error)
                guard failure == .unauthorized else { throw failure }
            }
        }

        let recovery = lock.withLock { self.recovery }
        await recovery?()
        return false // Authentication recovery never retries a write.
    }

    static func requiresAuthenticationProbe(_ request: URLRequest?) -> Bool {
        guard let path = request?.url?.path else { return false }
        let components = path.lowercased().split(separator: "/")
        switch request?.httpMethod {
        case "DELETE": return components.dropLast().last == "items"
        case "POST": return components.suffix(2).elementsEqual(["quickconnect", "authorize"])
        default: return false
        }
    }
}
