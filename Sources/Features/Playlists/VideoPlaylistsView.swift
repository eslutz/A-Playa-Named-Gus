import SwiftUI

struct VideoPlaylistsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(VideoPlaylistsStore.self) private var store
    @State private var creating = false
    @State private var deleting: UUID?
    private var scope: AccountScope {
        session.references.scope
    }

    var body: some View {
        List {
            if store.playlists(scope: scope).isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "list.and.film", description: Text("Create a playlist to watch movies and episodes in your own order."))
            }
            ForEach(store.playlists(scope: scope)) { playlist in
                NavigationLink(value: VideoPlaylistRef(id: playlist.id)) {
                    VStack(alignment: .leading) {
                        Text(playlist.name)
                        Text("\(playlist.entries.count) items").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contextMenu {
                    Button("Delete Playlist", role: .destructive) { deleting = playlist.id }
                }
            }
            .onDelete { offsets in
                if let offset = offsets.first {
                    deleting = store.playlists(scope: scope)[offset].id
                }
            }
            Section("iCloud Sync") { Text(store.syncStatus).foregroundStyle(.secondary) }
        }
        .navigationTitle("Playlists")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("New Playlist", systemImage: "plus") { creating = true } } }
        .sheet(isPresented: $creating) {
            NavigationStack {
                VideoPlaylistNameEditor(initialName: "", title: "New Playlist", saveTitle: "Create") { name in
                    store.clearError()
                    return store.create(name: name, scope: scope) != nil
                }
            }
        }
        .confirmationDialog("Delete Playlist?", isPresented: Binding(get: { deleting != nil }, set: {
            if !$0 {
                deleting = nil
            }
        })) {
            Button("Delete Playlist", role: .destructive) {
                if let deleting {
                    store.delete(id: deleting, scope: scope)
                }; deleting = nil
            }
        } message: { Text("This deletes the playlist on your synced devices. Your media and watched history are preserved.") }
        .playlistErrorAlert(store)
        .task { store.load(scope: scope) }
    }
}

