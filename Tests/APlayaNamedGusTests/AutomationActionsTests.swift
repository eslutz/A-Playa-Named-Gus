import Foundation
@testable import Gus
import Testing

@Suite("Shortcut automation actions") @MainActor
struct AutomationActionsTests {
    @Test("Remote shortcuts require exactly one active session for a stable device")
    func distinctPlayers() {
        let sessions = [
            player(session: "session1", device: "a"), player(session: "session2", device: "b"),
            player(session: "session3", device: "a"), player(session: "session4", device: nil),
            player(session: "session5", device: ""),
        ]
        #expect(GusRemotePlayerQuery.distinctDevices(sessions).map(\.id) == ["session2"])
    }

    @Test("Shortcut outputs preserve unconfirmed, queued, and failed states")
    func outcomes() throws {
        #expect(try GusActionStatus(.accepted) == .accepted)
        #expect(try GusActionStatus(.confirmed) == .confirmed)
        #expect(try GusActionStatus(.uncertain) == .uncertain)
        #expect(try GusActionStatus(.queued) == .queued)
        #expect(throws: GusError.forbidden) { try GusActionStatus(.failed(.forbidden)) }
    }

    @Test("Concurrent invocations cannot send a second command to the same device")
    func concurrentCommand() async throws {
        let key = UUID().uuidString
        var innerSent = false
        try await GusAutomationWrite.perform(key: key) {
            do {
                try await GusAutomationWrite.perform(key: key) { innerSent = true }
                Issue.record("Conflicting command was accepted.")
            } catch {
                #expect(!innerSent)
            }
        }
        try await GusAutomationWrite.perform(key: key) { innerSent = true }
        #expect(innerSent)
    }

    @Test("DVR attempts survive relaunch, expire after airing and never cross accounts")
    func recordingJournal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = AccountScope(serverID: "server", userID: "user")
        let other = AccountScope(serverID: "server", userID: "other")
        let now = Date()
        let end = now.addingTimeInterval(900)
        try GusRecordingJournal(scope: account, directory: directory).set("guide-id", expires: end, now: now)
        let reopened = GusRecordingJournal(scope: account, directory: directory)
        #expect(try reopened.contains("guide-id", now: now))
        #expect(try !GusRecordingJournal(scope: other, directory: directory).contains("guide-id", now: now))
        #expect(try !reopened.contains("guide-id", now: end))
        try reopened.set("guide-id", expires: nil, now: now)
        #expect(try !reopened.contains("guide-id", now: now))
    }

    @Test("Chapter commands preserve one-based numbering and never seek beyond either end")
    func chapterSelection() {
        let targets = [
            PlaybackChapter(id: 0, title: "Opening", startPositionTicks: 0),
            PlaybackChapter(id: 1, title: "Middle", startPositionTicks: PlaybackTime.ticks(fromSeconds: 30)),
        ]
        #expect(GusChapterAction.numbered.target(in: targets, at: 2, number: 2)?.title == "Middle")
        #expect(GusChapterAction.numbered.target(in: targets, at: 2, number: 0) == nil)
        #expect(GusChapterAction.next.target(in: targets, at: 0, number: nil)?.title == "Middle")
        #expect(GusChapterAction.next.target(in: targets, at: 40, number: nil) == nil)
        #expect(GusChapterAction.previous.target(in: targets, at: 30, number: nil)?.title == "Opening")
    }

    @Test("A saved slideshow directive never leaves the device through a playback URL")
    func slideshowSharing() {
        var request = PlaybackRequest(item: MediaItem(id: "photo", parentID: "album", type: .photo))
        request.slideshowAlbumID = "album"
        #expect(request.sharingIntent.slideshowAlbumID == nil)
    }

    @Test("A moved airing requires review even if the program identifier is unchanged")
    func changedGuideAiring() {
        let start = Date(), end = start.addingTimeInterval(900)
        let a = LiveTVGuideProgram(id: "program", channelID: "channel", channelName: nil, name: "Example", rating: nil, start: start, end: end, timerID: nil)
        let b = LiveTVGuideProgram(id: "program", channelID: "channel", channelName: nil, name: "Example", rating: nil, start: end, end: end.addingTimeInterval(900), timerID: nil)
        #expect(!a.isSameAiring(as: b))
    }

    private func player(session: String, device: String?) -> RemoteSession {
        RemoteSession(
            id: session,
            deviceID: device,
            deviceName: "Living Room",
            client: "Gus",
            userName: nil,
            nowPlaying: nil,
            positionTicks: nil,
            isPaused: false,
            volumeLevel: nil,
            isMuted: false,
            supportsMediaControl: true,
            canSeek: false,
            supportedCommands: [],
            playableMediaTypes: ["Audio"],
            mediaSourceID: nil,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
    }
}
