import SwiftUI

/// Signed-out root: a `NavigationStack` that walks Connect → Sign In.
///
/// Replaces Swiftfin's Stinsen coordinator for this flow with a plain `NavigationStack`
/// + `navigationDestination`.
struct ConnectFlowView: View {
    @State private var path: [ServerConnection] = []

    var body: some View {
        NavigationStack(path: $path) {
            ConnectServerView { server in
                path.append(server)
            }
            .navigationDestination(for: ServerConnection.self) { server in
                SignInView(server: server)
            }
        }
    }
}
