import SwiftUI

/// Manual server-address entry → `Paths.getPublicSystemInfo`.
///
/// Pattern reference: Swiftfin's `ConnectToServerViewModel`. Manual entry stays primary;
/// local-network discovery only runs when the user asks for it.
struct ConnectServerView: View {
    @Environment(AppModel.self) private var appModel
    let onConnected: (ServerConnection) -> Void

    @State private var urlText = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var discoveryStore = ServerDiscoveryStore()

    var body: some View {
        Form {
            Section {
                TextField("http://192.168.1.50:8096", text: $urlText)
                    .urlFieldStyle()
                    .onSubmit(connect)
            } header: {
                Text("Server Address")
            } footer: {
                Text("Enter your Jellyfin server's address, including the port (default 8096).")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section {
                Button(action: connect) {
                    HStack {
                        Text("Connect")
                        Spacer()
                        if isConnecting { ProgressView() }
                    }
                }
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
            }

            Section("Local Servers") {
                Button {
                    discoveryStore.start()
                } label: {
                    HStack {
                        Label("Find Local Servers", systemImage: "network")
                        Spacer()
                        if discoveryStore.isSearching {
                            ProgressView()
                        }
                    }
                }
                .disabled(discoveryStore.isSearching)

                ForEach(discoveryStore.servers) { server in
                    Button {
                        urlText = server.url.absoluteString
                    } label: {
                        VStack(alignment: .leading) {
                            Text(server.name)
                            Text(server.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                switch discoveryStore.state {
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
        .formStyle(.grouped)
        .navigationTitle("Connect to Jellyfin")
        .onDisappear {
            discoveryStore.cancel()
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
