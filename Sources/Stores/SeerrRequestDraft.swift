import Foundation
import Observation

/// A reviewed payload stays intact until Seerr confirms its result or an explicit readback resolves it.
@MainActor @Observable
final class SeerrRequestDraft {
    enum Phase { case loading, review, submitting, uncertain, confirmed }
    var phase: Phase = .loading
    var title: SeerrTitle
    var settings: SeerrPublicSettings?
    var quota: SeerrQuota?
    var account: SeerrUser?
    var selectedSeasons: Set<Int> = []
    var is4K = false
    var message: String?
    var confirmed: SeerrRequest?
    var isChecking = false
    var servers: [SeerrServiceServer] = []
    var service: SeerrServiceDetails?
    var serverID: Int?
    var profileID: Int?
    var rootFolder: String?
    var languageID: Int?
    var isLoadingOptions = false
    private var revision: UUID?
    private var serviceRevision = UUID()
    private var attempt: SeerrPendingRequest?

    init(title: SeerrTitle) {
        self.title = title
    }

    /// The durable submission journal remains authoritative; shared UI reads this projection.
    var actionOutcome: ActionOutcome? {
        switch phase {
        case .loading: nil
        case .review: message.map { .failed(.unknown($0)) }
        case .submitting: .pending
        case .uncertain: .uncertain
        case .confirmed: .confirmed
        }
    }

    var type: SeerrMediaType {
        title.mediaType ?? .unknown
    }

    var eligibleSeasons: [Int] {
        settings.map { SeerrRequestEligibility.requestableSeasons(title: title, settings: $0, is4K: is4K) } ?? []
    }

    var canSubmit: Bool {
        guard phase == .review, !isLoadingOptions, let account, let settings, let quota else { return false }
        return SeerrRequestEligibility.canRequest(
            title: title,
            type: type,
            user: account,
            settings: settings,
            quota: quota,
            is4K: is4K,
            seasons: Array(selectedSeasons)
        )
    }

    var allows4K: Bool {
        settings?.permits4K(type) == true && account?.canRequest(type, is4K: true) == true
    }

    func load(store: SeerrStore, resetSelection: Bool = false) async {
        let expected = store.revision
        revision = expected
        phase = .loading
        message = nil
        do {
            let client = try store.requireClient()
            try await store.refreshUser()
            guard let user = store.user else { throw SeerrConnectionError.signInRequired }
            let detail = try await client.details(mediaType: type, id: title.id)
            let publicSettings = try await client.publicSettings()
            let limits = try await client.quota(userID: user.id)
            guard expected == store.revision, !Task.isCancelled else { return }
            guard store.admits(detail) else { throw SeerrConnectionError.notPermitted }
            title = detail
            settings = publicSettings
            quota = limits
            account = user
            if !allows4K {
                is4K = false
            }
            let eligible = Set(eligibleSeasons)
            selectedSeasons.formIntersection(eligible)
            if resetSelection {
                selectedSeasons = []
            }
            if publicSettings.partialRequestsEnabled != true {
                selectedSeasons = eligible
            }
            phase = .review
            await loadOptions(store: store)
        } catch {
            guard expected == store.revision, !Task.isCancelled else { return }
            phase = .review
            message = error.localizedDescription
            store.handle(error)
        }
    }

    func formatChanged(store: SeerrStore) async {
        selectedSeasons.formIntersection(Set(eligibleSeasons))
        if settings?.partialRequestsEnabled != true {
            selectedSeasons = Set(eligibleSeasons)
        }
        serverID = nil; service = nil; profileID = nil; rootFolder = nil; languageID = nil
        await loadOptions(store: store)
    }

    func loadOptions(store: SeerrStore) async {
        let optionsRevision = UUID()
        serviceRevision = optionsRevision
        guard account?.permissions.permits(.requestAdvanced) == true else { servers = []; clearOptions(); isLoadingOptions = false; return }
        isLoadingOptions = true
        defer {
            if serviceRevision == optionsRevision {
                isLoadingOptions = false
            }
        }
        do {
            let client = try store.requireClient()
            let fetched = try await client.serviceServers(mediaType: type)
            guard revision == store.revision, serviceRevision == optionsRevision else { return }
            servers = fetched.filter { $0.is4k == is4K }
            if let serverID, servers.contains(where: { $0.id == serverID }) {
                let fetched = try await client.serviceDetails(mediaType: type, serverID: serverID)
                guard revision == store.revision, serviceRevision == optionsRevision else { return }
                service = fetched
                profileID = fetched.profiles.first(where: { $0.id == fetched.server.activeProfileId })?.id
                rootFolder = fetched.rootFolders.first(where: { $0.path == fetched.server.activeDirectory })?.path
                languageID = fetched.languageProfiles?.first(where: { $0.id == fetched.server.activeLanguageProfileId })?.id
            } else {
                clearOptions()
            }
        } catch {
            guard revision == store.revision, serviceRevision == optionsRevision else { return }
            servers = []; clearOptions()
            store.handle(error)
        }
    }

