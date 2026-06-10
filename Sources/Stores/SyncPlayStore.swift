import AVFoundation
import Foundation
import JellyfinAPI
import Observation
import OSLog

/// Jellyfin SyncPlay shared playback: group membership, sending local transport
/// actions, and applying server-issued commands to the active player.
///
/// SyncPlay is intentionally Jellyfin-specific — it stays behind a `providerKind` gate
/// instead of joining the shared provider contract, per the provider-architecture rules.
/// Inbound commands arrive on the server WebSocket; local pause/play/seek are observed
/// from the attached player and forwarded. Because remote commands are applied through
/// the same player APIs the observers watch, forwarding is suppressed for a short
/// window after each applied command (the KVO/notification hop is asynchronous, so a
/// boolean flag cleared on return would never be seen by the forwarding task).
@MainActor
@Observable
final class SyncPlayStore {
    struct Group: Identifiable, Equatable {
        let id: String
        let name: String
        let participants: [String]
    }

    /// Local transport changes within this window of a remote command are echoes.
    private static let echoSuppressionWindow: TimeInterval = 1.0

    private(set) var groups: [Group] = []
    private(set) var activeGroupID: String?
    private(set) var participants: [String] = []
    private(set) var statusMessage: String?

    private let session: SessionStore
    private weak var attachedPlayer: AVPlayer?
    private let logger = Logger(subsystem: Logger.subsystem, category: "SyncPlay")
    private var socket: SyncPlaySocket?
    private var socketTask: Task<Void, Never>?
    private var rateObservation: NSKeyValueObservation?
    private var seekObserver: NSObjectProtocol?
    private var lastRemoteCommandDate: Date = .distantPast

    /// SyncPlay rides Jellyfin's session APIs; other providers hide the feature.
    var isSupported: Bool {
        session.mediaProvider.providerKind == .jellyfin
    }

    var isInGroup: Bool {
        activeGroupID != nil
    }

    init(session: SessionStore) {
        self.session = session
    }

    /// Attaches (or re-attaches) the live player. The playback store rebuilds its
    /// `AVPlayer` across Play Next transitions, so the view calls this whenever the
    /// player instance changes; commands and observers always target the current one.
    func attachPlayer(_ player: AVPlayer?) {
        guard attachedPlayer !== player else { return }
        detachObservers()
        attachedPlayer = player
        if isInGroup {
            startObservingLocalTransport()
        }
    }

    func loadGroups() async {
        guard isSupported else { return }
        do {
            let response = try await session.client.send(Paths.syncPlayGetGroups)
            groups = response.value.compactMap { group in
                guard let id = group.groupID else { return nil }
                return Group(
                    id: id,
                    name: group.groupName ?? String(localized: "SyncPlay Group", comment: "Fallback SyncPlay group name"),
                    participants: group.participants ?? []
                )
            }
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            statusMessage = gusError.localizedDescription
        }
    }

    func createGroup(named name: String) async {
        guard isSupported else { return }
        do {
            let response = try await session.client.send(Paths.syncPlayCreateGroup(NewGroupRequestDto(groupName: name)))
            if let id = response.value.groupID {
                await join(groupID: id)
            }
        } catch {
            statusMessage = GusError(from: error).localizedDescription
        }
    }

    func join(groupID: String) async {
        guard isSupported else { return }
        do {
            try await session.client.send(Paths.syncPlayJoinGroup(JoinGroupRequestDto(groupID: groupID)))
            activeGroupID = groupID
            participants = groups.first { $0.id == groupID }?.participants ?? []
            startListening()
            startObservingLocalTransport()
        } catch {
            statusMessage = GusError(from: error).localizedDescription
        }
    }

    func leave() async {
        guard isSupported, isInGroup else { return }
        try? await session.client.send(Paths.syncPlayLeaveGroup)
        stop()
    }

    /// Stops listening without a server round-trip (player teardown).
    func stop() {
        socketTask?.cancel()
        socketTask = nil
        socket?.disconnect()
        socket = nil
        detachObservers()
        activeGroupID = nil
        participants = []
    }

    private func detachObservers() {
        rateObservation?.invalidate()
        rateObservation = nil
        if let seekObserver {
            NotificationCenter.default.removeObserver(seekObserver)
        }
        seekObserver = nil
    }

    // MARK: - Inbound commands

    private func startListening() {
        guard socket == nil,
              let token = session.client.accessToken,
              let url = SyncPlaySocket.socketURL(
                  serverURL: session.server.url,
                  accessToken: token,
                  deviceID: DeviceIdentity.deviceID
              )
        else { return }

        let socket = SyncPlaySocket(url: url)
        self.socket = socket
        socketTask = Task { [weak self] in
            for await event in socket.events() {
                guard !Task.isCancelled else { return }
                await self?.handle(event)
            }
        }
    }

    private func handle(_ event: SyncPlayEvent) async {
        switch event {
        case let .command(payload):
            await apply(payload)
        case let .groupUpdate(type, _):
            switch type {
            case "UserJoined", "UserLeft", "GroupJoined":
                await loadGroups()
                participants = groups.first { $0.id == activeGroupID }?.participants ?? participants
            case "GroupLeft", "GroupDoesNotExist":
                stop()
            default:
                break
            }
        case .forceKeepAlive:
            break // answered inside the socket
        }
    }

    private func apply(_ payload: SyncPlayCommandPayload) async {
        guard let player = attachedPlayer else { return }
        lastRemoteCommandDate = Date()

        if let ticks = payload.positionTicks {
            await player.seek(
                to: CMTime(seconds: PlaybackTime.seconds(fromTicks: ticks), preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }

        switch payload.command {
        case .play:
            player.play()
        case .pause, .stop:
            player.pause()
        case .seek:
            break // position already applied above
        }
        // The seek/rate change lands in the observers asynchronously; stamp again so
        // the suppression window starts when the command finished applying.
        lastRemoteCommandDate = Date()
    }

    // MARK: - Local action forwarding

    private var isWithinEchoWindow: Bool {
        Date().timeIntervalSince(lastRemoteCommandDate) < Self.echoSuppressionWindow
    }

    /// Forwards pause/play and seeks coming from the AVKit transport to the group,
    /// skipping changes inside the suppression window (those are remote echoes).
    private func startObservingLocalTransport() {
        detachObservers()
        guard let player = attachedPlayer else { return }

        rateObservation = player.observe(\.rate, options: [.old, .new]) { [weak self] _, change in
            guard let oldRate = change.oldValue, let newRate = change.newValue,
                  oldRate != newRate
            else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isInGroup, !self.isWithinEchoWindow else { return }
                if newRate == 0 {
                    try? await self.session.client.send(Paths.syncPlayPause)
                } else {
                    try? await self.session.client.send(Paths.syncPlayUnpause)
                }
            }
        }

        seekObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.timeJumpedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self, self.isInGroup, !self.isWithinEchoWindow,
                      let item = notification.object as? AVPlayerItem,
                      let player = self.attachedPlayer,
                      item === player.currentItem
                else { return }
                let ticks = PlaybackTime.ticks(fromSeconds: player.currentTime().seconds)
                try? await self.session.client.send(Paths.syncPlaySeek(SeekRequestDto(positionTicks: ticks)))
            }
        }
    }
}
