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
    let lease: SessionLease
    private(set) var isActive = true
    let client: JellyfinClient
    let playbackReports = PlaybackReportQueue()
    let artworkTransport: NativeArtworkTransport
    let mediaProvider: any MediaProviderSession
    let references: MediaReferenceResolver
    var user: StoredUser
    let profile: UserProfileStore
    let server: ServerConnection
    let seerr: SeerrStore
    private(set) var reauthenticationRequest: SessionLease?
    private weak var recoveryOwner: AppModel?
    private final class InvalidationRegistration {
        weak var owner: AnyObject?
        let action: @MainActor () -> Void

        init(owner: AnyObject, action: @escaping @MainActor () -> Void) {
            self.owner = owner
            self.action = action
        }
    }

    private var invalidationHandlers: [InvalidationRegistration] = []

    /// Coalesces expiry reports from concurrent requests for this credential generation.
    func handleUnauthorized() {
        guard isActive, reauthenticationRequest == nil else { return }
        reauthenticationRequest = lease
        invalidate()
        recoveryOwner?.recoverExpiredSession(lease: lease)
    }

    func bindRecovery(to owner: AppModel) {
        recoveryOwner = owner
    }

    func onInvalidation<Owner: AnyObject>(of owner: Owner, _ action: @escaping @MainActor (Owner) -> Void) {
        guard isActive else { action(owner); return }
        invalidationHandlers.removeAll { $0.owner == nil || $0.owner === owner }
        invalidationHandlers.append(InvalidationRegistration(owner: owner) { [weak owner] in
            guard let owner else { return }
            action(owner)
        })
    }

    /// Stops account-bound consumers before a replacement tree can install its state.
    func invalidate() {
        guard isActive else { return }
        isActive = false
        artworkTransport.invalidate()
        profile.invalidate()
        seerr.deactivate()
        references.invalidate()
        invalidateCollections()
        let handlers = invalidationHandlers
        invalidationHandlers.removeAll()
        handlers.forEach { $0.action() }
    }

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
        let lease = SessionLease(credential: SessionCredential(user: user))
        self.lease = lease
        self.artworkTransport = NativeArtworkTransport(scope: AccountScope(serverID: server.id, userID: user.id), generation: lease.generation)
        self.client = client
        self.profile = UserProfileStore(client: client, userID: user.id)
        self.user = user
        self.server = server
        self.seerr = SeerrStore(scope: AccountScope(serverID: server.id, userID: user.id))
        let provider = mediaProvider ?? JellyfinMediaProviderSession(client: client, userID: user.id)
        self.mediaProvider = provider
        self.references = MediaReferenceResolver(provider: provider, scope: AccountScope(serverID: server.id, userID: user.id))
    }
}
