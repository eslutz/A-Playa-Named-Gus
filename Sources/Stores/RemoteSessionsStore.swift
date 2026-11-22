import Foundation
import JellyfinAPI
import Observation

/// Another Jellyfin client on the same server that this device can remote-control.
struct RemoteSession: Identifiable, Equatable, Sendable {
    let id: String
    var deviceID: String? = nil
    var userID: String? = nil
    let deviceName: String
    let client: String
    let userName: String?
    let nowPlaying: MediaItem?
    let positionTicks: Int?
    let isPaused: Bool
    var hasReportedPauseState = true
    var lastPlaybackCheckIn: Date? = nil
    let volumeLevel: Int?
    let isMuted: Bool
    let supportsMediaControl: Bool
    let canSeek: Bool
    let supportedCommands: Set<String>
    let playableMediaTypes: Set<String>
    let mediaSourceID: String?
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?

    func supports(_ command: RemoteSessionCommand) -> Bool {
        switch command {
        case .seek: supportsMediaControl && canSeek
        case .volumeUp: supportedCommands.contains("VolumeUp")
        case .volumeDown: supportedCommands.contains("VolumeDown")
        case .toggleMute: supportedCommands.contains("ToggleMute")
        default: supportsMediaControl
        }
    }

    func canPlay(_ item: MediaItem) -> Bool {
        guard supportsMediaControl else { return false }
        if item.isAudioPlayable {
            return playableMediaTypes.contains("Audio")
        }
        switch item.type {
        case .movie, .episode, .video, .trailer, .liveChannel, .recording:
            return playableMediaTypes.contains("Video")
        default: return false
        }
    }
}

extension ActionOutcome {
    var remoteMessage: String {
        switch self {
        case .pending: String(localized: "Sending Command")
        case .accepted: String(localized: "Command accepted. Waiting for the player to update.")
        case .confirmed: String(localized: "Player updated.")
        case .queued: String(localized: "Command queued.")
        case .uncertain: String(localized: "The command may have been accepted. Check the player before trying again.")
        case let .failed(error): error.localizedDescription
        }
    }
}

/// Non-idempotent commands are sent once, including after an ambiguous network failure.
enum RemoteSessionCommand: Equatable {
    case playPause, stop, nextTrack, previousTrack
    case seek(Int)
    case volumeUp, volumeDown, toggleMute
    case play(PlaybackRequest)
}

@MainActor
protocol RemoteSessionsTransport {
    func sessions(userID: String) async throws -> [RemoteSession]
    func send(_ command: RemoteSessionCommand, to sessionID: String) async throws
}

@MainActor
private struct JellyfinRemoteSessionsTransport: RemoteSessionsTransport {
    let client: JellyfinClient

    func sessions(userID: String) async throws -> [RemoteSession] {
        let parameters = Paths.GetSessionsParameters(controllableByUserID: userID, activeWithinSeconds: 960)
        let response = try await client.send(Paths.getSessions(parameters: parameters))
        return response.value.compactMap { dto in
            guard let id = dto.id, dto.isSupportsRemoteControl == true, dto.deviceID != DeviceIdentity.deviceID else { return nil }
            return RemoteSession(
                id: id,
                deviceID: dto.deviceID,
                userID: dto.userID,
                deviceName: dto.deviceName ?? String(localized: "Unknown Device"),
                client: dto.client ?? "Jellyfin",
                userName: dto.userName,
                nowPlaying: dto.nowPlayingItem.map(JellyfinMediaItemMapper.mediaItem(from:)),
                positionTicks: dto.playState?.positionTicks,
                isPaused: dto.playState?.isPaused ?? false,
                hasReportedPauseState: dto.playState?.isPaused != nil,
                lastPlaybackCheckIn: dto.lastPlaybackCheckIn,
                volumeLevel: dto.playState?.volumeLevel,
                isMuted: dto.playState?.isMuted ?? false,
                supportsMediaControl: dto.isSupportsMediaControl == true,
                canSeek: dto.playState?.canSeek == true,
                supportedCommands: Set((dto.supportedCommands ?? []).map(\.rawValue)),
                playableMediaTypes: Set((dto.playableMediaTypes ?? []).map(\.rawValue)),
                mediaSourceID: dto.playState?.mediaSourceID,
                audioStreamIndex: dto.playState?.audioStreamIndex,
                subtitleStreamIndex: dto.playState?.subtitleStreamIndex
            )
        }
    }

