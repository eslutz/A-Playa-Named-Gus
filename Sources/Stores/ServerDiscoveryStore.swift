import Foundation
import JellyfinAPI
import Observation
import OSLog

struct DiscoveredServer: Identifiable, Hashable {
    let id: String
    var name: String
    var url: URL

    init(id: String, name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }

    init(publicServer: JellyfinClient.PublicServer) {
        id = publicServer.id
        name = publicServer.name
        url = publicServer.url
    }
}

enum ServerDiscoveryState: Equatable {
    case idle
    case searching
    case found
    case empty
    case failed(String)
}

@MainActor
@Observable
final class ServerDiscoveryStore {
    typealias DiscoveryStreamFactory = () -> AsyncThrowingStream<DiscoveredServer, Error>

    private let discoveryStream: DiscoveryStreamFactory
    private let logger = Logger(category: .discovery)
    private var discoveryTask: Task<Void, Never>?

    private(set) var state: ServerDiscoveryState = .idle
    private(set) var servers: [DiscoveredServer] = []

    var isSearching: Bool {
        state == .searching
    }

    init(duration: Duration = .seconds(5)) {
        self.discoveryStream = {
            Self.makeDiscoveryStream(duration: duration)
        }
    }

    init(discoveryStream: @escaping DiscoveryStreamFactory) {
        self.discoveryStream = discoveryStream
    }

    func start() {
        guard discoveryTask == nil else { return }
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            await self.findServers()
        }
    }

    func cancel() {
        discoveryTask?.cancel()
        discoveryTask = nil
        state = .idle
    }

    func findServers() async {
        state = .searching
        servers = []

        do {
            for try await server in discoveryStream() {
                appendIfNeeded(server)
            }
            discoveryTask = nil
            state = servers.isEmpty ? .empty : .found
        } catch {
            discoveryTask = nil
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else {
                state = .idle
                return
            }
            logger.error("Server discovery failed: \(gusError.localizedDescription, privacy: .public)")
            state = .failed(gusError.localizedDescription)
        }
    }

    private func appendIfNeeded(_ server: DiscoveredServer) {
        guard !servers.contains(where: { $0.id == server.id || $0.url == server.url }) else { return }
        servers.append(server)
    }

    private static func makeDiscoveryStream(duration: Duration) -> AsyncThrowingStream<DiscoveredServer, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await server in JellyfinClient.discover(duration: duration) {
                        continuation.yield(DiscoveredServer(publicServer: server))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