struct VideoPlaylistDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(VideoPlaylistsStore.self) private var store
    let id: UUID
    @State private var renaming = false
    @State private var adding = false
    @State private var replacing: VideoPlaylistEntry?
    @State private var player: ItemRef?
    private var scope: AccountScope {
        session.references.scope
    }

    private var playlist: VideoPlaylist? {
        store.playlist(id: id, scope: scope)
    }

    var body: some View {
        Group {
            if let playlist {
                List {
                    Section {
                        if playlist.cursor?.finished == true {
                            Label("Playlist Finished", systemImage: "checkmark.circle")
                        } else if let current = playlist.entries.firstIndex(where: { $0.id == playlist.cursor?.entryID }) {
                            Text("Playlist \(current + 1) of \(playlist.entries.count)")
                        }
                        Button("Play from Beginning", systemImage: "play.fill") { play(playlist.entries.first, fromBeginning: true) }.disabled(playlist.entries.isEmpty)
                        Button("Continue Playlist", systemImage: "play.circle") {
                            play(playlist.entries.first(where: { $0.id == playlist.cursor?.entryID }) ?? playlist.entries.first, fromBeginning: playlist.cursor?.finished == true)
                        }.disabled(playlist.entries.isEmpty)
                        Toggle("Add to Next Up", isOn: Binding(get: { playlist.queued }, set: { store.setQueued(id: id, queued: $0, scope: scope) }))
                    }
                    Section("Entries") {
                        if playlist.entries.isEmpty {
                            Text("Add movies or individual episodes to get started.").foregroundStyle(.secondary)
                        }
                        ForEach(Array(playlist.entries.enumerated()), id: \.element.id) { index, entry in
                            let admitted = ContentRatingGate.admitsStored(entry.reference.item)
                            HStack {
                                Text("\(index + 1)").foregroundStyle(.secondary)
                                if admitted {
                                    NavigationLink(value: ItemRef(item: entry.reference.item)) {
                                        VStack(alignment: .leading) {
                                            Text(entry.reference.item.displayTitle)
                                            if let series = entry.reference.item.seriesName {
                                                Text([series, entry.reference.item.episodeLocator].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                } else {
                                    Label("Restricted Content", systemImage: "lock")
                                }
                            }
                            .contextMenu {
                                Button("Play from Here") { play(entry, fromBeginning: true) }.disabled(!admitted)
                                Button("Move Up") { move(index, by: -1, in: playlist) }.disabled(index == 0)
                                Button("Move Down") { move(index, by: 1, in: playlist) }.disabled(index == playlist.entries.count - 1)
                                Button("Choose Replacement") { replacing = entry }.disabled(!admitted)
                                Button("Remove", role: .destructive) { store.remove(entryID: entry.id, from: id, scope: scope) }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                store.remove(entryID: playlist.entries[index].id, from: id, scope: scope)
                            }
                        }
                        .onMove { offsets, destination in
                            guard let index = offsets.first else { return }
                            var entries = playlist.entries
                            let moved = entries.remove(at: index)
                            let target = min(max(destination > index ? destination - 1 : destination, 0), entries.count)
                            store.move(entryID: moved.id, in: id, before: target < entries.count ? entries[target].id : nil, scope: scope)
                        }
                    }
                }
                .navigationTitle(playlist.name)
                .toolbar {
                    ToolbarItem { Button("Add Media", systemImage: "plus") { adding = true } }
                    ToolbarItem { Button("Rename") { renaming = true } }
                }
            } else {
                ContentUnavailableView("Playlist Unavailable", systemImage: "list.and.film", description: Text("It may have been deleted or belong to another account."))
            }
        }
        .sheet(isPresented: $renaming) {
            NavigationStack {
                VideoPlaylistNameEditor(initialName: playlist?.name ?? "", title: "Rename Playlist", saveTitle: "Save") { name in
                    store.clearError()
                    store.rename(id: id, name: name, scope: scope)
                    return store.errorMessage == nil
                }
            }
        }
        .sheet(isPresented: $adding) { NavigationStack { VideoPlaylistSearchView(playlistID: id) } }
        .sheet(item: $replacing) { entry in
            MediaReplacementPicker(item: entry.reference.item, candidates: []) { replacement in
                guard let current = try? await session.references.selectedReplacement(replacement) else { return false }
                return store.replace(entryID: entry.id, in: id, with: current, scope: scope)
            }
        }
        .playlistErrorAlert(store)
        .playerPresentation(item: $player)
    }

    private func play(_ entry: VideoPlaylistEntry?, fromBeginning: Bool) {
        guard let entry else { return }
        player = ItemRef(item: entry.reference.item, serverID: scope.serverID, userID: scope.userID, playlistID: id, playlistEntryID: entry.id, playlistFromBeginning: fromBeginning)
    }

    private func move(_ index: Int, by offset: Int, in playlist: VideoPlaylist) {
        var entries = playlist.entries
        let entry = entries.remove(at: index)
        let destination = min(max(index + offset, 0), entries.count)
        store.move(entryID: entry.id, in: id, before: destination < entries.count ? entries[destination].id : nil, scope: scope)
    }
}

struct AddToVideoPlaylistView: View {
    @Environment(SessionStore.self) private var session
    @Environment(VideoPlaylistsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    @State private var name = ""

    var body: some View {
        List {
            Section("Choose Playlist") {
                ForEach(store.playlists(scope: session.references.scope)) { playlist in
                    Button(playlist.name) {
                        if store.add(item: item, to: playlist.id, scope: session.references.scope) {
                            dismiss()
                        }
                    }
                }
            }
            Section("New Playlist") {
                TextField("Name", text: $name)
                Button("Create and Add") {
                    if let id = store.create(name: name, scope: session.references.scope), store.add(item: item, to: id, scope: session.references.scope) {
                        dismiss()
                    }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Add to Playlist")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .playlistErrorAlert(store)
        .task { store.load(scope: session.references.scope) }
    }
}

private struct VideoPlaylistSearchView: View {
    @Environment(SessionStore.self) private var session
    @Environment(VideoPlaylistsStore.self) private var playlists
    @Environment(\.dismiss) private var dismiss
    let playlistID: UUID
    @State private var query = ""
    @State private var store: SearchStore?

    var body: some View {
        List {
            if let store {
                if case let .failed(message) = store.state {
                    Text(message); Button("Retry") { Task { await store.search(query) } }
                }
                ForEach(store.results.filter { $0.type == .movie || $0.type == .episode }) { item in
                    Button {
                        if playlists.add(item: item, to: playlistID, scope: session.references.scope) {
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.displayTitle); if let series = item.seriesName {
                                Text(series).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if store.canLoadMore {
                    Button("Load More") { Task { await store.continueSearching() } }
                }
                if store.state == .loading {
                    ProgressView()
                }
                if store.state == .loaded, store.results.filter({ $0.type == .movie || $0.type == .episode }).isEmpty {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                }
            } else {
                ProgressView()
            }
        }
        .searchable(text: $query, prompt: "Movies and Episodes")
        .navigationTitle("Add Media")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .task { store = SearchStore(session: session) }
        .task(id: query) {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await store?.search(query)
        }
        .playlistErrorAlert(playlists)
    }
}

extension View {
    func playlistErrorAlert(_ store: VideoPlaylistsStore) -> some View {
        alert("Playlist Could Not Be Updated", isPresented: Binding(get: { store.errorMessage != nil }, set: {
            if !$0 {
                store.clearError()
            }
        })) {
            Button("OK", role: .cancel) { store.clearError() }
        } message: { Text(store.errorMessage ?? "") }
    }
}

/// Name entry owns its state in a native form rather than a UIKit alert action.
private struct VideoPlaylistNameEditor: View {
    @Environment(VideoPlaylistsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    let title: LocalizedStringKey
    let saveTitle: LocalizedStringKey
    let save: (String) -> Bool

    init(initialName: String, title: LocalizedStringKey, saveTitle: LocalizedStringKey, save: @escaping (String) -> Bool) {
        _name = State(initialValue: initialName)
        self.title = title
        self.saveTitle = saveTitle
        self.save = save
    }

    var body: some View {
        Form { TextField("Name", text: $name) }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        if save(name) {
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .playlistErrorAlert(store)
    }
}
