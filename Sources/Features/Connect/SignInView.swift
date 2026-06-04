import Foundation
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
    @State private var signInStore: SignInStore?

    var body: some View {
        Form {
            publicProfilesSection
            credentialsSection
            quickConnectSection
            signInErrorSection
            signInActionSection
        }
        .formStyle(.grouped)
        .tint(.accentColor)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(server.name)
        .task {
            await loadPublicSignInData()
            await refreshQuickConnectAvailability()
        }
        .onDisappear {
            quickConnectStore?.cancel()
        }
    }

    @ViewBuilder
    private var publicProfilesSection: some View {
        if let signInStore {
            switch signInStore.state {
            case .loaded where !signInStore.publicUsers.isEmpty:
                Section("Public Profiles") {
                    ForEach(signInStore.publicUsers) { profile in
                        Button {
                            username = profile.user.name ?? profile.displayName
                            password = ""
                        } label: {
                            PublicUserProfileRow(
                                profile: profile,
                                imageURL: signInStore.imageBuilder.userImageURL(for: profile.user)
                            )
                        }
                        .buttonStyle(.plain)
                        .visionHoverEffect(cornerRadius: 14)
                    }
                }

            case .loading:
                Section("Public Profiles") {
                    HStack {
                        Text("Loading Profiles")
                        Spacer()
                        ProgressView()
                    }
                }

            default:
                EmptyView()
            }

            if let disclaimer = signInStore.loginDisclaimer {
                Section("Server Notice") {
                    Text(disclaimer)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var credentialsSection: some View {
        Section {
            TextField("Username", text: $username)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .onSubmit(signIn)
        } header: {
            Text("Sign In")
        } footer: {
            Text("Connecting to \(server.url.absoluteString)")
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

    @ViewBuilder
    private var signInErrorSection: some View {
        if let errorMessage {
            Section {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
    }

    private var signInActionSection: some View {
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

    private func loadPublicSignInData() async {
        if signInStore == nil {
            signInStore = SignInStore(server: server)
        }

        await signInStore?.load()
    }
}

private struct PublicUserProfileRow: View {
    let profile: PublicUserProfile
    let imageURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            AsyncPoster(
                url: imageURL,
                contentMode: .fill,
                placeholderSymbol: "person.crop.circle"
            )
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.headline)
                if profile.user.hasPassword == false {
                    Text("No password required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
