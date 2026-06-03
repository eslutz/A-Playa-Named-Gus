import SwiftUI

/// Account, known servers, sign-out, and version info.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionStore.self) private var session

    @State private var reauthenticationServer: ServerConnection?
    @State private var switchErrorMessage: String?

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("User", value: session.user.name)
                LabeledContent("Server", value: session.server.name)
                LabeledContent("Address", value: session.server.url.absoluteString)
            }

            ForEach(appModel.servers) { server in
                let users = appModel.users(on: server)
                if !users.isEmpty {
                    Section {
                        ForEach(users) { user in
                            storedUserRow(user, server: server)
                        }
                    } header: {
                        Text(server.name)
                    } footer: {
                        Text(server.url.host() ?? server.url.absoluteString)
                    }
                }
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    appModel.signOut()
                }
                .gusKeyboardShortcut("q", modifiers: [.command, .shift])
            }

            Section("About") {
                LabeledContent("Version", value: DeviceIdentity.appVersion)
                LabeledContent("Client", value: DeviceIdentity.clientName)
                LabeledContent("Device", value: DeviceIdentity.deviceName)
            }
        }
        .formStyle(.grouped)
        .glassBackground()
        .navigationTitle("Settings")
        .sheet(item: $reauthenticationServer) { server in
            NavigationStack {
                SignInView(server: server)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                reauthenticationServer = nil
                            }
                        }
                    }
            }
        }
        .alert(
            "Account Switch Failed",
            isPresented: Binding(
                get: { switchErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        switchErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                switchErrorMessage = nil
            }
        } message: {
            Text(switchErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private func storedUserRow(_ user: StoredUser, server: ServerConnection) -> some View {
        let isActiveUser = session.user.id == user.id && session.user.serverID == user.serverID

        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text(user.name)
                    Text(server.url.host() ?? server.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: isActiveUser ? "checkmark.circle.fill" : "person.circle")
            }

            Spacer()

            if isActiveUser {
                Text("Active")
                    .foregroundStyle(.secondary)
            } else if appModel.hasStoredToken(for: user) {
                Button("Switch") {
                    switchToStoredUser(user)
                }
            } else {
                Button("Sign In Again") {
                    reauthenticationServer = server
                }
            }
        }
    }

    private func switchToStoredUser(_ user: StoredUser) {
        do {
            try appModel.switchToStoredUser(user)
        } catch {
            switchErrorMessage = error.localizedDescription
        }
    }
}
