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
    @State private var signInTask: Task<Void, Never>?
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
        @State private var showingSignInOptions = false
    #endif

    var body: some View {
        Group {
            #if os(iOS)
                if widthClass == .compact {
                    onboarding
                } else {
                    signInForm
                }
            #else
                signInForm
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showingSignInOptions) {
            NavigationStack {
                signInOptionsContent
                    .navigationTitle("Sign-in Options")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            GusCloseButton { showingSignInOptions = false }
                        }
                    }
            }
        }
        #endif
        .task { await loadPublicSignInData() }
        .task { await refreshQuickConnectAvailability() }
        .onDisappear {
            signInTask?.cancel()
            quickConnectStore?.cancel()
        }
    }

    private var signInForm: some View {
        Form {
            #if os(iOS)
                if DeviceIdentity.usesIPadPresentation {
                    credentialsSection
                    Section {
                        Button("More sign-in options") { showingSignInOptions = true }
                            .disabled(quickConnectStore == nil || signInStore == nil)
                    }
                } else {
                    publicProfilesSection
                    credentialsSection
                    quickConnectSection
                }
            #else
                publicProfilesSection
                credentialsSection
                quickConnectSection
            #endif
            signInErrorSection
            signInActionSection
        }
        .formStyle(.grouped)
        .tint(.accentColor)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(server.name)
    }

    #if os(iOS)
        private var onboarding: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GusOnboardingHeader()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sign in.").font(.largeTitle.bold())
                        Text(server.name).font(.title3).foregroundStyle(.secondary)
                        Text(server.url.host() ?? server.url.absoluteString)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    GusOnboardingField(title: "Username") {
                        TextField("Username", text: $username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .textContentType(.username)
                    }
                    GusOnboardingField(title: "Password") {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .onSubmit(signIn)
                    }
                    signInErrorSection
                    if let disclaimer = signInStore?.loginDisclaimer {
                        Text(disclaimer).font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Use your Jellyfin account for this server.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                    Button(action: signIn) {
                        HStack {
                            if isSigningIn {
                                ProgressView().tint(.white)
                            }
                            Text("Sign In").frame(maxWidth: .infinity)
                        }
                        .frame(minHeight: 26)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(username.isEmpty || isSigningIn)
                    if isSigningIn {
                        Button("Cancel", role: .cancel) { signInTask?.cancel() }
                    }
                    Button("More sign-in options") { showingSignInOptions = true }
                        .disabled(quickConnectStore == nil || signInStore == nil)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .gusIPhoneCanvas()
        }

        @ViewBuilder private var signInOptionsContent: some View {
            if let quickConnectStore, case let .polling(code) = quickConnectStore.state {
                VStack(spacing: 28) {
                    Image(systemName: "bolt.horizontal.circle").font(.largeTitle).foregroundStyle(.blue)
                    Text("Quick Connect").font(.title.bold())
                    Text(code).font(.largeTitle.monospaced().bold())
                        .textSelection(.enabled)
                        .accessibilityLabel("Authorization code")
                    Text("Approve this code in Jellyfin on another device.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Cancel", role: .cancel) { quickConnectStore.cancel() }
                        .buttonStyle(.bordered).controlSize(.large)
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if signInStore?.state == .loaded,
                      signInStore?.publicUsers.isEmpty == true,
                      signInStore?.loginDisclaimer == nil,
                      quickConnectStore?.availability == .unavailable
            {
                ContentUnavailableView("No Additional Sign-in Options", systemImage: "person.crop.circle", description: Text("Use your Jellyfin username and password to sign in."))
            } else {
                Form {
                    publicProfilesSection
                    quickConnectSection
                    if let signInStore, case let .failed(message) = signInStore.state {
                        Section {
                            Label(message, systemImage: "exclamationmark.triangle")
                            Button("Try Again") { Task { await loadPublicSignInData() } }
                        }
                    }
                }
            }
        }
    #endif

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
                            #if os(iOS)
                                showingSignInOptions = false
                            #endif
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
                .textContentType(.username)
            SecureField("Password", text: $password)
                .textContentType(.password)
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
                    #if os(macOS)
                        .foregroundStyle(Color(NSColor.systemRed))
                    #else
                        .foregroundStyle(Color(UIColor.systemRed))
                    #endif
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
                #if os(macOS)
                    .foregroundStyle(Color(NSColor.systemRed))
                #else
                    .foregroundStyle(Color(UIColor.systemRed))
                #endif
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
                    if isSigningIn {
                        ProgressView()
                    }
                }
            }
            .disabled(username.isEmpty || isSigningIn)
        }
    }

    private func signIn() {
        guard !isSigningIn else { return }
        errorMessage = nil
        isSigningIn = true
        signInTask?.cancel()
        signInTask = Task {
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
