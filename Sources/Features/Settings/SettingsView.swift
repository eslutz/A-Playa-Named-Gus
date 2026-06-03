import SwiftUI

/// Account, known servers, sign-out, and version info.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionStore.self) private var session

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("User", value: session.user.name)
                LabeledContent("Server", value: session.server.name)
                LabeledContent("Address", value: session.server.url.absoluteString)
            }

            if appModel.servers.count > 1 {
                Section("Known Servers") {
                    ForEach(appModel.servers) { server in
                        LabeledContent(server.name, value: server.url.host() ?? server.url.absoluteString)
                    }
                }
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    appModel.signOut()
                }
            }

            Section("About") {
                LabeledContent("Version", value: DeviceIdentity.appVersion)
                LabeledContent("Client", value: DeviceIdentity.clientName)
                LabeledContent("Device", value: DeviceIdentity.deviceName)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