    func send(_ command: RemoteSessionCommand, to sessionID: String) async throws {
        switch command {
        case let .play(request):
            guard let itemID = request.item.id else { throw GusError.notFound }
            let selection = request.streamSelection
            try await client.send(Paths.play(sessionID: sessionID, parameters: .init(playCommand: .playNow, itemIDs: [itemID], startPositionTicks: request.requestedStartTicks ?? PlaybackTime.resumePositionTicks(for: request.item), mediaSourceID: selection.mediaSourceID, audioStreamIndex: selection.audioStreamIndex, subtitleStreamIndex: selection.subtitleStreamIndex)))
        case .volumeUp, .volumeDown, .toggleMute:
            let name: String
            switch command {
            case .volumeUp: name = "VolumeUp"
            case .volumeDown: name = "VolumeDown"
            default: name = "ToggleMute"
            }
            try await client.send(Paths.sendGeneralCommand(sessionID: sessionID, command: name))
        default:
            let playstate: PlaystateCommand
            var position: Int?
            switch command {
            case .playPause: playstate = .playPause
            case .stop: playstate = .stop
            case .nextTrack: playstate = .nextTrack
            case .previousTrack: playstate = .previousTrack
            case let .seek(ticks): playstate = .seek; position = ticks
            default: return
            }
            try await client.send(Paths.sendPlaystateCommand(sessionID: sessionID, command: playstate.rawValue, seekPositionTicks: position))
        }
    }
}

/// Frontmost-only remote monitoring, with bounded socket invalidations and a polling
/// fallback. Every response is checked against its credential and visibility generation.
@MainActor @Observable
final class RemoteSessionsStore {
    private static let pollingInterval = Duration.seconds(15)
    private(set) var state: LoadState = .idle
    private(set) var sessions: [RemoteSession] = []
    private(set) var refreshErrorMessage: String?
    private(set) var pendingSessionIDs: Set<String> = []
    private(set) var commandOutcomes: [String: ActionOutcome] = [:]
    private(set) var commandNotices: [String: String] = [:]

    private let session: SessionStore
    private let transport: any RemoteSessionsTransport
    private var generation = UUID()
    private var refreshVersion = 0
    private struct CommandObservation {
        let command: RemoteSessionCommand
        let previous: RemoteSession
        let onConfirmedPlay: (@MainActor (PlaybackRequest, RemoteSession) -> Void)?
        var minimumRefreshVersion: Int?
    }

    private var observations: [String: CommandObservation] = [:]
    private var socket: SessionsSocket?
    private var socketTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    var isSupported: Bool {
        session.mediaProvider.providerKind == .jellyfin
    }

    init(session: SessionStore, transport: (any RemoteSessionsTransport)? = nil) {
        self.session = session
        self.transport = transport ?? JellyfinRemoteSessionsTransport(client: session.client)
        session.onInvalidation(of: self) { $0.stopLiveUpdates() }
    }

    func refresh() async {
        guard isSupported, session.isActive else { return }
        let generation = generation
        refreshVersion += 1
        let version = refreshVersion
        if sessions.isEmpty {
            state = .loading
        }
        do {
            let loaded = try await transport.sessions(userID: session.user.id)
            guard !Task.isCancelled, session.isActive, generation == self.generation, version == refreshVersion else { return }
            sessions = loaded
            for (target, observation) in observations {
                guard let minimum = observation.minimumRefreshVersion, version >= minimum,
                      let current = loaded.first(where: { $0.id == target }), Self.confirms(observation.command, previous: observation.previous, current: current) else { continue }
                commandOutcomes[target] = .confirmed
                observations.removeValue(forKey: target)
                if case let .play(request) = observation.command {
                    observation.onConfirmedPlay?(request, current)
                }
            }
            state = .loaded
            refreshErrorMessage = nil
        } catch {
            guard session.isActive, generation == self.generation, version == refreshVersion else { return }
            let failure = GusError(from: error)
            guard !failure.isCancellation, !Task.isCancelled else {
                if sessions.isEmpty {
                    state = .idle
                }
                return
            }
            failure.handleIfUnauthorized(session: session)
            refreshErrorMessage = failure.localizedDescription
            state = sessions.isEmpty ? .failed(failure.localizedDescription) : .loaded
        }
    }

