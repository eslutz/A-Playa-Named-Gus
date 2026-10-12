import SwiftUI

struct ProgressTransferView: View {
    @Environment(SessionStore.self) private var session
    @State private var progress = OfflinePlaybackProgressStore.shared
    @State private var selected: OfflinePlaybackProgressStore.Checkpoint?
    @State private var error: String?
    @State private var replacementSelection: OfflinePlaybackProgressStore.Checkpoint?

    var body: some View {
        let transfers = progress.transfers(scope: session.references.scope)
        let unavailable = progress.unavailableCheckpoints(scope: session.references.scope)
        if !transfers.isEmpty || !unavailable.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved Progress Needs Review").font(.headline)
                ForEach(transfers, id: \.itemID) { entry in
                    Button(entry.replacement?.displayTitle ?? "Review Progress") { selected = entry }
                }
                ForEach(unavailable, id: \.itemID) { entry in
                    VStack(alignment: .leading) {
                        Text(entry.reference?.item.displayTitle ?? "Saved Playback Progress")
                        Text("Unavailable on this server").foregroundStyle(.secondary)
                        HStack {
                            Button("Retry") { progress.retry(entry, scope: session.references.scope) }
                            Button("Choose Replacement") { replacementSelection = entry }
                            Button("Keep Progress Local") { progress.keepTransferLocal(entry, scope: session.references.scope) }
                        }
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: Binding(get: { replacementSelection != nil }, set: {
                if !$0 {
                    replacementSelection = nil
                }
            })) {
                if let entry = replacementSelection {
                    MediaReplacementPicker(item: entry.reference?.item ?? MediaItem(id: entry.itemID), candidates: []) { candidate in
                        await progress.selectReplacement(entry, candidate: candidate, session: session)
                    }
                }
            }
            .confirmationDialog("Transfer saved progress to the replacement item?", isPresented: Binding(
                get: { selected != nil }, set: {
                    if !$0 {
                        selected = nil
                    }
                }
            ), titleVisibility: .visible) {
                if let entry = selected {
                    Button("Transfer Progress") {
                        Task {
                            do { try await progress.confirmTransfer(entry, session: session) }
                            catch { self.error = GusError(from: error).localizedDescription }
                        }
                    }
                    Button("Keep Progress Local") { progress.keepTransferLocal(entry, scope: session.references.scope) }
                    Button("Cancel", role: .cancel) {}
                }
            } message: {
                Text("Local files and their reading locations will be preserved. Only the saved playback position or reading percentage will be transferred.")
            }
        }
    }
}
