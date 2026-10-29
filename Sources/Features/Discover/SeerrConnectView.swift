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
            SeerrSetupLayout {
                VStack(alignment: .gusSeerrSetupHeading, spacing: 12) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
                    Text("Discover your next favorite").font(.title2.bold())
                    Text("Connect your Seerr server to discover movies and shows, request titles, and follow their availability.").foregroundStyle(.secondary)
                }
                .gusSeerrSetupHeading()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Seerr Server URL").font(.subheadline.weight(.medium))
                    TextField("https://seerr.example.com", text: $address)
                        .urlFieldStyle().seerrSetupFieldStyle()
                        .accessibilityLabel("Seerr Server URL")
                        .accessibilityIdentifier("Seerr.serverURL")
                        .disabled(isValidating)
                        .onSubmit { startValidation() }
                    Text("Your connection is saved for this Gus account on this device.").font(.footnote).foregroundStyle(.secondary)
                }
                if let message {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout).accessibilityIdentifier("Seerr.connectionError")
                }
                Button { startValidation() } label: {
                    HStack {
                        Text(isValidating ? "Checking Server…" : "Continue")
                        if isValidating {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity).gusSeerrActionLabelSizing()
                    .gusProminentActionForeground()
                }
                .gusProminentGlassButtonStyle().gusProminentActionTint().controlSize(.large)
                .gusDefaultActionShortcut()
                .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
                .accessibilityIdentifier("Seerr.continue")
            }
            .navigationTitle("Connect to Seerr")
            .gusSeerrSetupTitle()
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
        SeerrSetupLayout {
            VStack(alignment: .leading, spacing: 6) {
                Text(info.settings.applicationTitle ?? "Seerr").font(.title2.bold())
                Text(client.baseURL.host() ?? "Seerr").font(.subheadline).foregroundStyle(.secondary)
                Text("Sign in to request titles and track your requests.").foregroundStyle(.secondary)
            }
            if info.settings.supportsLocalLogin || info.settings.supportsJellyfinLogin {
                if info.settings.supportsLocalLogin && info.settings.supportsJellyfinLogin {
                    Picker("Sign-In Method", selection: $method) {
                        Text("Seerr Account").tag("local")
                        Text("Jellyfin Account").tag("jellyfin")
                    }
                    .pickerStyle(.segmented)
                    .disabled(isSigningIn)
                    .onChange(of: method) { _, _ in password = ""; message = nil }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(method == "local" ? "Email" : "Username").font(.subheadline.weight(.medium))
                    TextField(method == "local" ? "Email" : "Username", text: $username)
                        .autocorrectionDisabled().gusAccountNameInput()
                        .textContentType(.username).seerrSetupFieldStyle()
                        .accessibilityIdentifier("Seerr.username")
                    Text("Password").font(.subheadline.weight(.medium)).padding(.top, 8)
                    SecureField("Password", text: $password)
                        .textContentType(.password).seerrSetupFieldStyle()
                        .accessibilityIdentifier("Seerr.password")
                        .onSubmit { startSignIn() }
                }
                .disabled(isSigningIn)
                if let message {
                    Label(message, systemImage: "exclamationmark.triangle").font(.callout)
                }
                Button { startSignIn() } label: {
                    HStack {
                        Text(isSigningIn ? "Signing In…" : "Sign In")
                        if isSigningIn {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity).gusSeerrActionLabelSizing()
                    .gusProminentActionForeground()
                }
                .gusProminentGlassButtonStyle().gusProminentActionTint().controlSize(.large)
                .gusDefaultActionShortcut()
                .disabled(isSigningIn || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                .accessibilityIdentifier("Seerr.signIn")
                Text("Your password is used only to sign in. Session cookies stay in this device’s Keychain.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Label("This server does not enable Seerr or Jellyfin account sign-in.", systemImage: "lock")
                Text("Enable a supported method in Seerr settings to connect Gus.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sign In to Seerr")
        .gusSeerrSetupTitle()
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
            let attempt = try SeerrClient(baseURL: client.baseURL)
            let account = try await(method == "local"
                ? attempt.loginLocal(email: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                : attempt.loginJellyfin(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password))
            guard !Task.isCancelled, expected == store.revision else { return }
            try await store.connect(client: attempt, user: account, expectedRevision: expected)
            completed()
        } catch {
            guard !Task.isCancelled else { return }
            message = error as? SeerrClientError == .unauthorized
                ? String(localized: "Seerr rejected the account name or password. Check your credentials and try again.")
                : error.localizedDescription
        }
    }
}
