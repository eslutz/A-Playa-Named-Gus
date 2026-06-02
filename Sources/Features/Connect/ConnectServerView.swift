import SwiftUI

/// Manual server-address entry → `Paths.getPublicSystemInfo`.
///
/// Pattern reference: Swiftfin's `ConnectToServerViewModel`. Bonjour discovery is a later
/// round; manual entry ships first.
struct ConnectServerView: View {

    @Environment(AppModel.self) private var appModel
    let onConnected: (ServerConnection) -> Void

    @State private var urlText = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("http://192.168.1.50:8096", text: $urlText)
                    .urlFieldStyle()
                    .onSubmit(connect)
            } header: {
                Text("Server Address")
            } footer: {
                Text("Enter your Jellyfin server's address, including the port (default 8096).")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section {
                Button(action: connect) {
                    HStack {
                        Text("Connect")
                        Spacer()
                        if isConnecting { ProgressView() }
                    }
                }
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Connect to Jellyfin")
    }

    private func connect() {
        guard !isConnecting else { return }
        errorMessage = nil
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                let server = try await appModel.connect(to: urlText)
                onConnected(server)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