    func submit(store: SeerrStore) async {
        guard canSubmit, revision == store.revision else { return }
        let payload = SeerrRequestPayload(
            mediaType: type,
            mediaId: title.id,
            seasons: type == .tv ? Array(selectedSeasons).sorted() : nil,
            is4k: is4K,
            serverId: serverID,
            profileId: profileID,
            rootFolder: rootFolder,
            languageProfileId: languageID
        )
        phase = .submitting
        message = nil
        var ownedAttempt: SeerrPendingRequest?
        var clearOwnedAttempt = false
        defer {
            if let ownedAttempt {
                store.endTransmission(of: ownedAttempt)
                if clearOwnedAttempt {
                    store.completeRequestAttempt(ownedAttempt)
                }
            }
        }
        let expected = store.revision
        do {
            let client = try store.requireClient()
            try await store.refreshUser()
            guard let user = store.user else { throw SeerrConnectionError.signInRequired }
            let current = try await client.details(mediaType: type, id: title.id)
            let currentSettings = try await client.publicSettings()
            let currentQuota = try await client.quota(userID: user.id)
            guard expected == store.revision, !Task.isCancelled else { return }
            guard store.admits(current), SeerrRequestEligibility.canRequest(
                title: current,
                type: type,
                user: user,
                settings: currentSettings,
                quota: currentQuota,
                is4K: payload.is4k,
                seasons: payload.seasons ?? []
            )
            else {
                title = current; settings = currentSettings; quota = currentQuota; account = user
                throw SeerrConnectionError.eligibilityChanged
            }
            let previous = try await ownRequestIDs(client: client, userID: user.id)
            guard expected == store.revision, !Task.isCancelled else { return }
            guard store.admits(current) else { throw SeerrConnectionError.notPermitted }
            let pending = try store.beginRequestAttempt(payload: payload, baselineIDs: previous)
            ownedAttempt = pending
            attempt = pending
            // Seerr validates any advanced destination/profile/folder against current permissions.
            let result = try await client.createRequest(payload)
            guard expected == store.revision, !Task.isCancelled else { return }
            confirmed = result
            clearOwnedAttempt = true
            phase = .confirmed
        } catch {
            guard expected == store.revision else { return }
            if case SeerrClientError.mutationOutcomeUnknown = error, let pending = store.pendingRequest(for: payload) {
                restoreAttempt(pending, store: store)
            } else {
                clearOwnedAttempt = true
                phase = .review
            }
            message = error.localizedDescription
            store.handle(error)
        }
    }

    func restoreAttempt(_ attempt: SeerrPendingRequest, store: SeerrStore) {
        self.attempt = attempt
        selectedSeasons = Set(attempt.payload.seasons ?? [])
        is4K = attempt.payload.is4k
        revision = store.revision
        phase = .uncertain
    }

    func resetAfterVerification(store: SeerrStore) async {
        guard phase == .uncertain, !isChecking, let attempt, revision == store.revision else { return }
        if let current = store.pendingRequest(for: attempt.payload) {
            if current != attempt {
                restoreAttempt(current, store: store)
                return
            }
            guard !store.isTransmitting(attempt) else {
                message = String(localized: "Wait for the pending command to finish.")
                return
            }
            guard store.completeRequestAttempt(attempt) else {
                message = String(localized: "Your changes couldn't be saved. Try again.")
                return
            }
        }
        self.attempt = nil
        await load(store: store)
    }

    private func clearOptions() {
        serverID = nil; service = nil; profileID = nil; rootFolder = nil; languageID = nil
    }

    private func ownRequestIDs(client: SeerrClient, userID: Int) async throws -> Set<Int> {
        var ids = Set<Int>(), skip = 0
        while true {
            let page = try await client.userRequests(userID: userID, take: 50, skip: skip)
            try Task.checkCancellation()
            let pageIDs = Set(page.results.map(\.id))
            guard pageIDs.count == page.results.count, pageIDs.isDisjoint(with: ids) else { throw SeerrClientError.invalidResponse }
            ids.formUnion(pageIDs)
            skip += page.results.count
            if skip >= page.pageInfo.results {
                return ids
            }
            guard !page.results.isEmpty else { throw SeerrClientError.invalidResponse }
        }
    }

    func check(store: SeerrStore) async {
        guard phase == .uncertain, !isChecking, let attempt, revision == store.revision else { return }
        let payload = attempt.payload
        if store.isTransmitting(attempt) {
            message = String(localized: "Wait for the pending command to finish.")
            return
        }
        isChecking = true
        defer { isChecking = false }
        do {
            let client = try store.requireClient()
            try await store.refreshUser()
            guard let user = store.user else { throw SeerrConnectionError.signInRequired }
            var skip = 0
            while true {
                let page = try await client.userRequests(userID: user.id, take: 50, skip: skip)
                guard revision == store.revision, !Task.isCancelled else { return }
                if let current = store.pendingRequest(for: payload), current != attempt {
                    restoreAttempt(current, store: store)
                    return
                }
                if let match = page.results.first(where: { request in
                    !attempt.baselineIDs.contains(request.id) && request.requestedBy?.id == user.id && request.media?.tmdbId == payload.mediaId
                        && (request.type ?? request.media?.mediaType) == payload.mediaType
                        && (request.is4k ?? false) == payload.is4k && request.status != .declined
                        && Set(payload.seasons ?? []).isSubset(of: Set((request.seasons ?? []).map(\.seasonNumber)))
                }) {
                    confirmed = match
                    phase = .confirmed
                    message = nil
                    store.completeRequestAttempt(attempt)
                    return
                }
                skip += page.results.count
                if page.results.isEmpty || skip >= page.pageInfo.results {
                    break
                }
            }
            message = String(localized: "Seerr has not confirmed this request. Check again later or verify its status in Seerr before starting another request.")
        } catch {
            guard revision == store.revision else { return }
            message = error.localizedDescription
            store.handle(error)
        }
    }
}
