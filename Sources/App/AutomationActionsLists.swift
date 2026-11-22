import AppIntents
import Foundation

enum GusMembershipChange: String, AppEnum {
    case add, remove
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Membership Change"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.add: "Add", .remove: "Remove"]
}

struct CreateGusPlaylistIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Private Playlist"
    static let description = IntentDescription("Creates a private Jellyfin playlist with the selected library items.", categoryName: "Playlists")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Playlist Name") var name: String
    @Parameter(title: "Library Items") var items: [GusMediaEntity]?

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<GusActionStatus> {
        let session = try await GusIntentRuntime.session()
        guard let name = name.trimmedNilIfEmpty else { throw GusError.server(String(localized: "Enter a playlist name.")) }
        var resolved = [MediaItem]()
        for item in items ?? [] {
            try resolved.append(await GusIntentRuntime.resolve(item, in: session))
        }
        try GusIntentRuntime.validate(session)
        let scope = session.references.scope
        let store = ServerMediaListsStore.shared
        store.load(scope: scope)
        let key = GusIntentID.make(resource: "playlist-create", id: name, provider: session.server.providerKind, scope: scope)
        let status: GusActionStatus = try await GusAutomationWrite.perform(key: key) {
            // A duplicate-capable request can survive app termination in the
            // playlist journal. Re-running the shortcut must preserve that entry.
            if let pending = store.pendingEdits(scope: scope).first(where: { $0.action == .create && $0.name == name }) {
                return try GusActionStatus(pending.outcome)
            }
            guard resolved.allSatisfy({ ContentRatingGate.admitsStored($0) }) else { throw GusError.forbidden }
            guard let id = await store.create(name: name, kind: .playlist, session: session, items: resolved, requiresPrivateOwnership: true) else {
                throw GusError.server(store.errorMessage ?? String(localized: "The playlist could not be created."))
            }
            try GusIntentRuntime.validate(session)
            if let pending = store.pendingEdits(scope: scope).first(where: { $0.listID == id && $0.action == .create }) {
                return try GusActionStatus(pending.outcome)
            }
            // An acknowledged create may outlive the read that confirms it.
            do {
                let fresh = try await session.mediaProvider.mediaList(id: id, kind: .playlist)
                try GusIntentRuntime.validate(session)
                return fresh.name == name && fresh.entries.map(\.item.id) == resolved.map(\.id) ? .confirmed : .accepted
            } catch {
                try GusIntentRuntime.validate(session)
                return .accepted
            }
        }
        return .result(value: status)
    }
}

struct SetGusListMembershipIntent: AppIntent {
    static let title: LocalizedStringResource = "Change List Membership"
    static let description = IntentDescription("Adds or removes an item. Shared lists and collections require confirmation.", categoryName: "Library")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Library Item") var item: GusMediaEntity
    @Parameter(title: "Playlist or Collection") var list: GusMediaEntity
    @Parameter(title: "Change", default: .add) var change: GusMembershipChange

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<GusActionStatus> {
        let session = try await GusIntentRuntime.session()
        let member = try await GusIntentRuntime.resolve(item, in: session)
        let header = try await GusIntentRuntime.resolve(list, in: session)
        guard member.id != header.id, header.type == .playlist || header.type == .boxSet,
              ContentRatingGate.admitsStored(member) else { throw GusError.notFound }
        var privatePlaylist = false
        if header.type == .playlist, let raw = header.id, let id = ServerMediaListID.uuid(raw) {
            privatePlaylist = try await session.mediaProvider.ownsPrivatePlaylist(id: id)
            try GusIntentRuntime.validate(session)
        }
        guard ContentRatingGate.admitsStored(member), ContentRatingGate.admitsStored(header) else { throw GusError.forbidden }
        if !privatePlaylist && change == .add {
            try await requestConfirmation(dialog: "Add \(member.displayTitle) to \(header.displayTitle)?")
        } else if !privatePlaylist {
            try await requestConfirmation(dialog: "Remove \(member.displayTitle) from \(header.displayTitle)?")
        }
        let status: GusActionStatus = try await GusAutomationWrite.perform(key: list.id) {
            let member = try await GusIntentRuntime.resolve(item, in: session)
            let list = try await GusIntentRuntime.resolve(list, in: session)
            guard let id = list.id, list.type == header.type, list.displayTitle == header.displayTitle,
                  ContentRatingGate.admitsStored(member) else { throw GusError.notFound }
            if list.type == .playlist, let guid = ServerMediaListID.uuid(id) {
                return try await updatePlaylist(guid, member: member, session: session, requiresPrivateOwnership: privatePlaylist)
            }
            guard list.type == .boxSet else { throw GusError.notFound }
            return try await updateCollection(id, member: member, session: session)
        }
        return .result(value: status)
    }

