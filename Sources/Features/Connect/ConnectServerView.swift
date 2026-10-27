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
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
        @State private var showingLocalServers = false
    #endif

    var body: some View {
        Group {
            #if os(iOS)
                if widthClass == .compact {
                    onboarding
                } else {
                    serverForm
                }
            #else
                serverForm
            #endif
        }
        .onDisappear {
            cancelConnect()
            discoveryStore.cancel()
        }
    }

    private var serverForm: some View {
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
    }

    #if os(iOS)
        private var onboarding: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    GusOnboardingHeader()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Let’s connect.").font(.largeTitle.bold())
                        Text("Add your Jellyfin server to bring your library into Gus.")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 20)
                    GusOnboardingField(title: "Server address") {
                        TextField("https://media.example.com", text: $urlText)
                            .urlFieldStyle()
                            .accessibilityLabel("Server Address")
                            .accessibilityIdentifier("ConnectServerView.serverAddress")
                            .onSubmit(connect)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Button {
                            showingLocalServers = true
                            discoveryStore.start()
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.blue)
                                Text("Find a local server").foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 18)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) { Divider() }
                        .overlay(alignment: .bottom) { Divider() }
                        Text("Search for Jellyfin servers on your local network when you’re on the same Wi-Fi.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    connectErrorSection
                    Button(action: connect) {
                        HStack {
                            if isConnecting {
                                ProgressView().tint(.white)
                            }
                            Text("Connect").frame(maxWidth: .infinity)
                        }
                        .frame(minHeight: 26)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
                    .accessibilityIdentifier("ConnectServerView.connectButton")
                    if isConnecting {
                        Button("Cancel", role: .cancel) { cancelConnect() }
                            .accessibilityIdentifier("ConnectServerView.cancelButton")
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .gusIPhoneCanvas()
            .sheet(isPresented: $showingLocalServers) {
                NavigationStack {
                    Form { localServersSection }
                        .navigationTitle("Local Servers")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                GusCloseButton { showingLocalServers = false }
                            }
                        }
                }
            }
        }
    #endif

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
                    #if os(iOS)
                        showingLocalServers = false
                    #endif
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
                        let failure = await appModel.connectToLocalDemoServer()
                        guard generation == connectGeneration, !Task.isCancelled else { return }
                        errorMessage = failure
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
