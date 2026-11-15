import Foundation
@testable import Gus
import Testing

@Suite("Remote sessions")
struct RemoteSessionsTests {
    @Test("decodes session-change signals from socket frames")
    func decodesSessionChanges() {
        let sessions = #"{"MessageType":"Sessions","Data":[]}"#
        let start = #"{"MessageType":"PlaybackStart","Data":{}}"#
        let progress = #"{"MessageType":"PlaybackProgress","Data":{}}"#
        let stopped = #"{"MessageType":"PlaybackStopped","Data":{}}"#
        let unrelated = #"{"MessageType":"GeneralCommand","Data":{}}"#

        #expect(SessionsSocketMessageDecoder.event(from: Data(sessions.utf8)) == .sessionsChanged)
        #expect(SessionsSocketMessageDecoder.event(from: Data(start.utf8)) == .sessionsChanged)
        #expect(SessionsSocketMessageDecoder.event(from: Data(progress.utf8)) == .sessionsChanged)
        #expect(SessionsSocketMessageDecoder.event(from: Data(stopped.utf8)) == .sessionsChanged)
        #expect(SessionsSocketMessageDecoder.event(from: Data(unrelated.utf8)) == nil)
    }

    @Test("decodes the keep-alive contract")
    func decodesKeepAlive() {
        let keepAlive = #"{"MessageType":"ForceKeepAlive","Data":45}"#

        #expect(SessionsSocketMessageDecoder.event(from: Data(keepAlive.utf8)) == .forceKeepAlive(timeoutSeconds: 45))
    }
}

@MainActor @Suite("Remote command and snapshot lifecycle")
struct RemoteSessionLifecycleTests {
    @Test("a late snapshot cannot replace a newer refresh")
    func supersededRefresh() async throws {
        let (store, transport, _) = try fixture()
        let first = RemoteGate<[RemoteSession]>()
        var calls = 0
        transport.fetch = {
            calls += 1
            if calls == 1 {
                return await first.suspend()
            }
            return [Self.remote(name: "New")]
        }
        let task = Task { await store.refresh() }
        await first.waitUntilStarted()
        await store.refresh()
        first.finish([Self.remote(name: "Old")])
        await task.value
        #expect(store.sessions.first?.deviceName == "New")
    }

    @Test("leaving or invalidating a session rejects a delayed refresh", arguments: [false, true])
    func invalidatedRefresh(invalidateSession: Bool) async throws {
        let (store, transport, session) = try fixture()
        let gate = RemoteGate<[RemoteSession]>()
        transport.fetch = { await gate.suspend() }
        let task = Task { await store.refresh() }
        await gate.waitUntilStarted()
        if invalidateSession {
            session.invalidate()
        } else {
            store.stopLiveUpdates()
        }
        gate.finish([Self.remote()])
        await task.value
        #expect(store.sessions.isEmpty)
        #expect(store.state == .idle)
    }

    @Test("one pending target rejects conflicting commands and acceptance is not playback confirmation")
    func pendingAndConfirmation() async throws {
        let (store, transport, _) = try fixture()
        await store.refresh()
        let gate = RemoteGate<Void>()
        transport.sendCommand = { _, _ in await gate.suspend() }
        let first = Task { try await store.togglePlayPause(sessionID: "remote") }
        await gate.waitUntilStarted()
        #expect(store.pendingSessionIDs == ["remote"])
        await #expect(throws: GusError.self) { try await store.nextTrack(sessionID: "remote") }
        #expect(transport.sent.count == 1)
        gate.finish(())
        #expect(try await first.value == .accepted)
        #expect(store.pendingSessionIDs.isEmpty)
        transport.values = [Self.remote(paused: true)]
        await store.refresh()
        #expect(store.commandOutcomes["remote"] == .confirmed)
    }

