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

    var body: some View {
        Form {
            serverAddressSection
            connectErrorSection
            connectActionSection
            localServersSection
        }
        .formStyle(.grouped)
        .tint(.accentColor)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Connect to Jellyfin")
        .onDisappear {
            discoveryStore.cancel()
        }
    }

    private var serverAddressSection: some View {
        Section {
            TextField("http://192.168.1.50:8096", text: $urlText)
                .urlFieldStyle()
                .onSubmit(connect)
        } header: {
            Text("Server Address")
        } footer: {
            Text("Enter your Jellyfin server's address, including the port (default 8096).")
        }
    }

    @ViewBuilder
    private var connectErrorSection: some View {
        if let errorMessage {
            Section {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
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
                    if isConnecting { ProgressView() }
                }
            }
            .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
            .accessibilityIdentifier("ConnectServerView.connectButton")
        }
    }

    private var localServersSection: some View {
        Section("Local Servers") {
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
                ContentUnavailableView(
                    "Find Local Servers",
                    systemImage: "network",
                    description: Text("Use Refresh to search for Jellyfin servers on this network.")
                )
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
        }
    }

    private func connect() {
        guard !isConnecting else { return }
        errorMessage = nil
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                let server = try await appModel.connect(to: urlText)
                onConnected(server)
            } catch {
                guard !GusError(from: error).isCancellation else { return }
                errorMessage = error.localizedDescription
            }
        }
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