    @MainActor private func updatePlaylist(_ id: UUID, member: MediaItem, session: SessionStore, requiresPrivateOwnership: Bool) async throws -> GusActionStatus {
        let store = ServerMediaListsStore.shared
        let scope = session.references.scope
        store.load(scope: scope)
        await store.refresh(id: id, kind: .playlist, session: session)
        try GusIntentRuntime.validate(session)
        let fresh = try await session.mediaProvider.mediaList(id: id, kind: .playlist)
        try GusIntentRuntime.validate(session)
        guard fresh.canEdit, ContentRatingGate.admitsStored(member) else { throw GusError.forbidden }
        if let pending = store.pendingEdits(scope: scope).first(where: { $0.listID == id }) {
            throw GusError.server(pending.message ?? String(localized: "Review the pending playlist change in Gus before editing it again."))
        }
        let entries = fresh.entries.filter { $0.item.id == member.id }
        let submitted: Bool
        switch change {
        case .add:
            guard entries.isEmpty else { return .confirmed }
            submitted = await store.add(item: member, to: id, kind: .playlist, session: session, requiresPrivateOwnership: requiresPrivateOwnership)
        case .remove:
            guard let entry = entries.first else { return .confirmed }
            guard entries.count == 1 else { throw GusError.server(String(localized: "Choose the playlist entry to remove in Gus.")) }
            submitted = await store.remove(entryID: entry.id, from: id, kind: .playlist, session: session, requiresPrivateOwnership: requiresPrivateOwnership)
        }
        try GusIntentRuntime.validate(session)
        guard submitted else { throw GusError.server(store.errorMessage ?? String(localized: "The playlist could not be updated.")) }
        if let pending = store.pendingEdits(scope: scope).first(where: { $0.listID == id }) {
            return try GusActionStatus(pending.outcome)
        }
        do {
            let readback = try await session.mediaProvider.mediaList(id: id, kind: .playlist)
            try GusIntentRuntime.validate(session)
            return readback.entries.contains { $0.item.id == member.id } == (change == .add) ? .confirmed : .accepted
        } catch {
            try GusIntentRuntime.validate(session)
            return .accepted
        }
    }

    @MainActor private func updateCollection(_ id: String, member: MediaItem, session: SessionStore) async throws -> GusActionStatus {
        guard let memberID = member.id, CollectionPlatform.canAddMembers,
              change == .add && !member.isBookFormat || CollectionPlatform.canManage else { throw GusError.forbidden }
        let store = CollectionStore(session: session)
        await store.loadDetail(id: id, force: true)
        let rights = try await session.mediaProvider.collectionCapabilities(id: id)
        try GusIntentRuntime.validate(session)
        guard let collection = store.collection(id), collection.membersLoaded, store.memberErrors[id] == nil,
              ContentRatingGate.admitsStored(collection.item), ContentRatingGate.admitsStored(member),
              change == .add ? rights.addMembers : rights.removeMembers else { throw GusError.forbidden }
        let exists = collection.members.contains { $0.id == memberID }
        guard exists != (change == .add) else { return .confirmed }
        _ = await store.mutate(collectionID: id, verifying: change == .add ? .contains([memberID]) : .excludes([memberID])) {
            if change == .add {
                try await session.mediaProvider.addCollectionMembers(id: id, itemIDs: [memberID])
            } else {
                try await session.mediaProvider.removeCollectionMembers(id: id, itemIDs: [memberID])
            }
            return id
        }
        try GusIntentRuntime.validate(session)
        return try GusActionStatus(store.actionOutcome, failure: store.errorMessage)
    }
}
