import SwiftUI

/// Missing pins remain manageable even when their detail route no longer exists.
struct SavedQueueRecoveryRail: View {
    @Environment(SessionStore.self) private var session
    @Environment(UpNextStore.self) private var upNext
    @State private var selection: UpNextEntry?

    private var missing: [UpNextEntry] {
        upNext.entries(serverID: session.server.id, userID: session.user.id)
            .filter { ($0.availability == .unavailable || $0.availability == .requiresSelection) && ContentRatingGate.admitsStored($0.reference.item) }
    }

    var body: some View {
        if !missing.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Unavailable in Next Up").font(.title2.bold())
                ForEach(missing) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.reference.item.displayTitle).font(.headline)
                        Text("Unavailable on this server").foregroundStyle(.secondary)
                        HStack {
                            Button("Retry") { Task { await upNext.refresh(session: session, force: true) } }
                            Button("Choose Replacement") { selection = entry }
                            Button("Remove", role: .destructive) { upNext.remove(entry) }
                        }
                    }
                }
            }
            .sheet(item: $selection) { entry in
                MediaReplacementPicker(item: entry.reference.item, candidates: upNext.candidates(for: entry)) { replacement in
                    await upNext.replace(entry, with: replacement, session: session)
                }
            }
        }
    }
}

struct MediaReplacementPicker: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    let candidates: [MediaItem]
    let choose: (MediaItem) async -> Bool
    @State private var search = ""
    @State private var results: [MediaItem] = []
    @State private var error: String?
    @State private var isChoosing = false

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).foregroundStyle(.secondary)
                }
                ForEach(ContentRatingGate.filter(results), id: \.id) { candidate in
                    Button {
                        isChoosing = true
                        Task {
                            let succeeded = await choose(candidate)
                            isChoosing = false
                            if succeeded {
                                dismiss()
                            } else {
                                error = String(localized: "The replacement could not be saved. Try again.", comment: "Saved reference replacement failure")
                            }
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(candidate.displayTitle)
                            if let year = candidate.productionYear {
                                Text(String(year)).foregroundStyle(.secondary)
                            }
                            if let locator = candidate.episodeLocator {
                                Text(locator).foregroundStyle(.secondary)
                            }
                            if let runtime = candidate.runtimeText {
                                Text(runtime).foregroundStyle(.secondary)
                            }
                            if let album = candidate.album {
                                Text(album).foregroundStyle(.secondary)
                            }
                            if let artist = candidate.albumArtist {
                                Text(artist).foregroundStyle(.secondary)
                            }
                            if let version = candidate.mediaSources.first?.mediaStreams.first(where: { $0.type == .video })?.displayTitle {
                                Text(version).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isChoosing)
                }
            }
            .navigationTitle("Choose Replacement")
            .searchable(text: $search)
            .toolbar { Button("Cancel", role: .cancel) { dismiss() } }
            .task(id: search) {
                if search.isEmpty, !candidates.isEmpty {
                    results = candidates; return
                }
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    let page = try await session.mediaProvider.items(query: MediaItemQuery(
                        searchTerm: search.isEmpty ? item.name : search,
                        includeTypes: item.type.map { [$0] }, startIndex: 0, limit: 100,
                        isRecursive: true, sort: .name
                    ))
                    try Task.checkCancellation()
                    results = page.items.filter { $0.id != nil }
                    error = nil
                } catch {
                    if !GusError(from: error).isCancellation {
                        self.error = GusError(from: error).localizedDescription
                    }
                }
            }
        }
    }
}