    @Test("permission errors throw, release pending state and do not expire authentication")
    func permissionFailure() async throws {
        let (store, transport, session) = try fixture()
        await store.refresh()
        transport.sendCommand = { _, _ in throw GusError.forbidden }
        await #expect(throws: GusError.forbidden) { try await store.stopPlayback(sessionID: "remote") }
        #expect(store.pendingSessionIDs.isEmpty)
        #expect(transport.sent.count == 1)
        #expect(session.reauthenticationRequest == nil)
        #expect(session.isActive)
        #expect(store.sessions.count == 1)
    }

    @Test("a lost command response is uncertain and is never automatically repeated")
    func uncertainCommand() async throws {
        let (store, transport, _) = try fixture()
        await store.refresh()
        transport.sendCommand = { _, _ in throw URLError(.timedOut) }
        await #expect(throws: GusError.self) { try await store.togglePlayPause(sessionID: "remote") }
        #expect(transport.sent.count == 1)
        #expect(store.commandOutcomes["remote"] == .uncertain)
        #expect(store.pendingSessionIDs.isEmpty)
        transport.values = [Self.remote(paused: true)]
        await store.refresh()
        #expect(store.commandOutcomes["remote"] == .confirmed)
    }

    @Test("failed refresh preserves players and vanished targets are not commanded")
    func refreshFailureAndVanishedPlayer() async throws {
        let (store, transport, _) = try fixture()
        await store.refresh()
        transport.fetch = { throw URLError(.notConnectedToInternet) }
        await store.refresh()
        #expect(store.state == .loaded)
        #expect(store.sessions.count == 1)
        #expect(store.refreshErrorMessage != nil)
        transport.fetch = { [] }
        await store.refresh()
        await #expect(throws: GusError.self) { try await store.stopPlayback(sessionID: "remote") }
        #expect(transport.sent.isEmpty)
    }

    @Test("unadvertised remote capabilities cannot send transport commands")
    func unsupportedCommands() async throws {
        let (store, transport, _) = try fixture()
        transport.values = [Self.remote(controls: false, seekable: false, commands: [])]
        await store.refresh()
        await #expect(throws: GusError.self) { try await store.seek(sessionID: "remote", bySeconds: 15) }
        await #expect(throws: GusError.self) { try await store.volumeUp(sessionID: "remote") }
        await #expect(throws: GusError.self) { try await store.play(PlaybackRequest(item: MediaItem(id: "video")), on: "remote") }
        #expect(transport.sent.isEmpty)
        #expect(store.pendingSessionIDs.isEmpty)
    }

