import SwiftUI

struct SeerrSettingsView: View {
    @Environment(SeerrStore.self) private var store
    @Environment(SessionStore.self) private var session
    @Environment(RootNavigationState.self) private var root
    @Environment(NavigationPreferencesStore.self) private var preferences
    @State private var showingSetup = false
    @State private var confirmingDisconnect = false

    private var visible: Bool {
        preferences.resolvedSections(libraries: root.home?.libraries ?? [], serverID: session.server.id, userID: session.user.id)
            .first { $0.id == NavigationSectionPreference.discoverID }?.isVisible ?? false
    }

    var body: some View {
        Form {
            Section("Connection") {
                if let url = store.serverURL {
                    LabeledContent("Server", value: url.host() ?? "Seerr")
                    if let user = store.user {
                        LabeledContent("Account", value: user.name)
                    }
                    if store.isConnected {
                        Text("Connected").foregroundStyle(.secondary)
                    } else {
                        Button("Sign In Again") { showingSetup = true }
                    }
                    Link("Open Seerr", destination: url)
                    Button("Disconnect This Device", role: .destructive) { confirmingDisconnect = true }
                } else {
                    Button("Connect to Seerr") { showingSetup = true }
                }
            }
            Section {
                Toggle("Show Discover", isOn: Binding(get: { visible }, set: { value in
                    preferences.setVisibility(
                        value,
                        forSectionID: NavigationSectionPreference.discoverID,
                        libraries: root.home?.libraries ?? [],
                        serverID: session.server.id,
                        userID: session.user.id
                    )
                    if !value, root.selectedSectionID == NavigationSectionPreference.discoverID {
                        root.selectedSectionID = NavigationSectionPreference.homeID
                    }
                }))
            } footer: { Text("Hiding Discover preserves your connection. You can also restore or reorder it in Navigation settings.") }
            if store.isConnected {
                Section("Seerr Preferences") {
                    NavigationLink("Catalog and Notifications") { SeerrPreferencesView() }
                    if store.user?.canViewIssues == true || store.user?.canCreateIssues == true {
                        NavigationLink("Issues") { SeerrIssuesView() }
                    }
                    if store.user?.canViewBlocklist == true {
                        NavigationLink("Blocklist") { SeerrBlocklistView() }
                    }
                }
            }
            Section {
                Text("Seerr controls requests, quotas, approval rules and media availability. Playback uses titles accessible to your signed-in Jellyfin account.")
                Text("Session cookies are stored in this device’s Keychain. Passwords are never saved or synced through iCloud.")
                Image("TMDBLogo").resizable().scaledToFit().frame(width: 140).accessibilityLabel("The Movie Database")
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                Link("The Movie Database", destination: URL(string: "https://www.themoviedb.org")!)
            }
        }
        .seerrFormStyle()
        .navigationTitle("Discover Settings")
        .gusTVTask(isPresented: $showingSetup) { SeerrConnectView() }
        .confirmationDialog("Disconnect Seerr on this device?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { store.disconnect() }
        } message: { Text("Your Seerr requests remain on the server. This removes the saved connection for this Gus account on this device.") }
    }
}
