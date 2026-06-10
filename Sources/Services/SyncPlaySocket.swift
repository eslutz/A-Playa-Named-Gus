import Foundation
import OSLog

/// A decoded Jellyfin WebSocket event relevant to SyncPlay.
enum SyncPlayEvent: Equatable {
    case command(SyncPlayCommandPayload)
    case groupUpdate(type: String, groupID: String?)
    case forceKeepAlive(timeoutSeconds: Int?)
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
            return .forceKeepAlive(timeoutSeconds: object["Data"] as? Int)
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
/// server's keep-alive contract. One socket per joined group session.
///
/// The server announces a session timeout via `ForceKeepAlive`; the client must then
/// send `KeepAlive` periodically (half the timeout) or the server closes the socket —
/// a single reply is not enough.
final class SyncPlaySocket: @unchecked Sendable {
    private static let defaultKeepAliveTimeoutSeconds = 60

    private let url: URL
    private let logger = Logger(subsystem: Logger.subsystem, category: "SyncPlay")
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var keepAliveTask: Task<Void, Never>?

    /// Builds the `/socket` URL from a server base URL and credentials.
    ///
    /// The token rides in the query (`api_key`) — Jellyfin's WebSocket auth contract.
    /// The resulting URL is sensitive; never log it.
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

    deinit {
        keepAliveTask?.cancel()
    }

    /// Connects and streams decoded SyncPlay events until cancelled or disconnected.
    func events() -> AsyncStream<SyncPlayEvent> {
        AsyncStream { continuation in
            let task = URLSession.shared.webSocketTask(with: url)
            lock.withLock { self.task = task }
            task.resume()

            func receiveNext() {
                task.receive { [weak self] result in
                    switch result {
                    case let .success(message):
                        if let data = Self.messageData(message),
                           let event = SyncPlayMessageDecoder.event(from: data)
                        {
                            if case let .forceKeepAlive(timeout) = event {
                                self?.scheduleKeepAlive(timeoutSeconds: timeout)
                            }
                            continuation.yield(event)
                        }
                        receiveNext()
                    case let .failure(error):
                        self?.logger.info("SyncPlay socket closed: \(error.localizedDescription, privacy: .public)")
                        self?.stopKeepAlive()
                        continuation.finish()
                    }
                }
            }
            receiveNext()

            continuation.onTermination = { [weak self] _ in
                self?.stopKeepAlive()
                task.cancel(with: .normalClosure, reason: nil)
            }
        }
    }

    func disconnect() {
        stopKeepAlive()
        let task = lock.withLock { () -> URLSessionWebSocketTask? in
            defer { self.task = nil }
            return self.task
        }
        task?.cancel(with: .normalClosure, reason: nil)
    }

    // MARK: - Keep-alive

    private func scheduleKeepAlive(timeoutSeconds: Int?) {
        let timeout = max(timeoutSeconds ?? Self.defaultKeepAliveTimeoutSeconds, 10)
        let interval = Duration.seconds(timeout / 2)
        stopKeepAlive()
        let keepAlive = Task { [weak self] in
            while !Task.isCancelled {
                self?.sendKeepAlive()
                try? await Task.sleep(for: interval)
            }
        }
        lock.withLock { keepAliveTask = keepAlive }
    }

    private func stopKeepAlive() {
        let task = lock.withLock { () -> Task<Void, Never>? in
            defer { keepAliveTask = nil }
            return keepAliveTask
        }
        task?.cancel()
    }

    private func sendKeepAlive() {
        let task = lock.withLock { self.task }
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
