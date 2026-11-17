import SwiftUI

/// Signed-out root: a `NavigationStack` that walks Connect → Sign In.
///
/// Replaces Swiftfin's Stinsen coordinator for this flow with a plain `NavigationStack`
/// + `navigationDestination`.
struct ConnectFlowView: View {
    @Environment(AppModel.self) private var appModel
    @State private var path: [ServerConnection] = []

    var body: some View {
        NavigationStack(path: $path) {
            ConnectServerView { server in
                path.append(server)
            }
            .navigationDestination(for: ServerConnection.self) { server in
                SignInView(server: server, initialUsername: appModel.reauthentication?.server.id == server.id ? appModel.reauthentication?.user.name ?? "" : "")
            }
        }
        .task(id: appModel.reauthentication) {
            guard let recovery = appModel.reauthentication else { return }
            path = [recovery.server]
        }
    }
}
