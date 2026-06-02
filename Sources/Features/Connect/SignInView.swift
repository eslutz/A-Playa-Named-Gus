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
        .navigationTitle(server.name)
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
                errorMessage = error.localizedDescription
            }
        }
    }
}
