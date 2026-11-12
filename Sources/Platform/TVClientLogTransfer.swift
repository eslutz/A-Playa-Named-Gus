import Foundation
import Observation
import SwiftUI

#if os(iOS) || os(tvOS)
    import Network
#endif
#if os(tvOS)
    import DeviceDiscoveryUI
#endif

/// A single explicit transfer over Apple's encrypted, app-scoped application service.
/// No Bonjour advertisement, general-purpose socket, or automatic upload is used.
@MainActor @Observable
final class TVClientLogTransfer {
    static let shared = TVClientLogTransfer()
    static let service = "Gus-Client-Logs"
    static let maximumBytes = 128 * 1024
    private(set) var status = ""
    private(set) var receivedURL: URL?
    private(set) var receivedAt: Date?
    private(set) var isTransferring = false

    private init() {
        #if os(iOS)
            let url = AppStorageLocation.appDirectory().appendingPathComponent("Gus-Apple-TV-logs.json")
            if let data = try? Data(contentsOf: url), (try? TVLogPayload.decode(data)) != nil {
                receivedURL = url
                receivedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            }
        #endif
    }

    #if os(iOS) || os(tvOS)
        private var listener: NWListener?
        private var connection: NWConnection?
        private var timeout: Task<Void, Never>?
        private var generation = UUID()
        private var beganIO = false

        func startReceiver() {
            #if os(iOS)
                guard listener == nil else { return }
                status = ""
                do {
                    let listener = try NWListener(applicationService: Self.service)
                    listener.newConnectionHandler = { connection in
                        Task { @MainActor in self.accept(connection) }
                    }
                    listener.stateUpdateHandler = { state in
                        if case .failed = state {
                            Task { @MainActor in
                                self.listener?.cancel()
                                self.listener = nil
                                self.status = String(localized: "Log receiver unavailable. Tap Retry Receiver.")
                            }
                        }
                    }
                    self.listener = listener
                    listener.start(queue: .main)
                } catch {
                    status = String(localized: "Log receiver unavailable. Tap Retry Receiver.")
                }
            #endif
        }

        private func begin(_ connection: NWConnection) -> UUID {
            cancel()
            let id = UUID()
            generation = id
            beganIO = false
            self.connection = connection
            isTransferring = true
            status = String(localized: "Transferring logs…")
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self, generation == id else { return }
                finish(String(localized: "Log transfer timed out. Try again."))
            }
            return id
        }

        private func accept(_ connection: NWConnection) {
            guard !isTransferring else { connection.cancel(); return }
            let id = begin(connection)
            connection.stateUpdateHandler = { state in
                Task { @MainActor in
                    guard self.generation == id else { return }
                    switch state {
                    case .ready:
                        guard !self.beganIO else { return }
                        self.beganIO = true
                        self.receive(connection, id: id, accumulated: Data())
                    case .failed: self.finish(String(localized: "Log transfer failed. Try again."))
                    default: break
                    }
                }
            }
            connection.start(queue: .main)
        }

        private func receive(_ connection: NWConnection, id: UUID, accumulated: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maximumBytes + 1 - accumulated.count) { data, _, complete, error in
                Task { @MainActor in
                    guard self.generation == id else { return }
                    var buffer = accumulated
                    if let data {
                        buffer.append(data)
                    }
                    guard buffer.count <= Self.maximumBytes, error == nil else {
                        self.finish(String(localized: "Log transfer was rejected or interrupted.")); return
                    }
                    if complete {
                        do {
                            let bundle = try TVLogPayload.decode(buffer)
                            let url = try bundle.save()
                            self.receivedURL = url
                            self.receivedAt = .now
                            connection.send(content: Data([1]), completion: .contentProcessed { error in
                                Task { @MainActor in
                                    guard self.generation == id else { return }
                                    self.finish(error == nil ? String(localized: "Apple TV logs received. Open Developer → Client Logs to share.") : String(localized: "Logs saved, but the sender could not be notified."))
                                }
                            })
                        } catch { self.finish(String(localized: "Invalid log bundle rejected.")) }
                    } else {
                        self.receive(connection, id: id, accumulated: buffer)
                    }
                }
            }
        }

        func send(to endpoint: NWEndpoint) {
            do {
                let data = try TVLogPayload.snapshot().encoded()
                guard data.count <= Self.maximumBytes else { status = String(localized: "Log bundle is too large."); return }
                let connection = NWConnection(to: endpoint, using: .applicationService)
                let id = begin(connection)
                connection.stateUpdateHandler = { state in
                    Task { @MainActor in
                        guard self.generation == id else { return }
                        switch state {
                        case .ready:
                            guard !self.beganIO else { return }
                            self.beganIO = true
                            connection.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { error in
                                Task { @MainActor in
                                    guard self.generation == id else { return }
                                    guard error == nil else { self.finish(String(localized: "Log transfer failed. Try again.")); return }
                                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { ack, _, _, error in
                                        Task { @MainActor in
                                            guard self.generation == id else { return }
                                            self.finish(ack == Data([1]) && error == nil ? String(localized: "Logs received on your phone. Open Gus → Developer → Client Logs to share.") : String(localized: "Receipt was not confirmed. Check the phone before retrying."))
                                        }
                                    }
                                }
                            })
                        case .failed: self.finish(String(localized: "Log transfer failed. Try again."))
                        default: break
                        }
                    }
                }
                connection.start(queue: .main)
            } catch { status = String(localized: "Logs could not be prepared. Try again.") }
        }

        func cancel() {
            finish("")
        }

        private func finish(_ message: String) {
            generation = UUID()
            timeout?.cancel(); timeout = nil
            connection?.cancel(); connection = nil
            isTransferring = false
            status = message
        }
    #else
        func startReceiver() {}
    #endif
}

