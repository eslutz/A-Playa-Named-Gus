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
        let unrelated = #"{"MessageType":"SyncPlayCommand","Data":{}}"#

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
