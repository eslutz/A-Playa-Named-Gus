#if !os(tvOS)
    import SwiftUI

    /// Native menu-bar commands and keyboard shortcuts for fixed app destinations.
    @MainActor
    struct GusCommands: Commands {
        let appModel: AppModel
        let navigation: AppNavigationModel

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
                    navigation.open(.search)
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .gusKeyboardShortcut("f", modifiers: .command)
                .disabled(appModel.currentSession == nil)

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
                    appModel.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .gusKeyboardShortcut("q", modifiers: [.command, .shift])
                .disabled(appModel.currentSession == nil)
            }
        }
    }
#endif
