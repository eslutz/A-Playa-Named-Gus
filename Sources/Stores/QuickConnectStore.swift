import Foundation
import JellyfinAPI
import Observation
import OSLog

enum QuickConnectAvailability: Equatable {
    case unknown
    case available
    case unavailable

    static func isEnabled(_ data: Data) throws -> Bool {
        try JSONDecoder().decode(Bool.self, from: data)
    }
}

enum QuickConnectFlowEvent: Equatable {
    case polling(code: String)
    case authenticated(secret: String)
}

enum QuickConnectFlowState: Equatable {
    case idle
    case starting
    case polling(code: String)
    case signingIn(code: String?)
    case signedIn
    case failed(String)
}

@MainActor
@Observable
final class QuickConnectStore {
    typealias AvailabilityLoader = () async throws -> Bool
    typealias EventStreamFactory = () -> AsyncThrowingStream<QuickConnectFlowEvent, Error>
    typealias SignInHandler = (ServerConnection, String) async throws -> Void

    let server: ServerConnection
    private let availabilityLoader: AvailabilityLoader
    private let eventStream: EventStreamFactory
    private let signIn: SignInHandler
    private let logger = Logger(category: .quickConnect)
    private var pollingTask: Task<Void, Never>?

    private(set) var availability: QuickConnectAvailability = .unknown
    private(set) var state: QuickConnectFlowState = .idle

    var isAvailable: Bool {
        availability == .available
    }

    init(server: ServerConnection, appModel: AppModel) {
        self.server = server
        self.availabilityLoader = {
            let client = JellyfinClientFactory.makeClient(url: server.url)
            let response = try await client.send(Paths.getQuickConnectEnabled)
            return try QuickConnectAvailability.isEnabled(response.value)
        }
        self.eventStream = {
            let client = JellyfinClientFactory.makeClient(url: server.url)
            return Self.makeEventStream(from: client)
        }
        self.signIn = { server, secret in
            try await appModel.signIn(to: server, quickConnectSecret: secret)
        }
    }

    init(
        server: ServerConnection,
        availabilityLoader: @escaping AvailabilityLoader,
        eventStream: @escaping EventStreamFactory,
        signIn: @escaping SignInHandler
    ) {
        self.server = server
        self.availabilityLoader = availabilityLoader
        self.eventStream = eventStream
        self.signIn = signIn
    }

    func refreshAvailability() async {
        do {
            availability = try await availabilityLoader() ? .available : .unavailable
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            logger.error("Quick Connect availability failed: \(gusError.localizedDescription, privacy: .public)")
            availability = .unavailable
        }
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.performQuickConnect()
        }
    }

    func cancel() {
        pollingTask?.cancel()
        pollingTask = nil
        state = .idle
    }

    func performQuickConnect() async {
        state = .starting
        var pollingCode: String?

        do {
            for try await event in eventStream() {
                switch event {
                case let .polling(code):
                    pollingCode = code
                    state = .polling(code: code)
                case let .authenticated(secret):
                    state = .signingIn(code: pollingCode)
                    try await signIn(server, secret)
                    state = .signedIn
                    pollingTask = nil
                    return
                }
            }
            pollingTask = nil
            switch state {
            case .starting:
                state = .idle
            case .polling:
                // The server closed the stream without authenticating (code expired);
                // surface that instead of leaving a dead code on screen.
                state = .failed(String(
                    localized: "The Quick Connect code expired. Try again.",
                    comment: "Quick Connect stream ended without authentication"
                ))
            default:
                break
            }
        } catch {
            pollingTask = nil
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else {
                state = .idle
                return
            }
            logger.error("Quick Connect failed: \(gusError.localizedDescription, privacy: .public)")
            state = .failed(gusError.localizedDescription)
        }
    }

    private static func makeEventStream(from client: JellyfinClient) -> AsyncThrowingStream<QuickConnectFlowEvent, Error> {
        AsyncStreamBridge.stream { continuation in
            for try await event in client.quickConnect.connect() {
                switch event {
                case let .polling(code):
                    continuation.yield(.polling(code: code))
                case let .authenticated(secret):
                    continuation.yield(.authenticated(secret: secret))
                }
            }
        }
    }
}