struct TVClientLogTransferSection: View {
    @State private var transfer = TVClientLogTransfer.shared
    var body: some View {
        #if os(tvOS)
            Section("Send to iPhone") {
                DevicePicker(.applicationService(name: TVClientLogTransfer.service), onSelect: { transfer.send(to: $0) }) {
                    Label("Send Logs to iPhone", systemImage: "iphone")
                } fallback: {
                    Text("Log transfer requires a supported Apple TV 4K and a nearby iPhone running Gus.")
                }
                .disabled(transfer.isTransferring)
                if transfer.isTransferring {
                    Button("Cancel Transfer") { transfer.cancel() }
                }
                Text(transfer.status)
                Text("Sends the latest 200 sanitized Apple TV events. Apple TV has no MetricKit performance reports.")
                Text("Select your iPhone and approve the system connection prompt. Gus must be installed on both devices with the appropriate iCloud or Family Sharing relationship.")
            }
        #elseif os(iOS)
            Section("Apple TV Logs") {
                Button("Retry Receiver") { transfer.startReceiver() }
                Text(transfer.status.isEmpty ? "Select this phone from Gus’s Client Logs screen on Apple TV, then approve the system connection prompt." : transfer.status)
                if let receivedAt = transfer.receivedAt, let url = transfer.receivedURL {
                    Text("Received \(receivedAt.formatted(date: .abbreviated, time: .standard))")
                    ShareLink("Share Apple TV Logs", item: url)
                }
                if transfer.isTransferring {
                    Button("Cancel Transfer") { transfer.cancel() }
                }
            }
        #endif
    }
}

struct WatchClientLogTransferSection: View {
    @State private var latest = WatchDiagnosticSnapshotStore.shared.latest()
    @State private var status = ""
    var body: some View {
        #if os(iOS)
            Section("Watch Logs") {
                Button("Request Watch Logs") {
                    status = WatchSessionRelay.shared.requestDiagnostics()
                        ? String(localized: "Requested. Delivery may wait until your Watch reconnects. Refresh to check for arrival.")
                        : String(localized: "A paired Watch running Gus is required.")
                }
                Button("Refresh Watch Logs") { latest = WatchDiagnosticSnapshotStore.shared.latest() }
                if let latest {
                    Text("Captured \(latest.snapshot.capturedAt.formatted(date: .abbreviated, time: .standard))")
                    Text("Received \(latest.receivedAt.formatted(date: .abbreviated, time: .standard))")
                    Text("Prepare a new log export to include this snapshot.")
                } else {
                    Text("No Watch snapshot received yet.")
                }
                if !status.isEmpty {
                    Text(status)
                }
            }
        #endif
    }
}
