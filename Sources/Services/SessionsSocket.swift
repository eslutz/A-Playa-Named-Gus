import Foundation
import OSLog

/// A decoded Jellyfin WebSocket event relevant to remote-session monitoring.
enum SessionsSocketEvent: Equatable {
    /// The server pushed a sessions snapshot — re-fetch via REST (the REST DTOs are the
    /// decoding source of truth; the socket is just the change signal).
    case sessionsChanged
    case forceKeepAlive(timeoutSeconds: Int?)
}

/// Pure decoding of Jellyfin WebSocket frames into `SessionsSocketEvent`s, separated
/// from the socket so the wire format stays unit-testable.
enum SessionsSocketMessageDecoder {
    static func event(from data: Data) -> SessionsSocketEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageType = object["MessageType"] as? String
        else { return nil }

        switch messageType {
        case "ForceKeepAlive":
            return .forceKeepAlive(timeoutSeconds: object["Data"] as? Int)
        case "Sessions", "PlaybackStart", "PlaybackStopped", "PlaybackProgress":
            return .sessionsChanged
        default:
            return nil
        }
    }
}

/// Jellyfin WebSocket listener for live session updates: subscribes with
/// `SessionsStart`, yields change signals, and answers the keep-alive contract.
/// Used only while a remote-control surface is frontmost (battery rule from the
/// watchOS brief) — callers must `disconnect()` when leaving the screen.
final class SessionsSocket: @unchecked Sendable {
    private static let defaultKeepAliveTimeoutSeconds = 60
    /// initialDelay,interval (ms) for the server's session push subscription.
    private static let sessionsStartPayload = #"{"MessageType":"SessionsStart","Data":"0,1500"}"#
    private static let sessionsStopPayload = #"{"MessageType":"SessionsStop","Data":""}"#

    private let url: URL
    private let logger = Logger(subsystem: Logger.subsystem, category: "RemoteSessions")
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var keepAliveTask: Task<Void, Never>?

    /// Builds the `/socket` URL from a server base URL and credentials.
    /// The token rides in the query (`api_key`) — Jellyfin's WebSocket auth contract.
    /// The resulting URL is sensitive; never log it.
    static func socketURL(serverURL: URL, accessToken: String, deviceID: String) -> URL? {
        SyncPlaySocket.socketURL(serverURL: serverURL, accessToken: accessToken, deviceID: deviceID)
    }

    init(url: URL) {
        self.url = url
    }

    deinit {
        keepAliveTask?.cancel()
    }

    /// Connects, subscribes to session updates, and streams change events until
    /// cancelled or disconnected.
    func events() -> AsyncStream<SessionsSocketEvent> {
        AsyncStream { continuation in
            let task = URLSession.shared.webSocketTask(with: url)
            lock.withLock { self.task = task }
            task.resume()
            task.send(.string(Self.sessionsStartPayload)) { _ in }

            func receiveNext() {
                task.receive { [weak self] result in
                    switch result {
                    case let .success(message):
                        if let data = Self.messageData(message),
                           let event = SessionsSocketMessageDecoder.event(from: data)
                        {
                            if case let .forceKeepAlive(timeout) = event {
                                self?.scheduleKeepAlive(timeoutSeconds: timeout)
                            }
                            continuation.yield(event)
                        }
                        receiveNext()
                    case let .failure(error):
                        self?.logger.info("Sessions socket closed: \(error.localizedDescription, privacy: .public)")
                        self?.stopKeepAlive()
                        continuation.finish()
                    }
                }
            }
            receiveNext()

            continuation.onTermination = { [weak self] _ in
                self?.stopKeepAlive()
                task.send(.string(Self.sessionsStopPayload)) { _ in }
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
        task?.send(.string(Self.sessionsStopPayload)) { _ in }
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
