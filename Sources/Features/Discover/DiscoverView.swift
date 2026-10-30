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
            #if os(tvOS)
                ToolbarItem {
                    NavigationLink { SeerrSettingsView() } label: { Label("Seerr Settings", systemImage: "gearshape") }.gusTVToolbarIcon()
                }
                if store.isConnected {
                    ToolbarItem {
                        NavigationLink { DiscoverBrowseView(store: store, searchOnly: true) } label: { Label("Search Seerr", systemImage: "magnifyingglass") }.gusTVToolbarIcon()
                    }
                    if store.user?.canManageRequests == true {
                        ToolbarItem { NavigationLink("Manage Requests") { SeerrRequestsView(managing: true) } }
                    }
                }
            #else
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
                    .gusIPadIconOnly()
                    .accessibilityIdentifier("Seerr.menu")
                }
            #endif
            if store.isConnected {
                ToolbarItem {
                    SeerrRequestHistoryLink().gusTVToolbarIcon()
                }
            }
        }
        .gusTVTask(isPresented: $showingSetup) { SeerrConnectView() }
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
