import Foundation
@testable import Gus
import Testing

@Suite("SyncPlay")
struct SyncPlayTests {
    @Test("decodes SyncPlay transport commands from socket frames")
    func decodesCommands() {
        let frame = """
        {"MessageType":"SyncPlayCommand","Data":{"GroupId":"g1","Command":"Seek","PositionTicks":1200000000,"When":"2026-06-10T12:00:00Z"}}
        """
        let event = SyncPlayMessageDecoder.event(from: Data(frame.utf8))

        #expect(event == .command(SyncPlayCommandPayload(command: .seek, positionTicks: 1_200_000_000)))
    }

    @Test("decodes pause and unpause commands")
    func decodesPauseUnpause() {
        let pause = #"{"MessageType":"SyncPlayCommand","Data":{"Command":"Pause"}}"#
        let unpause = #"{"MessageType":"SyncPlayCommand","Data":{"Command":"Unpause"}}"#

        #expect(SyncPlayMessageDecoder.event(from: Data(pause.utf8)) == .command(.init(command: .pause, positionTicks: nil)))
        #expect(SyncPlayMessageDecoder.event(from: Data(unpause.utf8)) == .command(.init(command: .play, positionTicks: nil)))
    }

    @Test("decodes group updates and keep-alive requests")
    func decodesGroupUpdatesAndKeepAlive() {
        let update = #"{"MessageType":"SyncPlayGroupUpdate","Data":{"GroupId":"g1","Type":"UserJoined"}}"#
        let keepAlive = #"{"MessageType":"ForceKeepAlive","Data":30}"#
        let unrelated = #"{"MessageType":"Sessions","Data":[]}"#

        #expect(SyncPlayMessageDecoder.event(from: Data(update.utf8)) == .groupUpdate(type: "UserJoined", groupID: "g1"))
        #expect(SyncPlayMessageDecoder.event(from: Data(keepAlive.utf8)) == .forceKeepAlive)
        #expect(SyncPlayMessageDecoder.event(from: Data(unrelated.utf8)) == nil)
    }

    @Test("socket URL swaps to the websocket scheme and carries credentials")
    func socketURLBuilds() throws {
        let serverURL = try #require(URL(string: "https://demo.example.com/jellyfin"))
        let url = try #require(SyncPlaySocket.socketURL(
            serverURL: serverURL,
            accessToken: "token-1",
            deviceID: "device-1"
        ))

        #expect(url.scheme == "wss")
        #expect(url.path == "/jellyfin/socket")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.contains(URLQueryItem(name: "api_key", value: "token-1")) == true)
        #expect(query?.contains(URLQueryItem(name: "deviceId", value: "device-1")) == true)

        let plainServerURL = try #require(URL(string: "http://192.168.1.5:8096"))
        let httpURL = try #require(SyncPlaySocket.socketURL(
            serverURL: plainServerURL,
            accessToken: "t",
            deviceID: "d"
        ))
        #expect(httpURL.scheme == "ws")
    }
}
