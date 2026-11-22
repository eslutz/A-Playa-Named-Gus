#if !os(tvOS)
    import SwiftUI

    /// Native menu-bar commands and keyboard shortcuts for fixed app destinations.
    @MainActor
    struct GusCommands: Commands {
        let appModel: AppModel
        let navigation: AppNavigationModel
        @FocusedValue(RootNavigationState.self) private var searchNavigation

        var body: some Commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Navigate") {
                Button {
                    navigation.open(.home)
                } label: {
                    Label("Home", systemImage: "house")
                }
                .gusKeyboardShortcut("1", modifiers: .command)

                Button {
                    searchNavigation?.focusSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .gusKeyboardShortcut("f", modifiers: .command)
                .disabled(searchNavigation == nil)

                Button {
                    navigation.open(.settings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .gusKeyboardShortcut("3", modifiers: .command)
                .disabled(appModel.currentSession == nil)
            }

            CommandMenu("Account") {
                Button(role: .destructive) {
                    Task { await appModel.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .gusKeyboardShortcut("q", modifiers: [.command, .shift])
                .disabled(appModel.currentSession == nil)
            }
        }
    }
#endif
