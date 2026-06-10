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
/// Inbound commands arrive on the server WebSocket; local pause/play is observed from
/// the player's rate and forwarded, with an echo guard so remote commands don't bounce.
@MainActor
@Observable
final class SyncPlayStore {
    struct Group: Identifiable, Equatable {
        let id: String
        let name: String
        let participants: [String]
    }

    private(set) var groups: [Group] = []
    private(set) var activeGroupID: String?
    private(set) var participants: [String] = []
    private(set) var statusMessage: String?

    private let session: SessionStore
    private weak var player: AVPlayer?
    private let logger = Logger(subsystem: Logger.subsystem, category: "SyncPlay")
    private var socket: SyncPlaySocket?
    private var socketTask: Task<Void, Never>?
    private var rateObservation: NSKeyValueObservation?
    private var isApplyingRemoteCommand = false

    /// SyncPlay rides Jellyfin's session APIs; other providers hide the feature.
    var isSupported: Bool {
        session.mediaProvider.providerKind == .jellyfin
    }

    var isInGroup: Bool {
        activeGroupID != nil
    }

    init(session: SessionStore, player: AVPlayer?) {
        self.session = session
        self.player = player
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
            startObservingPlayerRate()
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
        rateObservation?.invalidate()
        rateObservation = nil
        activeGroupID = nil
        participants = []
    }

    // MARK: - Outbound commands

    func sendSeek(toTicks ticks: Int) async {
        guard isInGroup else { return }
        try? await session.client.send(Paths.syncPlaySeek(SeekRequestDto(positionTicks: ticks)))
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
        guard let player else { return }
        isApplyingRemoteCommand = true
        defer { isApplyingRemoteCommand = false }

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
    }

    // MARK: - Local action forwarding

    /// Forwards pause/play coming from the AVKit transport to the group, skipping
    /// changes we just applied from a remote command.
    private func startObservingPlayerRate() {
        guard let player else { return }
        rateObservation = player.observe(\.rate, options: [.old, .new]) { [weak self] _, change in
            guard let self, let oldRate = change.oldValue, let newRate = change.newValue,
                  oldRate != newRate
            else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isInGroup, !self.isApplyingRemoteCommand else { return }
                if newRate == 0 {
                    try? await self.session.client.send(Paths.syncPlayPause)
                } else {
                    try? await self.session.client.send(Paths.syncPlayUnpause)
                }
            }
        }
    }
}
