import Foundation
import OSLog

/// A decoded Jellyfin WebSocket event relevant to SyncPlay.
enum SyncPlayEvent: Equatable {
    case command(SyncPlayCommandPayload)
    case groupUpdate(type: String, groupID: String?)
    case forceKeepAlive
}

/// The server-issued SyncPlay transport command.
struct SyncPlayCommandPayload: Equatable {
    enum Command: String {
        case play = "Unpause"
        case pause = "Pause"
        case stop = "Stop"
        case seek = "Seek"
    }

    let command: Command
    let positionTicks: Int?
}

/// Pure decoding of Jellyfin WebSocket frames into `SyncPlayEvent`s, separated from the
/// socket so the wire format stays unit-testable.
enum SyncPlayMessageDecoder {
    static func event(from data: Data) -> SyncPlayEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageType = object["MessageType"] as? String
        else { return nil }

        switch messageType {
        case "ForceKeepAlive":
            return .forceKeepAlive
        case "SyncPlayCommand":
            guard let payload = object["Data"] as? [String: Any],
                  let commandName = payload["Command"] as? String,
                  let command = SyncPlayCommandPayload.Command(rawValue: commandName)
            else { return nil }
            return .command(SyncPlayCommandPayload(
                command: command,
                positionTicks: payload["PositionTicks"] as? Int
            ))
        case "SyncPlayGroupUpdate":
            guard let payload = object["Data"] as? [String: Any],
                  let updateType = payload["Type"] as? String
            else { return nil }
            return .groupUpdate(type: updateType, groupID: payload["GroupId"] as? String)
        default:
            return nil
        }
    }
}

/// Jellyfin WebSocket listener for SyncPlay: yields decoded events and answers the
/// server's keep-alive requests. One socket per joined group session.
final class SyncPlaySocket: @unchecked Sendable {
    private let url: URL
    private let logger = Logger(subsystem: Logger.subsystem, category: "SyncPlay")
    private var task: URLSessionWebSocketTask?

    /// Builds the `/socket` URL from a server base URL and credentials.
    static func socketURL(serverURL: URL, accessToken: String, deviceID: String) -> URL? {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = components.path.appending("/socket")
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "api_key", value: accessToken),
            URLQueryItem(name: "deviceId", value: deviceID),
        ]
        return components.url
    }

    init(url: URL) {
        self.url = url
    }

    /// Connects and streams decoded SyncPlay events until cancelled or disconnected.
    func events() -> AsyncStream<SyncPlayEvent> {
        AsyncStream { continuation in
            let task = URLSession.shared.webSocketTask(with: url)
            self.task = task
            task.resume()

            func receiveNext() {
                task.receive { [weak self] result in
                    switch result {
                    case let .success(message):
                        if let data = Self.messageData(message),
                           let event = SyncPlayMessageDecoder.event(from: data)
                        {
                            if case .forceKeepAlive = event {
                                self?.sendKeepAlive()
                            }
                            continuation.yield(event)
                        }
                        receiveNext()
                    case let .failure(error):
                        self?.logger.info("SyncPlay socket closed: \(error.localizedDescription, privacy: .public)")
                        continuation.finish()
                    }
                }
            }
            receiveNext()

            continuation.onTermination = { _ in
                task.cancel(with: .normalClosure, reason: nil)
            }
        }
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func sendKeepAlive() {
        task?.send(.string(#"{"MessageType":"KeepAlive"}"#)) { _ in }
    }

    private static func messageData(_ message: URLSessionWebSocketTask.Message) -> Data? {
        switch message {
        case let .data(data):
            return data
        case let .string(string):
            return Data(string.utf8)
        @unknown default:
            return nil
        }
    }
}
