import Foundation
import JellyfinAPI
import Observation

/// Owns the authenticated `JellyfinClient` plus the signed-in user and server for the
/// duration of a session. Injected into the signed-in view tree via `@Environment`.
///
/// Replaces Swiftfin's `UserSession` (Factory-injected). Feature stores take a
/// `SessionStore` and call `session.client.send(...)`.
@MainActor
@Observable
final class SessionStore {

    let client: JellyfinClient
    let user: StoredUser
    let server: ServerConnection

    init(client: JellyfinClient, user: StoredUser, server: ServerConnection) {
        self.client = client
        self.user = user
        self.server = server
    }

    var imageBuilder: ImageURLBuilder { ImageURLBuilder(client: client) }

    var streamBuilder: StreamURLBuilder { StreamURLBuilder(client: client, userID: user.id) }
}
