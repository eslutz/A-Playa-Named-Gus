import SwiftUI

/// Manual server-address entry → `Paths.getPublicSystemInfo`.
///
/// Pattern reference: Swiftfin's `ConnectToServerViewModel`. Manual entry stays primary,
/// with local-network discovery available after explicit user action.
struct ConnectServerView: View {
    @Environment(AppModel.self) private var appModel
    let onConnected: (ServerConnection) -> Void

    @State private var urlText = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var discoveryStore = ServerDiscoveryStore()
    @State private var connectTask: Task<Void, Never>?
    @State private var connectGeneration = 0

    var body: some View {
        Form {
            Section { Text("Connect to Jellyfin").font(.headline).fixedSize(horizontal: false, vertical: true) }
            serverAddressSection
            connectErrorSection
            connectActionSection
            localServersSection
            #if DEBUG
                demoServerSection
            #endif
        }
        .formStyle(.grouped)
        .tint(.accentColor)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Connect")
        .onDisappear {
            cancelConnect()
            discoveryStore.cancel()
        }
    }

    private var serverAddressSection: some View {
        Section {
            TextField("http://192.168.1.50:8096", text: $urlText)
                .accessibilityIdentifier("ConnectServerView.serverAddress")
                .accessibilityLabel("Server Address")
                .urlFieldStyle()
            #if os(iOS)
                .frame(minHeight: 44)
            #endif
                .onSubmit(connect)
        } header: {
            Text("Server Address")
                .foregroundStyle(Color.primary)
        } footer: {
            Text("Enter your Jellyfin server's address, including the port (default 8096).")
                .foregroundStyle(Color.primary)
        }
    }

    @ViewBuilder
    private var connectErrorSection: some View {
        if let errorMessage {
            Section {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                #if os(macOS)
                    .foregroundStyle(Color(NSColor.systemRed))
                #else
                    .foregroundStyle(Color(UIColor.systemRed))
                #endif
                    .font(.callout)
            }
        }
    }

    private var connectActionSection: some View {
        Section {
            Button(action: connect) {
                HStack {
                    Text("Connect")
                    Spacer()
                    if isConnecting {
                        ProgressView()
                    }
                }
            }
            .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
            .accessibilityIdentifier("ConnectServerView.connectButton")
            if isConnecting {
                Button("Cancel", role: .cancel) { cancelConnect() }
                    .accessibilityIdentifier("ConnectServerView.cancelButton")
            }
        }
    }

    private var localServersSection: some View {
        Section {
            HStack {
                Label(discoveryStore.isSearching ? "Searching for Local Servers" : "Local Server Discovery", systemImage: "network")
                Spacer()
                if discoveryStore.isSearching {
                    ProgressView()
                } else {
                    Button {
                        discoveryStore.start()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.borderless)
                }
            }

            ForEach(discoveryStore.servers) { server in
                Button {
                    urlText = server.url.absoluteString
                } label: {
                    LocalServerRow(server: server)
                }
                .buttonStyle(.plain)
                .visionHoverEffect(cornerRadius: 14)
            }

            switch discoveryStore.state {
            case .idle:
                ContentUnavailableView {
                    Label("Find Local Servers", systemImage: "network")
                } description: {
                    Text("Use Refresh to search for Jellyfin servers on this network.")
                        .foregroundStyle(Color.primary)
                }
            case .empty:
                ContentUnavailableView(
                    "No Servers Found",
                    systemImage: "network.slash",
                    description: Text("Check that your Jellyfin server and this device are on the same network.")
                )
            case let .failed(message):
                ContentUnavailableView(
                    "Discovery Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            default:
                EmptyView()
            }
        } header: {
            Text("Local Servers")
                .foregroundStyle(Color.primary)
        }
    }

    #if DEBUG
        /// Development-only shortcut to the local demo Jellyfin container
        /// (`Scripts/demo-server.sh start`); signs straight in to the demo account.
        private var demoServerSection: some View {
            Section {
                Button {
                    guard !isConnecting else { return }
                    errorMessage = nil
                    isConnecting = true
                    connectGeneration += 1
                    let generation = connectGeneration
                    connectTask = Task {
                        defer {
                            if generation == connectGeneration {
                                isConnecting = false
                            }
                        }
                        await appModel.connectToLocalDemoServer()
                    }
                } label: {
                    Label("Use Local Demo Server", systemImage: "shippingbox")
                }
                .disabled(isConnecting)
            } footer: {
                Text("Debug builds only. Start it with Scripts/demo-server.sh.")
            }
        }
    #endif

    private func connect() {
        guard !isConnecting else { return }
        errorMessage = nil
        isConnecting = true
        connectTask?.cancel()
        connectGeneration += 1
        let generation = connectGeneration
        let address = urlText
        connectTask = Task {
            defer {
                if generation == connectGeneration {
                    isConnecting = false
                }
            }
            do {
                let server = try await appModel.connect(to: address)
                try Task.checkCancellation()
                guard generation == connectGeneration else { return }
                onConnected(server)
            } catch {
                guard generation == connectGeneration, !Task.isCancelled, !GusError(from: error).isCancellation else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelConnect() {
        connectGeneration += 1
        connectTask?.cancel()
        connectTask = nil
        isConnecting = false
        errorMessage = nil
    }
}

private struct LocalServerRow: View {
    let server: DiscoveredServer

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .foregroundStyle(Color.accentColor)
                .imageScale(.large)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.headline)
                Text(server.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
