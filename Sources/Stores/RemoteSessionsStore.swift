import Foundation
import JellyfinAPI
import Observation
import OSLog

/// Another Jellyfin client on the same server that this device can remote-control.
struct RemoteSession: Identifiable, Equatable {
    let id: String
    let deviceName: String
    let client: String
    let userName: String?
    let nowPlaying: MediaItem?
    let positionTicks: Int?
    let isPaused: Bool
    let volumeLevel: Int?
    let isMuted: Bool
}

/// Remote control of the household's other Jellyfin clients via the `Sessions` API:
/// list controllable sessions, send transport/volume commands, and start remote
/// playback ("quick resume" sends Continue Watching items to a chosen client).
///
/// This rides Jellyfin's session APIs directly and stays behind a `providerKind` gate
/// instead of joining the shared provider contract; the
/// session-based model also serves the future Emby provider per the roadmap.
/// Live updates use the server WebSocket only while a remote-control surface is
/// frontmost, with a timed polling fallback (battery rules from the watchOS brief).
@MainActor
@Observable
final class RemoteSessionsStore {
    /// Sessions seen by the server within this window count as active.
    private static let activeWindowSeconds = 960
    /// Polling cadence when the WebSocket is unavailable.
    private static let pollingInterval = Duration.seconds(15)

    private(set) var state: LoadState = .idle
    private(set) var sessions: [RemoteSession] = []

    private let session: SessionStore
    private let logger = Logger(subsystem: Logger.subsystem, category: "RemoteSessions")
    private var socket: SessionsSocket?
    private var socketTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    var isSupported: Bool {
        session.mediaProvider.providerKind == .jellyfin
    }

    init(session: SessionStore) {
        self.session = session
    }

    // MARK: - Loading

    func refresh() async {
        guard isSupported else {
            state = .loaded
            return
        }
        if state == .idle {
            state = .loading
        }
        do {
            let parameters = Paths.GetSessionsParameters(
                controllableByUserID: session.user.id,
                activeWithinSeconds: Self.activeWindowSeconds
            )
            let response = try await session.client.send(Paths.getSessions(parameters: parameters))
            sessions = response.value.compactMap(Self.remoteSession(from:))
            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            logger.error("Sessions load failed: \(gusError.localizedDescription, privacy: .public)")
            state = .failed(gusError.localizedDescription)
        }
    }

    private static func remoteSession(from dto: SessionInfoDto) -> RemoteSession? {
        guard let id = dto.id,
              dto.isSupportsRemoteControl == true,
              dto.deviceID != DeviceIdentity.deviceID // never remote-control ourselves
        else { return nil }
        return RemoteSession(
            id: id,
            deviceName: dto.deviceName ?? String(localized: "Unknown Device", comment: "Fallback remote session device name"),
            client: dto.client ?? "Jellyfin",
            userName: dto.userName,
            nowPlaying: dto.nowPlayingItem.map(JellyfinMediaItemMapper.mediaItem(from:)),
            positionTicks: dto.playState?.positionTicks,
            isPaused: dto.playState?.isPaused ?? false,
            volumeLevel: dto.playState?.volumeLevel,
            isMuted: dto.playState?.isMuted ?? false
        )
    }

    // MARK: - Live updates (frontmost remote-control UI only)

    func startLiveUpdates() {
        guard isSupported, socketTask == nil, pollingTask == nil else { return }

        if let token = session.client.accessToken,
           let url = SessionsSocket.socketURL(
               serverURL: session.server.url,
               accessToken: token,
               deviceID: DeviceIdentity.deviceID
           )
        {
            let socket = SessionsSocket(url: url)
            self.socket = socket
            socketTask = Task { [weak self] in
                for await event in socket.events() {
                    guard !Task.isCancelled else { return }
                    if case .sessionsChanged = event {
                        await self?.refresh()
                    }
                }
                // Socket ended (network/server) — fall back to polling if still active.
                guard let self, !Task.isCancelled else { return }
                self.socketTask = nil
                self.socket = nil
                self.startPolling()
            }
        } else {
            startPolling()
        }
    }

    func stopLiveUpdates() {
        socketTask?.cancel()
        socketTask = nil
        socket?.disconnect()
        socket = nil
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollingInterval)
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    // MARK: - Transport commands

    func togglePlayPause(sessionID: String) async {
        await sendPlaystate(.playPause, sessionID: sessionID)
    }

    func stopPlayback(sessionID: String) async {
        await sendPlaystate(.stop, sessionID: sessionID)
    }

    func nextTrack(sessionID: String) async {
        await sendPlaystate(.nextTrack, sessionID: sessionID)
    }

    func previousTrack(sessionID: String) async {
        await sendPlaystate(.previousTrack, sessionID: sessionID)
    }

    /// Seeks relative to the session's last reported position.
    func seek(sessionID: String, bySeconds offset: Double) async {
        guard let current = sessions.first(where: { $0.id == sessionID })?.positionTicks else { return }
        let target = max(0, current + PlaybackTime.ticks(fromSeconds: abs(offset)) * (offset < 0 ? -1 : 1))
        do {
            try await session.client.send(Paths.sendPlaystateCommand(
                sessionID: sessionID,
                command: PlaystateCommand.seek.rawValue,
                seekPositionTicks: target
            ))
            await refresh()
        } catch {
            logger.error("Remote seek failed: \(GusError(from: error).localizedDescription, privacy: .public)")
        }
    }

    func volumeUp(sessionID: String) async {
        await sendGeneral("VolumeUp", sessionID: sessionID)
    }

    func volumeDown(sessionID: String) async {
        await sendGeneral("VolumeDown", sessionID: sessionID)
    }

    func toggleMute(sessionID: String) async {
        await sendGeneral("ToggleMute", sessionID: sessionID)
    }

    /// Starts playback of an item on a remote client (quick resume / play-on).
    func play(itemID: String, on sessionID: String, startPositionTicks: Int? = nil) async {
        do {
            try await session.client.send(Paths.play(sessionID: sessionID, parameters: Paths.PlayParameters(
                playCommand: .playNow,
                itemIDs: [itemID],
                startPositionTicks: startPositionTicks
            )))
        } catch {
            logger.error("Remote play failed: \(GusError(from: error).localizedDescription, privacy: .public)")
        }
    }

    private func sendPlaystate(_ command: PlaystateCommand, sessionID: String) async {
        do {
            try await session.client.send(Paths.sendPlaystateCommand(sessionID: sessionID, command: command.rawValue))
            await refresh()
        } catch {
            logger.error("Remote \(command.rawValue, privacy: .public) failed: \(GusError(from: error).localizedDescription, privacy: .public)")
        }
    }

    private func sendGeneral(_ command: String, sessionID: String) async {
        do {
            try await session.client.send(Paths.sendGeneralCommand(sessionID: sessionID, command: command))
            await refresh()
        } catch {
            logger.error("Remote \(command, privacy: .public) failed: \(GusError(from: error).localizedDescription, privacy: .public)")
        }
    }
}
