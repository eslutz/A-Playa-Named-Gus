import Foundation
import JellyfinAPI
import Observation

/// Owns the authenticated `JellyfinClient` plus the signed-in user and server for the
/// duration of a session. Injected into the signed-in view tree via `@Environment`.
///
/// Replaces Swiftfin's `UserSession` (Factory-injected). Feature stores take a
/// `SessionStore` and call provider-neutral media operations through `mediaProvider`.
@MainActor
@Observable
final class SessionStore {
    let client: JellyfinClient
    let mediaProvider: any MediaProviderSession
    let references: MediaReferenceResolver
    let user: StoredUser
    let server: ServerConnection
    /// Called when any request in this session receives a 401; navigates back to sign-in.
    var onUnauthorized: () -> Void = {}

    private final class CollectionRegistration {
        weak var store: CollectionStore?
        init(_ store: CollectionStore) {
            self.store = store
        }
    }

    private var collectionRegistrations: [CollectionRegistration] = []

    func registerCollectionStore(_ store: CollectionStore) {
        collectionRegistrations.removeAll { $0.store == nil }
        collectionRegistrations.append(CollectionRegistration(store))
    }

    func invalidateCollections() {
        collectionRegistrations.forEach { $0.store?.invalidate() }
        collectionRegistrations = []
    }

    init(
        client: JellyfinClient,
        user: StoredUser,
        server: ServerConnection,
        mediaProvider: (any MediaProviderSession)? = nil
    ) {
        self.client = client
        self.user = user
        self.server = server
        let provider = mediaProvider ?? JellyfinMediaProviderSession(client: client, userID: user.id)
        self.mediaProvider = provider
        self.references = MediaReferenceResolver(provider: provider, scope: AccountScope(serverID: server.id, userID: user.id))
    }
}
