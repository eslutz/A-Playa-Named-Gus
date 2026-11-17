import JellyfinAPI
import SwiftUI

/// Session status glance (feature 1 of the brief) plus sign-out: active server,
/// signed-in user, and a live connection check.
struct WatchSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionStore.self) private var session

    @State private var connectionState: ConnectionState = .checking
    @State private var rememberPlaybackTracks = false

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
                Toggle("Remember Episode Tracks for This Account", isOn: $rememberPlaybackTracks)
                    .onChange(of: rememberPlaybackTracks) { _, enabled in
                        PlaybackTrackMemory.shared.setEnabled(enabled, scope: session.references.scope)
                    }
            } header: {
                Text("Playback")
            } footer: {
                Text("Saved on this Apple Watch for this Jellyfin account. Choices apply to later episodes in the same series.")
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    Task { await appModel.signOut() }
                }
            }

            Section("About") {
                LabeledContent("Version", value: DeviceIdentity.appVersion)
            }
        }
        .navigationTitle("Settings")
        .task {
            rememberPlaybackTracks = PlaybackTrackMemory.shared.isEnabled(scope: session.references.scope)
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
