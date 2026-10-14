import SwiftUI

/// Lists are owned by Jellyfin; the local cache permits browsing without a server.
struct VideoPlaylistsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ServerMediaListsStore.self) private var lists
    @Environment(VideoPlaylistsStore.self) private var supplemental
    @State private var creating: ServerMediaListKind?
    @State private var deleting: ServerMediaList?
    @State private var retrying: UUID?
    private var scope: AccountScope {
        session.references.scope
    }

    var body: some View {
        List {
            Section("Playlists") { rows(.playlist) }
            let pending = lists.pendingEdits(scope: scope).filter(\.needsReview)
            if !pending.isEmpty {
                Section("Changes Need Review") {
                    ForEach(pending) { edit in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(lists.list(id: edit.listID, kind: edit.kind, scope: scope)?.name ?? String(localized: "Pending List Change")).font(.headline)
                            Text(edit.message ?? String(localized: "Check this change in Jellyfin before retrying.")).foregroundStyle(.secondary)
                            HStack {
                                Button("Refresh") { Task { await lists.refresh(session: session) } }
                                Button("Retry") { retrying = edit.id }
                                Button("Discard Change", role: .destructive) { _ = lists.discardPendingEdit(id: edit.id, scope: scope) }
                            }
                        }
                    }
                }
            }
            let legacy = supplemental.playlists(scope: scope).filter { lists.legacyImportID(for: $0.id, scope: scope) == nil }
            if !legacy.isEmpty {
                Section("Import Gus Playlists") {
                    Text("Copy your previous Gus playlists to Jellyfin. Originals remain available until import succeeds.").foregroundStyle(.secondary)
                    ForEach(legacy) { playlist in
                        Button { Task { _ = await lists.importLegacy(playlist, session: session) } } label: {
                            Label(playlist.name, systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            if let message = lists.statusMessage, !message.isEmpty {
                Section { Text(message).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Playlist", systemImage: "list.and.film") { creating = .playlist }
                } label: { Label("New List", systemImage: "plus") }
            }
        }
        .sheet(isPresented: Binding(get: { creating != nil }, set: {
            if !$0 {
                creating = nil
            }
        })) {
            NavigationStack {
                ServerListNameEditor(initialName: "", title: "New Playlist", saveTitle: "Create") { name in
                    await lists.create(name: name, kind: creating ?? .playlist, session: session) != nil
                }
            }
        }
        .confirmationDialog("Delete List?", isPresented: Binding(get: { deleting != nil }, set: {
            if !$0 {
                deleting = nil
            }
        })) {
            Button("Delete", role: .destructive) {
                if let deleting {
                    Task { _ = await lists.delete(id: deleting.id, kind: deleting.kind, session: session) }
                }
                deleting = nil
            }
        } message: { Text("This removes the list from Jellyfin. Your media files and watched history are preserved.") }
        .confirmationDialog("Retry This Change?", isPresented: Binding(get: { retrying != nil }, set: {
            if !$0 {
                retrying = nil
            }
        })) {
            Button("Retry After Checking Jellyfin") {
                if let retrying {
                    Task { await lists.retryPendingEdit(id: retrying, session: session) }
                }; retrying = nil
            }
        } message: { Text("The previous request may have succeeded. Check Jellyfin first to avoid creating a duplicate playlist or entry.") }
        .serverListErrorAlert(lists)
        .safeAreaInset(edge: .top) { SavedPlaylistErrorBanner() }
        .task { supplemental.load(scope: scope); lists.load(scope: scope); await lists.refresh(session: session) }
        .refreshable { await lists.refresh(session: session) }
    }

    @ViewBuilder private func rows(_ kind: ServerMediaListKind) -> some View {
        let values = lists.lists(kind: kind, scope: scope)
        if values.isEmpty {
            Text(String(localized: "No Playlists")).foregroundStyle(.secondary)
        }
        ForEach(values) { list in
            Group {
                if kind == .playlist {
                    NavigationLink(value: VideoPlaylistRef(id: list.id)) { label(list) }
                }
            }
            .contextMenu { Button("Delete", role: .destructive) { deleting = list }.disabled(!list.canEdit) }
        }
    }

    private func label(_ list: ServerMediaList) -> some View {
        VStack(alignment: .leading) {
            Text(list.name)
            if list.entriesLoaded {
                Text("\(list.entries.count) items").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct VideoPlaylistDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ServerMediaListsStore.self) private var lists
    @Environment(VideoPlaylistsStore.self) private var supplemental
    let id: UUID
    @State private var renaming = false
    @State private var adding = false
    @State private var replacing: VideoPlaylistEntry?
    @State private var player: ItemRef?
    @State private var loadingEntries = false
    private var scope: AccountScope {
        session.references.scope
    }

    private var playlist: VideoPlaylist? {
        lists.videoPlaylist(id: id, scope: scope, supplemental: supplemental)
    }

    private var serverList: ServerMediaList? {
        lists.list(id: id, kind: .playlist, scope: scope)
    }

    var body: some View {
        Group {
            if let playlist, let serverList {
                List {
                    if serverList.entriesLoaded {
                        if serverList.entries.allSatisfy({ $0.item.isAudioPlayable }) && !serverList.entries.isEmpty {
                            Section {
                                NavigationLink("Open Audio Playlist") {
                                    AlbumDetailView(album: MediaItem(id: ServerMediaListID.string(serverList.id), name: serverList.name, type: .playlist))
                                }
                            }
                        } else {
                            playbackControls(playlist)
                        }
                        Section("Entries") {
                            if playlist.entries.isEmpty {
                                Text("Add movies or individual episodes to get started.").foregroundStyle(.secondary)
                            }
                            ForEach(Array(playlist.entries.enumerated()), id: \.element.id) { index, entry in
                                entryRow(entry, index: index, playlist: playlist, canEdit: serverList.canEdit)
                            }
                            .onDelete { offsets in
                                guard serverList.canEdit else { return }
                                for index in offsets {
                                    Task { _ = await lists.remove(entryID: playlist.entries[index].id, from: id, kind: .playlist, session: session) }
                                }
                            }
                            .onMove { offsets, destination in
                                guard serverList.canEdit, let index = offsets.first else { return }
                                var entries = playlist.entries
                                let moved = entries.remove(at: index)
                                let target = min(max(destination > index ? destination - 1 : destination, 0), entries.count)
                                Task { _ = await lists.move(entryID: moved.id, in: id, before: target < entries.count ? entries[target].id : nil, session: session) }
                            }
                        }
                    } else if loadingEntries {
                        ProgressView()
                    } else {
                        ContentUnavailableView("Playlist Entries Unavailable", systemImage: "wifi.slash", description: Text("Connect to Jellyfin to load the entries for this playlist."))
                        Button("Try Again") { Task { loadingEntries = true; await lists.refresh(id: id, kind: .playlist, session: session); loadingEntries = false } }
                    }
                    if let message = lists.statusMessage, !message.isEmpty {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle(playlist.name)
                .toolbar {
                    ToolbarItem { Button("Add Media", systemImage: "plus") { adding = true }.disabled(!serverList.canEdit) }
                    ToolbarItem { Button("Rename") { renaming = true }.disabled(!serverList.canEdit) }
                }
            } else {
                ContentUnavailableView("Playlist Unavailable", systemImage: "list.and.film", description: Text("Refresh while connected to Jellyfin to load this playlist."))
            }
        }
        .sheet(isPresented: $renaming) {
            NavigationStack {
                ServerListNameEditor(initialName: playlist?.name ?? "", title: "Rename Playlist", saveTitle: "Save") { name in
                    await lists.rename(id: id, kind: .playlist, name: name, session: session)
                }
            }
        }
        .sheet(isPresented: $adding) { NavigationStack { ServerListSearchView(listID: id, kind: .playlist) } }
        .sheet(item: $replacing) { entry in
            MediaReplacementPicker(item: entry.reference.item, candidates: []) { replacement in
                guard let current = try? await session.references.selectedReplacement(replacement) else { return false }
                return await lists.replace(entryID: entry.id, in: id, with: current, session: session)
            }
        }
        .serverListErrorAlert(lists)
        .safeAreaInset(edge: .top) { SavedPlaylistErrorBanner() }
        .playerPresentation(item: $player)
        .task {
            loadingEntries = true
            supplemental.load(scope: scope); lists.load(scope: scope)
            supplemental.registerServerPlaylist(id: lists.resolvedID(id, scope: scope), scope: scope)
            await lists.refresh(id: id, kind: .playlist, session: session)
            loadingEntries = false
        }
        .refreshable { await lists.refresh(id: id, kind: .playlist, session: session) }
    }

    private func playbackControls(_ playlist: VideoPlaylist) -> some View {
        let unresolvedResume = playlist.cursor?.finished != true && playlist.cursor?.entryID.map { current in !playlist.entries.contains { $0.id == current } } == true
        let isVideo = !playlist.entries.isEmpty && playlist.entries.allSatisfy { [.movie, .episode, .video].contains($0.reference.item.type) }
        return Section {
            if unresolvedResume {
                Label("Resume Entry Unavailable", systemImage: "exclamationmark.triangle"); Text("Choose an entry to play from, or start this playlist again.").foregroundStyle(.secondary)
            }
            if playlist.cursor?.finished == true {
                Label("Playlist Finished", systemImage: "checkmark.circle")
            } else if let current = playlist.entries.firstIndex(where: { $0.id == playlist.cursor?.entryID }) {
                Text("Playlist \(current + 1) of \(playlist.entries.count)")
            }
            Button("Play from Beginning", systemImage: "play.fill") { play(playlist.entries.first, fromBeginning: true) }.disabled(!isVideo)
            Button("Continue Playlist", systemImage: "play.circle") {
                play(playlist.entries.first(where: { $0.id == playlist.cursor?.entryID }) ?? playlist.entries.first, fromBeginning: playlist.cursor?.finished == true)
            }.disabled(!isVideo || unresolvedResume)
            if !isVideo && !playlist.entries.isEmpty {
                Text("Play mixed media individually. Ordered video playback supports movies and episodes.").foregroundStyle(.secondary)
            }
            Toggle("Add to Next Up", isOn: Binding(get: { playlist.queued }, set: {
                let resolved = lists.resolvedID(id, scope: scope)
                supplemental.setQueued(id: resolved, queued: $0, scope: scope)
                NextUpActivityStore.shared.setDismissed("playlist:" + resolved.uuidString, dismissed: !$0, scope: scope)
            }))
        }
    }

    private func entryRow(_ entry: VideoPlaylistEntry, index: Int, playlist: VideoPlaylist, canEdit: Bool) -> some View {
        let admitted = ContentRatingGate.admitsStored(entry.reference.item)
        let isVideo = playlist.entries.allSatisfy { [.movie, .episode, .video].contains($0.reference.item.type) }
        return HStack {
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
        .mediaItemContextMenu(item: admitted ? entry.reference.item : nil, groupName: playlist.name, canRemove: canEdit, remove: {
            _ = await lists.remove(entryID: entry.id, from: id, kind: .playlist, session: session)
        }) {
            Button("Play from Here") { play(entry, fromBeginning: true) }.disabled(!admitted || !isVideo)
            Button("Move Up") { move(index, by: -1, in: playlist) }.disabled(!canEdit || index == 0)
            Button("Move Down") { move(index, by: 1, in: playlist) }.disabled(!canEdit || index == playlist.entries.count - 1)
            Button("Choose Replacement") { replacing = entry }.disabled(!admitted || !canEdit)
        }
    }

    private func play(_ entry: VideoPlaylistEntry?, fromBeginning: Bool) {
        guard let entry else { return }
        player = ItemRef(item: entry.reference.item, serverID: scope.serverID, userID: scope.userID, playlistID: lists.resolvedID(id, scope: scope), playlistEntryID: entry.id, playlistFromBeginning: fromBeginning)
    }

    private func move(_ index: Int, by offset: Int, in playlist: VideoPlaylist) {
        var entries = playlist.entries
        let entry = entries.remove(at: index)
        let destination = min(max(index + offset, 0), entries.count)
        Task { _ = await lists.move(entryID: entry.id, in: id, before: destination < entries.count ? entries[destination].id : nil, session: session) }
    }
}

/// Supplemental queue and cursor failures remain independent of native list errors.
struct SavedPlaylistErrorBanner: View {
    @Environment(VideoPlaylistsStore.self) private var store

    var body: some View {
        if let message = store.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Label("Saved Changes Unavailable", systemImage: "exclamationmark.triangle").font(.headline)
                Text(message).foregroundStyle(.secondary)
                Button("Dismiss") { store.clearError() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial)
        }
    }
}

struct AddToVideoPlaylistView: View {
    let item: MediaItem
    var body: some View {
        AddToServerMediaListView(item: item, kind: .playlist)
    }
}

private struct AddToServerMediaListView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ServerMediaListsStore.self) private var lists
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    let kind: ServerMediaListKind
    @State private var name = ""

    var body: some View {
        List {
            Section(String(localized: "Choose Playlist")) {
                ForEach(lists.lists(kind: kind, scope: session.references.scope)) { list in
                    Button(list.name) { Task {
                        if await lists.add(item: item, to: list.id, kind: kind, session: session) {
                            dismiss()
                        }
                    } }.disabled(!list.canEdit)
                }
            }
            Section(String(localized: "New Playlist")) {
                TextField("Name", text: $name)
                Button("Create and Add") {
                    guard item.id != nil else { return }
                    Task {
                        if await lists.create(name: name, kind: kind, session: session, items: [item]) != nil {
                            dismiss()
                        }
                    }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle(String(localized: "Add to Playlist"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .serverListErrorAlert(lists)
        .task { lists.load(scope: session.references.scope); await lists.refresh(session: session) }
    }
}

private struct ServerListSearchView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ServerMediaListsStore.self) private var lists
    @Environment(\.dismiss) private var dismiss
    let listID: UUID
    let kind: ServerMediaListKind
    @State private var query = ""
    @State private var search: SearchStore?

    var body: some View {
        List {
            if let search {
                if case let .failed(message) = search.state {
                    Text(message); Button("Retry") { Task { await search.search(query) } }
                }
                ForEach(search.results.filter { [.movie, .episode, .video].contains($0.type) }) { item in
                    Button { Task {
                        if await lists.add(item: item, to: listID, kind: kind, session: session) {
                            dismiss()
                        }
                    } } label: {
                        VStack(alignment: .leading) {
                            Text(item.displayTitle)
                            if let series = item.seriesName {
                                Text(series).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if search.canLoadMore {
                    Button("Load More") { Task { await search.continueSearching() } }
                }
                if search.state == .loading {
                    ProgressView()
                }
                if search.state == .loaded && search.results.isEmpty {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                }
            } else {
                ProgressView()
            }
        }
        .searchable(text: $query, prompt: String(localized: "Movies and Episodes"))
        .navigationTitle("Add Media")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .task { search = SearchStore(session: session) }
        .task(id: query) { do { try await Task.sleep(for: .milliseconds(300)) } catch { return }; await search?.search(query) }
        .serverListErrorAlert(lists)
    }
}

extension View {
    func serverListErrorAlert(_ store: ServerMediaListsStore) -> some View {
        alert("List Could Not Be Updated", isPresented: Binding(get: { store.errorMessage != nil }, set: {
            if !$0 {
                store.clearError()
            }
        })) {
            Button("OK", role: .cancel) { store.clearError() }
        } message: { Text(store.errorMessage ?? "") }
    }
}

/// Editor-owned state avoids the native alert's stale field value on Save.
private struct ServerListNameEditor: View {
    @Environment(ServerMediaListsStore.self) private var lists
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var saving = false
    let title: LocalizedStringKey
    let saveTitle: LocalizedStringKey
    let save: @MainActor (String) async -> Bool

    init(initialName: String, title: LocalizedStringKey, saveTitle: LocalizedStringKey, save: @escaping @MainActor (String) async -> Bool) {
        _name = State(initialValue: initialName); self.title = title; self.saveTitle = saveTitle; self.save = save
    }

    var body: some View {
        Form { TextField("Name", text: $name) }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        guard !saving else { return }; saving = true
                        Task {
                            let saved = await save(name); saving = false; if saved {
                                dismiss()
                            }
                        }
                    }.disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .serverListErrorAlert(lists)
    }
}
