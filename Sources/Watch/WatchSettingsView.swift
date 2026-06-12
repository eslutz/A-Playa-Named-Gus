import JellyfinAPI
import SwiftUI

/// Session status glance (feature 1 of the brief) plus sign-out: active server,
/// signed-in user, and a live connection check.
struct WatchSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionStore.self) private var session

    @State private var connectionState: ConnectionState = .checking

    private enum ConnectionState {
        case checking
        case online
        case offline
    }

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Server", value: session.server.name)
                LabeledContent("User", value: session.user.name)
                HStack {
                    Text("Connection")
                    Spacer()
                    switch connectionState {
                    case .checking:
                        ProgressView()
                    case .online:
                        Label("Online", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green) // watchOS has no UIColor.systemGreen; .green is the platform-correct semantic color
                            .labelStyle(.titleAndIcon)
                    case .offline:
                        Label("Offline", systemImage: "wifi.slash")
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
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
            }
        }
        .navigationTitle("Settings")
        .task {
            await checkConnection()
        }
    }

    private func checkConnection() async {
        connectionState = .checking
        do {
            _ = try await session.client.send(Paths.getPublicSystemInfo)
            connectionState = .online
        } catch {
            connectionState = .offline
        }
    }
}