    @Test("Play On preserves source, semantic tracks, subtitle Off and explicit start intent")
    func remotePlaybackIntent() async throws {
        let english = MediaStreamInfo(index: 8, language: "eng", title: "English", type: .audio)
        let source = MediaSource(id: "extended", mediaStreams: [MediaStreamInfo(index: 3, language: "eng", title: "English", type: .audio)])
        let item = MediaItem(id: "movie", mediaSources: [source], officialRating: "G", type: .movie)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in item }
        let (store, transport, _) = try fixture(provider: provider)
        await store.refresh()
        let request = PlaybackRequest(item: item, streamSelection: .init(audioStreamIndex: 8, subtitleStreamIndex: -1, mediaSourceID: "extended"), audioTrack: english, subtitleIntent: .off, start: .fromBeginning, startPositionTicks: 500)
        #expect(try await store.play(request, on: "remote") == .accepted)
        guard case let .play(sent) = try #require(transport.sent.first) else { Issue.record("Expected a remote Play request"); return }
        #expect(sent.streamSelection.mediaSourceID == "extended")
        #expect(sent.streamSelection.audioStreamIndex == 3)
        #expect(sent.streamSelection.subtitleStreamIndex == -1)
        #expect(sent.requestedStartTicks == 0)
    }

    @Test("replaying the same item requires the explicit position to be observed before confirmation", arguments: [true, false])
    func explicitPositionConfirmation(fromBeginning: Bool) async throws {
        let source = MediaSource(id: "source")
        let item = MediaItem(id: "video", mediaSources: [source], officialRating: "G", type: .movie)
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in item }
        let (store, transport, _) = try fixture(provider: provider)
        let targetTicks = PlaybackTime.ticks(fromSeconds: fromBeginning ? 0 : 60)
        var snapshot = Self.remote()
        snapshot = RemoteSession(
            id: snapshot.id,
            deviceName: snapshot.deviceName,
            client: snapshot.client,
            userName: snapshot.userName,
            nowPlaying: item,
            positionTicks: targetTicks + PlaybackTime.ticks(fromSeconds: 30),
            isPaused: snapshot.isPaused,
            volumeLevel: snapshot.volumeLevel,
            isMuted: snapshot.isMuted,
            supportsMediaControl: snapshot.supportsMediaControl,
            canSeek: snapshot.canSeek,
            supportedCommands: snapshot.supportedCommands,
            playableMediaTypes: snapshot.playableMediaTypes,
            mediaSourceID: source.id,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
        transport.values = [snapshot]
        await store.refresh()
        let request = PlaybackRequest(
            item: item,
            streamSelection: .init(mediaSourceID: source.id),
            start: fromBeginning ? .fromBeginning : .automatic,
            startPositionTicks: targetTicks
        )
        #expect(try await store.play(request, on: "remote") == .accepted)
        #expect(store.commandOutcomes["remote"] == .accepted)

        let matching = RemoteSession(
            id: snapshot.id,
            deviceName: snapshot.deviceName,
            client: snapshot.client,
            userName: snapshot.userName,
            nowPlaying: item,
            positionTicks: targetTicks + PlaybackTime.ticks(fromSeconds: 2),
            isPaused: snapshot.isPaused,
            volumeLevel: snapshot.volumeLevel,
            isMuted: snapshot.isMuted,
            supportsMediaControl: snapshot.supportsMediaControl,
            canSeek: snapshot.canSeek,
            supportedCommands: snapshot.supportedCommands,
            playableMediaTypes: snapshot.playableMediaTypes,
            mediaSourceID: source.id,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
        transport.values = [matching]
        await store.refresh()
        #expect(store.commandOutcomes["remote"] == .confirmed)
        #expect(transport.sent.count == 1)
    }

    private func fixture(provider: (any MediaProviderSession)? = nil) throws -> (RemoteSessionsStore, RemoteTransportStub, SessionStore) {
        let url = try #require(URL(string: "https://remote.example.invalid"))
        let session = SessionStore(
            client: JellyfinClientFactory.makeClient(url: url, accessToken: "fixture-token"),
            user: StoredUser(id: "user", name: "Gus", serverID: "server"),
            server: ServerConnection(id: "server", name: "Server", url: url), mediaProvider: provider
        )
        let transport = RemoteTransportStub(values: [Self.remote()])
        return (RemoteSessionsStore(session: session, transport: transport), transport, session)
    }

    private static func remote(name: String = "Player", paused: Bool = false, controls: Bool = true, seekable: Bool = true, commands: Set<String> = ["VolumeUp", "VolumeDown", "ToggleMute"]) -> RemoteSession {
        RemoteSession(id: "remote", deviceName: name, client: "Gus", userName: "Gus", nowPlaying: MediaItem(id: "video"), positionTicks: 0, isPaused: paused, volumeLevel: 50, isMuted: false, supportsMediaControl: controls, canSeek: seekable, supportedCommands: commands, playableMediaTypes: ["Video", "Audio"], mediaSourceID: nil, audioStreamIndex: nil, subtitleStreamIndex: nil)
    }
}

@MainActor
private final class RemoteTransportStub: RemoteSessionsTransport {
    var values: [RemoteSession]
    var fetch: (() async throws -> [RemoteSession])?
    var sendCommand: ((RemoteSessionCommand, String) async throws -> Void)?
    var sent: [RemoteSessionCommand] = []

    init(values: [RemoteSession]) {
        self.values = values
    }

    func sessions(userID: String) async throws -> [RemoteSession] {
        if let fetch {
            return try await fetch()
        }
        return values
    }

    func send(_ command: RemoteSessionCommand, to sessionID: String) async throws {
        sent.append(command)
        try await sendCommand?(command, sessionID)
    }
}

@MainActor
private final class RemoteGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func suspend() async -> Value {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if continuation != nil {
            return
        }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
