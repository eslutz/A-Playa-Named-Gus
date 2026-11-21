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
    let intelligencePreferences: GusIntelligencePreferences
    @ObservationIgnored lazy var libraryIntelligence = GusLibraryIntelligence(session: self)
    #if os(iOS) || os(tvOS)
        @ObservationIgnored lazy var forYouSnapshotSync = ForYouSnapshotSync(scope: references.scope)
    #endif
    #if os(iOS)
        @ObservationIgnored private var forYouSyncTask: Task<Void, Never>?
        @ObservationIgnored private var forYouSyncGeneration = UUID()
        private(set) var isVerifyingForYouSyncAccount = false
        private(set) var forYouSyncAccountVerificationFailed = false
    #endif
    @ObservationIgnored lazy var intelligenceAccess: GusIntelligenceAccess = {
        let access = GusIntelligenceAccess(preferences: intelligencePreferences, routes: .system()) { [weak self] in
            guard let self else { return }
            libraryIntelligence.clearRecommendations()
            #if os(iOS)
                if intelligencePreferences.forYouSyncEnabled, !intelligencePreferences.recommendationsEnabled {
                    revokeForYouSharing()
                }
            #endif
        }
        onInvalidation(of: access) { $0.invalidate() }
        return access
    }()

    #if os(tvOS)
        func setForYouSyncEnabled(_ enabled: Bool) {
            guard isActive else { return }
            intelligencePreferences.forYouSyncEnabled = enabled
        }
    #endif

    #if os(iOS)
        func setForYouSyncEnabled(_ enabled: Bool) {
            guard isActive, !isVerifyingForYouSyncAccount,
                  intelligencePreferences.forYouSyncEnabled != enabled else { return }
            forYouSyncAccountVerificationFailed = false
            guard enabled else {
                revokeForYouSharing()
                intelligencePreferences.forYouSyncIdentity = nil
                return
            }
            guard intelligencePreferences.recommendationsEnabled else { return }
            isVerifyingForYouSyncAccount = true
            Task {
                defer { isVerifyingForYouSyncAccount = false }
                do {
                    let identity = try await forYouSnapshotSync.currentPublishingIdentity()
                    guard isActive, intelligencePreferences.recommendationsEnabled else { return }
                    intelligencePreferences.forYouSyncIdentity = identity
                    forYouSyncAccountVerificationFailed = identity == nil
                } catch {
                    guard isActive else { return }
                    forYouSyncAccountVerificationFailed = true
                }
            }
        }

        func shareForYouPicks(_ picks: [GusLibraryPick]) {
            guard isActive, intelligencePreferences.forYouSyncEnabled,
                  intelligencePreferences.recommendationsEnabled else { return }
            scheduleForYouSync(itemIDs: picks.compactMap {
                $0.item.providerKind == .jellyfin ? $0.item.id : nil
            })
        }

        func refreshForYouSyncAccount() {
            guard forYouSyncTask == nil, intelligencePreferences.forYouSyncEnabled ||
                !intelligencePreferences.forYouSyncRevocations.isEmpty else { return }
            scheduleForYouSync()
        }

        private func revokeForYouSharing() {
            guard let identity = intelligencePreferences.forYouSyncIdentity else { return }
            intelligencePreferences.forYouSyncRevocations[identity] = .now
            scheduleForYouSync()
        }

        private func scheduleForYouSync(itemIDs: [String]? = nil) {
            let previous = forYouSyncTask
            let token = UUID()
            let createdAt = Date.now
            forYouSyncGeneration = token
            // Finish an in-flight upload before processing a newer decision. Superseded
            // work that has not reached CloudKit can be dropped.
            forYouSyncTask = Task { [weak self] in
                await previous?.value
                guard let self, isActive, forYouSyncGeneration == token else { return }
                defer {
                    if forYouSyncGeneration == token {
                        forYouSyncTask = nil
                    }
                }
                do {
                    guard let identity = try await forYouSnapshotSync.currentPublishingIdentity(),
                          isActive, forYouSyncGeneration == token else { return }
                    // An opt-in from the previous iCloud account must never grant
                    // access to a new account, including after an app relaunch.
                    if let allowed = intelligencePreferences.forYouSyncIdentity, allowed != identity {
                        intelligencePreferences.forYouSyncIdentity = nil
                    }
                    if let revokedAt = intelligencePreferences.forYouSyncRevocations[identity] {
                        try await forYouSnapshotSync.revoke(createdAt: revokedAt, identity: identity)
                        guard isActive else { return }
                        if intelligencePreferences.forYouSyncRevocations[identity] == revokedAt {
                            intelligencePreferences.forYouSyncRevocations[identity] = nil
                        }
                    }
                    guard let itemIDs, isActive, forYouSyncGeneration == token,
                          intelligencePreferences.forYouSyncIdentity == identity,
                          intelligencePreferences.recommendationsEnabled else { return }
                    try await forYouSnapshotSync.publish(itemIDs: itemIDs, createdAt: createdAt, identity: identity)
                } catch {
                    // Keep an unsent opt-out for the next foreground activation.
                    // Expiring snapshots also bound retention if iCloud stays unavailable.
                }
            }
        }
    #endif

    let searchHistory: SearchHistoryStore
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
        #if os(iOS)
            forYouSyncTask?.cancel()
        #endif
        artworkTransport.invalidate()
        profile.invalidate()
        seerr.deactivate()
        searchHistory.deactivate()
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
        mediaProvider: (any MediaProviderSession)? = nil,
        historyDefaults: UserDefaults = .standard
    ) {
        let scope = AccountScope(serverID: server.id, userID: user.id)
        let lease = SessionLease(credential: SessionCredential(user: user))
        self.lease = lease
        self.artworkTransport = NativeArtworkTransport(scope: scope, generation: lease.generation)
        self.client = client
        self.profile = UserProfileStore(client: client, userID: user.id)
        self.user = user
        self.server = server
        self.seerr = SeerrStore(scope: scope)
        self.intelligencePreferences = GusIntelligencePreferences(scope: scope, defaults: historyDefaults)
        self.searchHistory = SearchHistoryStore(scope: scope, defaults: historyDefaults)
        let provider = mediaProvider ?? JellyfinMediaProviderSession(client: client, userID: user.id)
        self.mediaProvider = provider
        self.references = MediaReferenceResolver(provider: provider, scope: scope)
    }
}
