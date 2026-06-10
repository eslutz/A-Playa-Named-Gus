import SwiftUI

/// Account, known servers, sign-out, and version info.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads

    @State private var reauthenticationServer: ServerConnection?
    @State private var switchErrorMessage: String?
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimitRawValue = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnratedContent = false
    @AppStorage(AppearanceSetting.defaultsKey) private var appearanceRawValue = AppearanceSetting.system.rawValue

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

            if DownloadsAvailability.isSupported, session.mediaProvider.capabilities.supportsDownloads {
                DownloadsSettingsSection(
                    byteCount: downloads.totalByteCount(serverID: session.server.id, userID: session.user.id)
                )
            }

            Section {
                Picker("Appearance", selection: $appearanceRawValue) {
                    ForEach(AppearanceSetting.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("System follows your device's light and dark setting.")
            }

            Section {
                Picker("Limit Content Ratings", selection: $contentLimitRawValue) {
                    ForEach(ContentRatingGate.Limit.allCases) { limit in
                        Text(limit.title).tag(limit.rawValue)
                    }
                }
                if contentLimitRawValue != ContentRatingGate.Limit.off.rawValue {
                    Toggle("Hide Unrated Media", isOn: $hideUnratedContent)
                }
            } header: {
                Text("Content Restrictions")
            } footer: {
                Text("Hides movies and shows rated above the limit. Pair with Jellyfin user permissions and Apple Screen Time for enforced parental controls.")
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
        .settingsFormStyle()
        .navigationTitle("Settings")
        .task {
            downloads.load(serverID: session.server.id, userID: session.user.id)
        }
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

private extension View {
    @ViewBuilder
    func settingsFormStyle() -> some View {
        #if os(visionOS)
            formStyle(.automatic)
        #else
            formStyle(.grouped)
        #endif
    }
}

private struct DownloadsSettingsSection: View {
    let byteCount: Int64

    private var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var body: some View {
        Section {
            NavigationLink {
                DownloadsView()
            } label: {
                LabeledContent("Downloaded Media", value: formattedByteCount)
            }
        } header: {
            Text("Downloads")
        } footer: {
            Text("Downloads are available on iOS, iPadOS, macOS, and visionOS. tvOS is excluded because its app storage is system-purgeable.")
        }
    }
}