    func startLiveUpdates() {
        guard !Task.isCancelled, isSupported, session.isActive, socketTask == nil, pollingTask == nil else { return }
        let generation = generation
        if let token = session.client.accessToken,
           let url = SessionsSocket.socketURL(serverURL: session.server.url, accessToken: token, deviceID: DeviceIdentity.deviceID)
        {
            let socket = SessionsSocket(url: url)
            self.socket = socket
            socketTask = Task { [weak self] in
                for await event in socket.events() {
                    guard let self, !Task.isCancelled, self.session.isActive, generation == self.generation else { return }
                    if case .sessionsChanged = event {
                        await self.refresh()
                    }
                }
                guard let self, !Task.isCancelled, self.session.isActive, generation == self.generation else { return }
                self.socketTask = nil
                self.socket = nil
                self.startPolling()
            }
        } else {
            startPolling()
        }
    }

    func stopLiveUpdates() {
        generation = UUID()
        refreshVersion += 1
        observations.removeAll()
        socketTask?.cancel()
        socketTask = nil
        socket?.disconnect()
        socket = nil
        pollingTask?.cancel()
        pollingTask = nil
        if sessions.isEmpty {
            state = .idle
        }
    }

    private func startPolling() {
        guard pollingTask == nil, session.isActive else { return }
        let generation = generation
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: Self.pollingInterval) }
                catch { return }
                guard let self, !Task.isCancelled, self.session.isActive, generation == self.generation else { return }
                await self.refresh()
            }
        }
    }

    func togglePlayPause(sessionID: String) async throws -> ActionOutcome {
        try await perform(.playPause, on: sessionID)
    }

    func stopPlayback(sessionID: String) async throws -> ActionOutcome {
        try await perform(.stop, on: sessionID)
    }

    func nextTrack(sessionID: String) async throws -> ActionOutcome {
        try await perform(.nextTrack, on: sessionID)
    }

    func previousTrack(sessionID: String) async throws -> ActionOutcome {
        try await perform(.previousTrack, on: sessionID)
    }

    func volumeUp(sessionID: String) async throws -> ActionOutcome {
        try await perform(.volumeUp, on: sessionID)
    }

    func volumeDown(sessionID: String) async throws -> ActionOutcome {
        try await perform(.volumeDown, on: sessionID)
    }

    func toggleMute(sessionID: String) async throws -> ActionOutcome {
        try await perform(.toggleMute, on: sessionID)
    }

    func seek(sessionID: String, bySeconds offset: Double) async throws -> ActionOutcome {
        guard let current = sessions.first(where: { $0.id == sessionID })?.positionTicks else {
            throw GusError.server(String(localized: "This player has not reported a playback position yet."))
        }
        let target = max(0, current + PlaybackTime.ticks(fromSeconds: abs(offset)) * (offset < 0 ? -1 : 1))
        return try await perform(.seek(target), on: sessionID)
    }

    func play(_ request: PlaybackRequest, on sessionID: String, onConfirmed: (@MainActor (PlaybackRequest, RemoteSession) -> Void)? = nil) async throws -> ActionOutcome {
        try await perform(.play(request), on: sessionID, resolvingItem: true, onConfirmedPlay: onConfirmed)
    }

    private func perform(_ requested: RemoteSessionCommand, on target: String, resolvingItem: Bool = false, onConfirmedPlay: (@MainActor (PlaybackRequest, RemoteSession) -> Void)? = nil) async throws -> ActionOutcome {
        guard session.isActive, !Task.isCancelled else { throw GusError.cancelled }
        guard let previous = sessions.first(where: { $0.id == target }) else {
            throw GusError.server(String(localized: "This player is no longer active."))
        }
        guard previous.supports(requested) else {
            throw GusError.server(String(localized: "This player does not support that command."))
        }
        guard pendingSessionIDs.insert(target).inserted else {
            throw GusError.server(String(localized: "Wait for the pending command to finish."))
        }
        defer { pendingSessionIDs.remove(target) }
        let generation = generation
        commandOutcomes[target] = .pending
        commandNotices.removeValue(forKey: target)
        var sent = false
        do {
            var command = requested
            if resolvingItem, case var .play(request) = requested {
                let current = try await session.references.currentItem(request.item)
                guard current.id != nil, ContentRatingGate.admitsStored(current) else { throw GusError.notFound }
                guard previous.canPlay(current) else {
                    throw GusError.server(String(localized: "This player cannot play this type of media."))
                }
                request.item = current
                let source = request.streamSelection.mediaSourceID.flatMap { id in current.mediaSources.first { $0.id == id } } ?? (request.streamSelection.mediaSourceID == nil ? current.mediaSources.first : nil)
                if request.streamSelection.mediaSourceID != nil, source == nil {
                    throw GusError.server(String(localized: "That version is no longer available on the server."))
                }
                if let source {
                    let selection = request.selection(in: source)
                    if (request.audioTrack != nil && selection.audioStreamIndex == nil) || (request.subtitleIntent == .explicit && request.subtitleTrack != nil && selection.subtitleStreamIndex == nil) {
                        commandNotices[target] = String(localized: "A selected track was unavailable. The player will use its default tracks.")
                    }
                    request.streamSelection = selection
                }
                command = .play(request)
            }
            guard session.isActive, !Task.isCancelled, generation == self.generation else { throw GusError.cancelled }
            sent = true
            observations[target] = CommandObservation(command: command, previous: previous, onConfirmedPlay: onConfirmedPlay)
            try await transport.send(command, to: target)
            guard session.isActive, !Task.isCancelled, generation == self.generation else { throw GusError.cancelled }
            observations[target]?.minimumRefreshVersion = refreshVersion + 1
            commandOutcomes[target] = .accepted
            await refresh()
            guard session.isActive, !Task.isCancelled, generation == self.generation else { throw GusError.cancelled }
            // Only an eligible post-send readback can confirm. A superseded GET
            // may return without publishing, leaving an older matching snapshot.
            let outcome: ActionOutcome = commandOutcomes[target] == .confirmed ? .confirmed : .accepted
            commandOutcomes[target] = outcome
            return outcome
        } catch {
            let failure = GusError(from: error)
            failure.handleIfUnauthorized(session: session)
            if sent, Self.isAmbiguous(failure), session.isActive, generation == self.generation {
                // Only a later readback may resolve an uncertain command. While
                // send was suspended, an old matching snapshot proved nothing.
                observations[target]?.minimumRefreshVersion = refreshVersion + 1
                commandOutcomes[target] = .uncertain
                throw GusError.server(ActionOutcome.uncertain.remoteMessage)
            }
            observations.removeValue(forKey: target)
            commandOutcomes[target] = failure.isCancellation ? nil : .failed(failure)
            throw failure
        }
    }

    private static func isAmbiguous(_ failure: GusError) -> Bool {
        switch failure {
        case .timeout, .offline, .network, .cancelled: true
        default: false
        }
    }

    private static func confirms(_ command: RemoteSessionCommand, previous: RemoteSession, current: RemoteSession?) -> Bool {
        guard let current else { return false }
        switch command {
        case .playPause: return current.nowPlaying != nil && current.isPaused != previous.isPaused
        case .stop: return current.nowPlaying == nil
        case .nextTrack, .previousTrack: return current.nowPlaying?.id != nil && current.nowPlaying?.id != previous.nowPlaying?.id
        case let .seek(ticks): return current.positionTicks.map { abs($0 - ticks) <= PlaybackTime.ticks(fromSeconds: 5) } ?? false
        case .volumeUp: return previous.volumeLevel.map { old in current.volumeLevel.map { $0 > old } ?? false } ?? false
        case .volumeDown: return previous.volumeLevel.map { old in current.volumeLevel.map { $0 < old } ?? false } ?? false
        case .toggleMute: return current.isMuted != previous.isMuted
        case let .play(request):
            guard current.nowPlaying?.id == request.item.id else { return false }
            let selection = request.streamSelection
            if let id = selection.mediaSourceID, current.mediaSourceID != id {
                return false
            }
            if let audio = selection.audioStreamIndex, current.audioStreamIndex != audio {
                return false
            }
            if let subtitles = selection.subtitleStreamIndex, current.subtitleStreamIndex != subtitles {
                return false
            }
            if let ticks = request.requestedStartTicks,
               current.positionTicks.map({ abs($0 - ticks) <= PlaybackTime.ticks(fromSeconds: 5) }) != true
            {
                return false
            }
            return true
        }
    }
}
