import AppIntents
import Foundation

struct GusRemotePlayerEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Jellyfin Player"
    static let defaultQuery = GusRemotePlayerQuery()
    var id: String
    @Property(title: "Device Name") var name: String
    @Property(title: "Client") var client: String
    init(identifier: String, player: RemoteSession) {
        id = identifier
        name = player.deviceName
        client = player.client
    }

    var displayRepresentation: DisplayRepresentation {
        .init(title: "\(name)", subtitle: "\(client)")
    }
}

struct GusRemotePlayerQuery: EntityStringQuery {
    func suggestedEntities() async throws -> [GusRemotePlayerEntity] {
        []
    }

    @MainActor func entities(for identifiers: [String]) async throws -> [GusRemotePlayerEntity] {
        let items = try await players()
        return identifiers.compactMap { id in items.first { $0.id == id } }
    }

    @MainActor func entities(matching string: String) async throws -> [GusRemotePlayerEntity] {
        try await players().filter { $0.name.localizedStandardContains(string) }
    }

    @MainActor fileprivate func players() async throws -> [GusRemotePlayerEntity] {
        let session = try await GusIntentRuntime.session()
        let store = RemoteSessionsStore(session: session)
        await store.refresh()
        try GusIntentRuntime.validate(session)
        if let error = store.refreshErrorMessage {
            throw GusError.server(error)
        }
        return GusRemotePlayerQuery.distinctDevices(store.sessions).compactMap { player -> GusRemotePlayerEntity? in
            guard let deviceID = player.deviceID else { return nil }
            let id = GusIntentID.make(resource: "player", id: deviceID, provider: session.server.providerKind, scope: session.references.scope)
            return GusRemotePlayerEntity(identifier: id, player: player)
        }
    }

    /// A saved shortcut refers to one device. A duplicate or missing device ID
    /// cannot distinguish two currently controllable sessions.
    static func distinctDevices(_ sessions: [RemoteSession]) -> [RemoteSession] {
        let counts = Dictionary(grouping: sessions, by: \.deviceID)
        return sessions.filter { player in
            guard let id = player.deviceID, !id.isEmpty else { return false }
            return counts[id]?.count == 1
        }
    }

    @MainActor func resolve(_ entity: GusRemotePlayerEntity, in session: SessionStore, using store: RemoteSessionsStore) async throws -> RemoteSession {
        guard let device = GusIntentID.value(entity.id, resource: "player", provider: session.server.providerKind, scope: session.references.scope) else { throw GusError.notFound }
        await store.refresh()
        try GusIntentRuntime.validate(session)
        if let error = store.refreshErrorMessage {
            throw GusError.server(error)
        }
        guard let match = Self.distinctDevices(store.sessions).first(where: { $0.deviceID == device }) else {
            throw GusError.server(String(localized: "This player is no longer active."))
        }
        return match
    }
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct FindGusPlayersIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Active Jellyfin Players"
    static let description = IntentDescription("Returns controllable devices on the active Jellyfin server.", categoryName: "Remote Playback")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[GusRemotePlayerEntity]> {
        try .result(value: await GusRemotePlayerQuery().players())
    }
}

enum GusRemoteCommand: String, AppEnum {
    case playPause, stop, next, previous, forward, back, volumeUp, volumeDown, mute

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Remote Command"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .playPause: "Play or Pause", .stop: "Stop", .next: "Next Track", .previous: "Previous Track",
        .forward: "Skip Forward 30 Seconds", .back: "Skip Back 15 Seconds", .volumeUp: "Volume Up",
        .volumeDown: "Volume Down", .mute: "Toggle Mute",
    ]
}

struct ControlGusPlayerIntent: AppIntent {
    static let title: LocalizedStringResource = "Control Jellyfin Player"
    static let description = IntentDescription("Confirms a command for a selected active Jellyfin player.", categoryName: "Remote Playback")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Player") var player: GusRemotePlayerEntity
    @Parameter(title: "Command") var command: GusRemoteCommand

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<GusActionStatus> {
        let session = try await GusIntentRuntime.session()
        let store = RemoteSessionsStore(session: session)
        let query = GusRemotePlayerQuery()
        let selected = try await query.resolve(player, in: session, using: store)
        if command == .playPause {
            _ = try selected.playPauseCommand(policy: ContentRatingGate.storedPolicy())
        }
        try await requestConfirmation(dialog: "Send \(command) to \(selected.deviceName)?")
        let fresh = try await query.resolve(player, in: session, using: store)
        guard selected.id == fresh.id, selected.userName == fresh.userName else { throw GusError.notFound }
        // A remote queue doesn't expose the next track's rating. Under a rating
        // limit, use the Play action with a specific, freshly admitted item.
        if command == .next || command == .previous, ContentRatingGate.storedPolicy().limit != .off {
            throw GusError.server(String(localized: "Choose a specific library item to play under this content limit."))
        }
        let outcome = try await GusAutomationWrite.perform(key: player.id) {
            switch command {
            case .playPause: try await store.togglePlayPause(sessionID: fresh.id)
            case .stop: try await store.stopPlayback(sessionID: fresh.id)
            case .next: try await store.nextTrack(sessionID: fresh.id)
            case .previous: try await store.previousTrack(sessionID: fresh.id)
            case .forward: try await store.seek(sessionID: fresh.id, bySeconds: 30)
            case .back: try await store.seek(sessionID: fresh.id, bySeconds: -15)
            case .volumeUp: try await store.volumeUp(sessionID: fresh.id)
            case .volumeDown: try await store.volumeDown(sessionID: fresh.id)
            case .mute: try await store.toggleMute(sessionID: fresh.id)
            }
        }
        try GusIntentRuntime.validate(session)
        return try .result(value: GusActionStatus(outcome))
    }
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct PlayOnGusPlayerIntent: AppIntent {
    static let title: LocalizedStringResource = "Play on Jellyfin Player"
    static let description = IntentDescription("Plays a selected library item on a specific Jellyfin device after confirmation.", categoryName: "Remote Playback")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Library Item") var item: GusMediaEntity
    @Parameter(title: "Player") var player: GusRemotePlayerEntity

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<GusActionStatus> {
        let session = try await GusIntentRuntime.session()
        let store = RemoteSessionsStore(session: session)
        let query = GusRemotePlayerQuery()
        let media = try await GusIntentRuntime.resolve(item, in: session)
        let selected = try await query.resolve(player, in: session, using: store)
        guard selected.canPlay(media), ContentRatingGate.admitsStored(media) else { throw GusError.forbidden }
        try await requestConfirmation(dialog: "Play \(media.displayTitle) on \(selected.deviceName)?")
        let fresh = try await query.resolve(player, in: session, using: store)
        guard selected.id == fresh.id, selected.userName == fresh.userName else { throw GusError.notFound }
        let outcome = try await GusAutomationWrite.perform(key: player.id) {
            try await store.play(PlaybackRequest(item: media), on: fresh.id)
        }
        try GusIntentRuntime.validate(session)
        return try .result(value: GusActionStatus(outcome))
    }
}

@MainActor enum GusAutomationWrite {
    private static var active: Set<String> = []

    static func perform<T>(key: String, operation: @MainActor () async throws -> T) async throws -> T {
        guard active.insert(key).inserted else { throw GusError.server(String(localized: "Wait for the pending command to finish.")) }
        defer { active.remove(key) }
        return try await operation()
    }
}
