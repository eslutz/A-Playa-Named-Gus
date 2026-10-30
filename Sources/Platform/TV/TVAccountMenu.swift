import SwiftUI

extension View {
    @ViewBuilder func gusTVAccountMenu() -> some View {
        #if os(tvOS)
            if #available(tvOS 27.0, *) {
                tabViewSidebarHeader {
                    TVAccountMenu().padding(.vertical, 16)
                }
            } else {
                // OS 26 has no sidebar-header slot; retain the same native menu
                // in a focusable inset above the tabs.
                safeAreaInset(edge: .top) {
                    HStack {
                        TVAccountMenu()
                        Spacer()
                    }
                    .padding()
                }
            }
        #else
            self
        #endif
    }
}

#if os(tvOS)
    /// A direct native menu over existing saved-session switching, without extra prompts.
    private struct TVAccountMenu: View {
        @Environment(AppModel.self) private var app
        @Environment(SessionStore.self) private var session
        @Environment(AppNavigationModel.self) private var navigation
        @Environment(AudioPlaybackCoordinator.self) private var audio
        @Environment(RootNavigationState.self) private var root
        @State private var showingProfile = false
        @State private var errorMessage: String?
        @State private var reauthenticationServer: ServerConnection?

        var body: some View {
            Menu {
                Button("View and Edit Profile", systemImage: "person.crop.circle") { showingProfile = true }
                ForEach(app.servers) { server in
                    Section(server.name) {
                        ForEach(app.users(on: server)) { user in
                            Button {
                                guard user.id != session.user.id || user.serverID != session.server.id else { return }
                                guard app.hasStoredToken(for: user) else {
                                    reauthenticationServer = server
                                    return
                                }
                                do {
                                    // AppModel validates the destination before committing; root identity
                                    // replacement cancels video and clears the old navigation/focus tree.
                                    try app.switchToStoredUser(user)
                                    audio.stop()
                                    root.playerItem = nil
                                } catch { errorMessage = error.localizedDescription }
                            } label: {
                                Label(user.name, systemImage: user.id == session.user.id && user.serverID == session.server.id ? "checkmark.circle.fill" : "person.circle")
                            }
                        }
                    }
                }
                Button("Manage Accounts", systemImage: "person.crop.circle.badge.gearshape") { navigation.open(.settings) }
            } label: {
                HStack {
                    ProfileAvatar(data: session.profile.imageData)
                    Text(session.user.name)
                }
            }
            .gusTVTask(isPresented: $showingProfile) { NavigationStack { UserProfileView() } }
            .accessibilityLabel("Account")
            .accessibilityValue(session.user.name)
            .gusTVTask(item: $reauthenticationServer) { server in
                NavigationStack {
                    SignInView(server: server)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { reauthenticationServer = nil } }
                        }
                }
            }
            .alert("Account Switch Failed", isPresented: Binding(get: { errorMessage != nil }, set: {
                if !$0 {
                    errorMessage = nil
                }
            })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }
#endif
