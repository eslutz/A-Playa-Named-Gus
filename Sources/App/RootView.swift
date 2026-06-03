import SwiftUI

/// Switches between the signed-out connect flow and the signed-in app, injecting the
/// active `SessionStore` into the signed-in tree.
///
/// Replaces Swiftfin's root coordinator: a plain `if let` on `AppModel.currentSession`.
struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let session = appModel.currentSession {
            RootContainer()
                .environment(session)
        } else {
            ConnectFlowView()
        }
    }
}
