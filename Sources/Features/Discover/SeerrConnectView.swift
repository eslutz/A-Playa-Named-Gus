import SwiftUI

/// Native setup separates server validation from transient sign-in credentials.
struct SeerrConnectView: View {
    @Environment(SeerrStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var candidate: SeerrClient?
    @State private var info: SeerrServerInfo?
    @State private var validation: Task<Void, Never>?
    @State private var isValidating = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Seerr Server URL", text: $address)
                        .urlFieldStyle()
                        .accessibilityIdentifier("Seerr.serverURL")
                        .disabled(isValidating)
                        .onSubmit { startValidation() }
                } header: { Text("Connect to Seerr") } footer: {
                    Text("Enter the address of your Seerr 3 server. Your connection is saved for this Gus account on this device.")
                }
                if let message {
                    Section { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("Seerr.connectionError") }
                }
                Section {
                    Button { startValidation() } label: {
                        HStack {
                            Text(isValidating ? "Checking Server…" : "Continue")
                            if isValidating {
                                ProgressView()
                            }
                        }
                    }
                    .gusDefaultActionShortcut()
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
                    .accessibilityIdentifier("Seerr.continue")
                }
            }
            .seerrFormStyle()
            .navigationTitle("Connect to Seerr")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .navigationDestination(isPresented: Binding(get: { candidate != nil && info != nil }, set: {
                if !$0 {
                    candidate = nil; info = nil
                }
            })) {
                if let candidate, let info {
                    SeerrSignInView(client: candidate, info: info) { dismiss() }
                }
            }
            .onDisappear { validation?.cancel() }
            .onAppear {
                if address.isEmpty {
                    address = store.serverURL?.absoluteString ?? ""
                }
            }
        }
    }

    private func startValidation() {
        validation?.cancel(); validation = Task { await validate() }
    }

    private func validate() async {
        guard !isValidating else { return }
        isValidating = true
        message = nil
        defer { isValidating = false }
        do {
            let url = try SeerrClient.normalizeURL(address)
            let client = try SeerrClient(baseURL: url)
            let value = try await client.validateServer()
            guard !Task.isCancelled else { return }
            candidate = client
            info = value
        } catch {
            guard !Task.isCancelled else { return }
            message = error.localizedDescription
        }
    }
}

private struct SeerrSignInView: View {
    @Environment(SeerrStore.self) private var store
    let client: SeerrClient
    let info: SeerrServerInfo
    let completed: () -> Void
    @State private var method = "local"
    @State private var username = ""
    @State private var password = ""
    @State private var operation: Task<Void, Never>?
    @State private var isSigningIn = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Server", value: info.settings.applicationTitle ?? "Seerr")
                LabeledContent("Version", value: info.status.version)
                Picker("Sign-In Method", selection: $method) {
                    if info.settings.supportsLocalLogin {
                        Text("Seerr Account").tag("local")
                    }
                    if info.settings.supportsJellyfinLogin {
                        Text("Jellyfin Account").tag("jellyfin")
                    }
                }
                .disabled(isSigningIn)
                .onChange(of: method) { _, _ in password = ""; message = nil }
            }
            if info.settings.supportsLocalLogin || info.settings.supportsJellyfinLogin {
                Section {
                    TextField(method == "local" ? "Email" : "Username", text: $username)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .accessibilityIdentifier("Seerr.username")
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("Seerr.password")
                        .onSubmit { startSignIn() }
                } footer: { Text("Your password is used only to sign in. Seerr session cookies are kept in this device’s Keychain and never synced through iCloud.") }
                    .disabled(isSigningIn)
                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
                Section {
                    Button { startSignIn() } label: {
                        HStack {
                            Text(isSigningIn ? "Signing In…" : "Sign In"); if isSigningIn {
                                ProgressView()
                            }
                        }
                    }
                    .gusDefaultActionShortcut()
                    .disabled(isSigningIn || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                    .accessibilityIdentifier("Seerr.signIn")
                }
            } else {
                Section { Text("This server does not enable Seerr or Jellyfin account sign-in. Enable a supported method in Seerr settings to connect Gus.") }
            }
        }
        .seerrFormStyle()
        .navigationTitle("Sign In to Seerr")
        .onAppear { method = info.settings.supportsLocalLogin ? "local" : "jellyfin" }
        .onDisappear { operation?.cancel(); password = "" }
    }

    private func startSignIn() {
        operation?.cancel(); operation = Task { await signIn() }
    }

    private func signIn() async {
        guard !isSigningIn, !password.isEmpty else { return }
        let expected = store.revision
        isSigningIn = true
        message = nil
        defer { isSigningIn = false; password = "" }
        do {
            let account = try await(method == "local"
                ? client.loginLocal(email: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                : client.loginJellyfin(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password))
            guard !Task.isCancelled, expected == store.revision else { return }
            try await store.connect(client: client, user: account, expectedRevision: expected)
            completed()
        } catch {
            guard !Task.isCancelled else { return }
            message = error.localizedDescription
        }
    }
}
