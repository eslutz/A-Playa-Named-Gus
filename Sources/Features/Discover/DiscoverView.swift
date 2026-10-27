import SwiftUI

/// Discovery keeps Seerr catalog navigation separate from Jellyfin library search.
struct DiscoverView: View {
    @Environment(SeerrStore.self) private var store
    @Environment(SessionStore.self) private var session
    @Environment(RootNavigationState.self) private var root
    @Environment(NavigationPreferencesStore.self) private var preferences
    @State private var showingSetup = false

    var body: some View {
        Group {
            if store.isConnected {
                DiscoverBrowseView(store: store).id(store.revision)
            } else if store.state == .restoring {
                ProgressView("Connecting to Seerr…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label(store.state == .expired ? "Sign In to Seerr Again" : "Discover with Seerr", systemImage: "sparkles")
                } description: {
                    Text(store.errorMessage ?? String(localized: "Browse movies and shows, request missing titles, and track your requests."))
                } actions: {
                    Button(store.serverURL == nil ? "Connect to Seerr" : "Sign In to Seerr") { showingSetup = true }
                        .gusProminentGlassButtonStyle().gusProminentActionTint()
                        .controlSize(.large)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("Seerr.connect")
                    if store.state == .offline {
                        Button("Retry Connection") { Task { await store.retryRestore() } }
                    }
                    Button("Hide Menu Item") { hide() }
                }
            }
        }
        .navigationTitle("Discover")
        .toolbar {
            ToolbarItem {
                Menu("Discover", systemImage: "ellipsis") {
                    if store.isConnected {
                        NavigationLink { SeerrRequestsView() } label: { Label("My Requests", systemImage: "clock") }
                        if store.user?.canManageRequests == true {
                            NavigationLink { SeerrRequestsView(managing: true) } label: { Label("Manage Requests", systemImage: "checklist") }
                        }
                    }
                    NavigationLink { SeerrSettingsView() } label: { Label("Discover Settings", systemImage: "gearshape") }
                }
                .accessibilityIdentifier("Seerr.menu")
            }
            if store.isConnected {
                ToolbarItem { NavigationLink("My Requests") { SeerrRequestsView() } }
            }
        }
        .sheet(isPresented: $showingSetup) { SeerrConnectView() }
    }

    private func hide() {
        preferences.setVisibility(
            false,
            forSectionID: NavigationSectionPreference.discoverID,
            libraries: root.home?.libraries ?? [],
            serverID: session.server.id,
            userID: session.user.id
        )
        root.selectedSectionID = NavigationSectionPreference.homeID
    }
}
