import SwiftUI

/// Standalone watch sign-in: server address → Quick Connect (preferred on watch) or
/// username/password. The iPhone hand-off (`WatchCredentialReceiver`) signs in silently
/// when the companion app is in use; this flow never requires it.
struct WatchConnectView: View {
    @Environment(AppModel.self) private var appModel

    @State private var urlText = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var server: ServerConnection?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Connect to Jellyfin")
                    .font(.headline)

                TextField("Server Address", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red) // watchOS has no UIColor.systemRed; .red is the platform-correct semantic color
                }

                Button {
                    connect()
                } label: {
                    if isConnecting {
                        ProgressView()
                    } else {
                        Text("Connect")
                    }
                }
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)

                Text("Or open A Playa Named Gus on your iPhone — the watch signs in automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .navigationDestination(item: $server) { server in
            WatchSignInView(server: server)
        }
    }

    private func connect() {
        guard !isConnecting else { return }
        errorMessage = nil
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                server = try await appModel.connect(to: urlText)
            } catch {
                guard !GusError(from: error).isCancellation else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Quick Connect first (display a code, approve elsewhere), credentials as fallback.
private struct WatchSignInView: View {
    @Environment(AppModel.self) private var appModel
    let server: ServerConnection

    @State private var quickConnect: QuickConnectStore?
    @State private var username = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let quickConnect, quickConnect.isAvailable {
                Section("Quick Connect") {
                    switch quickConnect.state {
                    case .idle:
                        Button("Get Code") {
                            quickConnect.start()
                        }
                    case .starting:
                        ProgressView()
                    case let .polling(code):
                        Text(code)
                            .font(.title2.monospacedDigit())
                            .frame(maxWidth: .infinity)
                        Text("Approve this code in Jellyfin on another device.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    case .signingIn:
                        ProgressView()
                    case .signedIn:
                        Label("Signed In", systemImage: "checkmark.circle")
                    case let .failed(message):
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red) // watchOS has no UIColor.systemRed; .red is the platform-correct semantic color
                        Button("Try Again") {
                            quickConnect.start()
                        }
                    }
                }
            }

            Section("Sign In") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red) // watchOS has no UIColor.systemRed; .red is the platform-correct semantic color
                }
                Button {
                    signIn()
                } label: {
                    if isSigningIn {
                        ProgressView()
                    } else {
                        Text("Sign In")
                    }
                }
                .disabled(username.isEmpty || isSigningIn)
            }
        }
        .navigationTitle(server.name)
        .task {
            if quickConnect == nil {
                quickConnect = QuickConnectStore(server: server, appModel: appModel)
            }
            await quickConnect?.refreshAvailability()
        }
        .onDisappear {
            quickConnect?.cancel()
        }
    }

    private func signIn() {
        guard !isSigningIn else { return }
        errorMessage = nil
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await appModel.signIn(to: server, username: username, password: password)
            } catch {
                guard !GusError(from: error).isCancellation else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
