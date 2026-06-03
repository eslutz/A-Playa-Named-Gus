import SwiftUI

/// Username/password sign-in against a connected server.
///
/// Pattern reference: Swiftfin's `UserSignInViewModel` (`client.signIn(username:password:)`).
/// On success, `AppModel.currentSession` is set and `RootView` swaps to the signed-in tree.
struct SignInView: View {
    @Environment(AppModel.self) private var appModel
    let server: ServerConnection

    @State private var username = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var quickConnectStore: QuickConnectStore?

    var body: some View {
        Form {
            Section {
                TextField("Username", text: $username)
                    .urlFieldStyle()
                SecureField("Password", text: $password)
                    .onSubmit(signIn)
            } header: {
                Text("Sign In")
            } footer: {
                Text("Connecting to \(server.url.absoluteString)")
            }

            quickConnectSection

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section {
                Button(action: signIn) {
                    HStack {
                        Text("Sign In")
                        Spacer()
                        if isSigningIn { ProgressView() }
                    }
                }
                .disabled(username.isEmpty || isSigningIn)
            }
        }
        .formStyle(.grouped)
        .glassBackground()
        .navigationTitle(server.name)
        .task {
            await refreshQuickConnectAvailability()
        }
        .onDisappear {
            quickConnectStore?.cancel()
        }
    }

    @ViewBuilder
    private var quickConnectSection: some View {
        if let quickConnectStore, quickConnectStore.isAvailable {
            Section("Quick Connect") {
                switch quickConnectStore.state {
                case .idle:
                    Button {
                        quickConnectStore.start()
                    } label: {
                        Label("Use Quick Connect", systemImage: "bolt.horizontal.circle")
                    }

                case .starting:
                    HStack {
                        Text("Starting Quick Connect")
                        Spacer()
                        ProgressView()
                    }

                case let .polling(code):
                    LabeledContent("Code", value: code)
                        .monospacedDigit()
                    Text("Approve this code in Jellyfin on another device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Cancel", role: .cancel) {
                        quickConnectStore.cancel()
                    }

                case let .signingIn(code):
                    if let code {
                        LabeledContent("Code", value: code)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Signing In")
                        Spacer()
                        ProgressView()
                    }

                case .signedIn:
                    Label("Signed In", systemImage: "checkmark.circle")

                case let .failed(message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button {
                        quickConnectStore.start()
                    } label: {
                        Label("Try Quick Connect Again", systemImage: "arrow.clockwise")
                    }
                }
            }
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

    private func refreshQuickConnectAvailability() async {
        if quickConnectStore == nil {
            quickConnectStore = QuickConnectStore(server: server, appModel: appModel)
        }

        await quickConnectStore?.refreshAvailability()
    }
}
