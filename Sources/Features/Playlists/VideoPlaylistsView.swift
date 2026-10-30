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
            Section { rows(.playlist) }
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
                Button { creating = .playlist } label: { GusToolbarLabel("New Playlist", systemImage: "plus") }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("Playlist.create")
                    .accessibilityLabel("New Playlist")
            }
        }
        .gusTVTask(isPresented: Binding(get: { creating != nil }, set: {
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
        HStack(spacing: 24) {
            #if os(tvOS)
                AsyncPoster(url: session.mediaProvider.primaryImageURL(for: MediaItem(id: ServerMediaListID.string(list.id), name: list.name, type: .playlist), context: .posterGrid), placeholderSymbol: "list.and.film")
                    .frame(width: 96, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
            #endif
            VStack(alignment: .leading, spacing: 8) {
                Text(list.name)
                if list.entriesLoaded {
                    Text("\(list.entries.count) items").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct VideoPlaylistDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ServerMediaListsStore.self) private var lists
    @Environment(VideoPlaylistsStore.self) private var supplemental
    @Environment(AudioPlaybackCoordinator.self) private var audio
    @Environment(OfflineDownloadStore.self) private var downloads
    let id: UUID
    @State private var renaming = false
    @State private var adding = false
    @State private var replacing: VideoPlaylistEntry?
    @State private var player: ItemRef?
    @State private var loadingEntries = false
    @State private var editing = false
    @State private var deletingPlaylist = false
    @State private var mutating = false
    @ScaledMetric(relativeTo: .body) private var numberDigitWidth: CGFloat = 10.5
    @State private var editingEntryIDs: [UUID]?
    @Environment(\.dismiss) private var dismiss
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
                Group {
                    if editing {
                        editingContents(playlist, serverList: serverList)
                    } else {
                        List {
                            if serverList.entriesLoaded {
                                if serverList.entries.allSatisfy({ $0.item.isAudioPlayable }) && !serverList.entries.isEmpty {
                                    Section {
                                        Text("\(playlist.entries.count) items").font(.subheadline).foregroundStyle(.secondary)
                                        NavigationLink("Open Audio Playlist") {
                                            AlbumDetailView(album: MediaItem(id: ServerMediaListID.string(serverList.id), name: serverList.name, type: .playlist))
                                        }
                                    }
                                } else {
                                    playbackControls(playlist)
                                }
                                Section {
                                    if playlist.entries.isEmpty {
                                        Text("Add movies or individual episodes to get started.").foregroundStyle(.secondary)
                                    }
                                    ForEach(Array(playlist.entries.enumerated()), id: \.element.id) { index, entry in
                                        entryRow(entry, index: index, playlist: playlist, canEdit: serverList.canEdit)
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
                    }
                }
                .navigationTitle(playlist.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { adding = true } label: { GusToolbarLabel("Add Items", systemImage: "text.badge.plus", tvSystemImage: "plus") }
                            .labelStyle(.iconOnly)
                            .disabled(!serverList.canEdit || mutating)
                            .accessibilityIdentifier("Playlist.addItems")
                            .accessibilityLabel("Add Items")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if editing {
                            Button("Done") { editing = false; editingEntryIDs = nil }
                                .disabled(mutating)
                                .accessibilityIdentifier("Playlist.done")
                        } else {
                            Menu {
                                Button("Rename", systemImage: "pencil") { renaming = true }.disabled(!serverList.canEdit)
                                Button("Edit Items", systemImage: "line.3.horizontal") { editing = true }.disabled(!serverList.canEdit || !serverList.entriesLoaded)
                                if serverList.entriesLoaded, serverList.entries.isEmpty || !serverList.entries.allSatisfy({ $0.item.isAudioPlayable }) {
                                    let key = "playlist:" + lists.resolvedID(id, scope: scope).uuidString
                                    let isInNextUp = playlist.appearsInNextUp && !NextUpActivityStore.shared.isDismissed(key, scope: scope)
                                    Button(isInNextUp ? "Remove from Next Up" : "Add to Next Up", systemImage: isInNextUp ? MediaActionSymbols.removeFromNextUp : MediaActionSymbols.addToNextUp) {
                                        let resolved = lists.resolvedID(id, scope: scope)
                                        supplemental.setQueued(id: resolved, queued: !isInNextUp, scope: scope)
                                        NextUpActivityStore.shared.setDismissed(key, dismissed: isInNextUp, scope: scope)
                                    }
                                }
                                Divider()
                                Button("Delete Playlist", systemImage: "trash", role: .destructive) { deletingPlaylist = true }.disabled(!serverList.canEdit)
                            } label: { GusToolbarLabel("More", systemImage: "ellipsis") }
                                .gusIPadIconOnly()
                                .disabled(mutating)
                                .accessibilityIdentifier("Playlist.more")
                                .accessibilityLabel("More")
                        }
                    }
                }
            } else {
                ContentUnavailableView("Playlist Unavailable", systemImage: "list.and.film", description: Text("Refresh while connected to Jellyfin to load this playlist."))
            }
        }
        .alert("Delete Playlist?", isPresented: $deletingPlaylist) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                mutate {
                    if await lists.delete(id: id, kind: .playlist, session: session) {
                        dismiss()
                    }
                }
            }
        } message: { Text("Delete “\(playlist?.name ?? "")”? The media will remain in your library.") }
        .gusTVTask(isPresented: $renaming) {
            NavigationStack {
                ServerListNameEditor(initialName: playlist?.name ?? "", title: "Rename Playlist", saveTitle: "Save") { name in
                    await lists.rename(id: id, kind: .playlist, name: name, session: session)
                }
            }
        }
        .gusTVTask(isPresented: $adding) { NavigationStack { ServerListSearchView(listID: id, kind: .playlist) } }
        .gusTVTask(item: $replacing) { entry in
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
        Section { playbackSummary(playlist) }
    }

    private func playbackSummary(_ playlist: VideoPlaylist) -> some View {
        let selection = playlist.playbackAction
        let isVideo = !playlist.entries.isEmpty && playlist.entries.allSatisfy { [.movie, .episode, .video].contains($0.reference.item.type) }
        return Group {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(playlist.entries.count) items").font(.subheadline).foregroundStyle(.secondary)
                if selection.isUnavailable {
                    Label("Resume Entry Unavailable", systemImage: "exclamationmark.triangle")
                    Text("Choose an entry to play from, or start this playlist again.").foregroundStyle(.secondary)
                }
                if !selection.hasProgress, !playlist.entries.isEmpty {
                    Text("Item 1 of \(playlist.entries.count)").font(.caption).foregroundStyle(.secondary)
                } else if selection.hasProgress, let current = playlist.entries.firstIndex(where: { $0.id == playlist.cursor?.entryID }) {
                    Text("Resume at item \(current + 1) of \(playlist.entries.count)").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button {
                        play(playlist.entries.first(where: { $0.id == selection.entryID }), fromBeginning: !selection.hasProgress)
                    } label: {
                        Label(selection.hasProgress ? "Resume" : "Play", systemImage: "play.fill")
                            .gusProminentActionForeground()
                            .frame(maxWidth: .infinity).gusPhoneActionLabelHeight()
                    }
                    .gusProminentGlassButtonStyle().gusProminentActionTint()
                    .disabled(!isVideo || selection.isUnavailable || editing || mutating)
                    .accessibilityIdentifier("Playlist.play")
                    Button {
                        play(playlist.entries.first, fromBeginning: true)
                    } label: {
                        Label("Start from Beginning", systemImage: "arrow.counterclockwise")
                            .labelStyle(.iconOnly).frame(minWidth: 24, minHeight: 24)
                    }
                    .gusGlassButtonStyle().buttonBorderShape(.circle)
                    .disabled(!isVideo || editing || mutating)
                    .accessibilityIdentifier("Playlist.restart")
                    Button {
                        play(playlist.entries.randomElement(), fromBeginning: true, shuffled: true)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .labelStyle(.iconOnly).frame(minWidth: 24, minHeight: 24)
                    }
                    .gusGlassButtonStyle().buttonBorderShape(.circle)
                    .disabled(!isVideo || editing || mutating)
                    .accessibilityIdentifier("Playlist.shuffle")
                }
                .controlSize(.large)
                .frame(maxWidth: DetailActionMetrics.maximumRowWidth)
                if !isVideo && !playlist.entries.isEmpty {
                    Text("Play mixed media individually. Ordered video playback supports movies and episodes.").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// iOS uses a native scroll container because List owns its trailing reorder affordance.
    private func editingContents(_ playlist: VideoPlaylist, serverList: ServerMediaList) -> some View {
        let entries = editingEntryIDs.map { ids in ids.compactMap { id in playlist.entries.first { $0.id == id } } } ?? playlist.entries
        #if os(iOS)
            return ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    playbackSummary(playlist)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            editingRow(entry, index: index, playlist: playlist)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .dropDestination(for: String.self) { payloads, _ in
                                    _ = acceptMove(payloads, before: entry.id, playlist: playlist)
                                }
                            if index + 1 < entries.count {
                                Divider().padding(.leading, 16)
                            }
                        }
                        Color.clear.frame(height: 24)
                            .accessibilityHidden(true)
                            .dropDestination(for: String.self) { payloads, _ in
                                _ = acceptMove(payloads, before: nil, playlist: playlist)
                            }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    if let message = lists.statusMessage, !message.isEmpty {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        #else
            return List {
                playbackControls(playlist)
                Section {
                    #if os(tvOS)
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            editingRow(entry, index: index, playlist: playlist)
                        }
                    #else
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            editingRow(entry, index: index, playlist: playlist)
                                .moveDisabled(!serverList.canEdit || mutating)
                        }
                        .onMove { offsets, destination in
                            guard offsets.count == 1, let source = offsets.first, !mutating, serverList.canEdit else { return }
                            var reordered = entries
                            reordered.move(fromOffsets: offsets, toOffset: destination)
                            guard reordered.map(\.id) != entries.map(\.id) else { return }
                            editingEntryIDs = reordered.map(\.id)
                            let moved = entries[source]
                            let newIndex = reordered.firstIndex { $0.id == moved.id }!
                            let before = reordered.indices.contains(newIndex + 1) ? reordered[newIndex + 1].id : nil
                            mutate {
                                _ = await lists.move(entryID: moved.id, in: id, before: before, session: session)
                                editingEntryIDs = nil
                            }
                        }
                    #endif
                }
                if let message = lists.statusMessage, !message.isEmpty {
                    Text(message).foregroundStyle(.secondary)
                }
            }
            #if os(iOS) || os(visionOS)
            .environment(\.editMode, .constant(.active))
            #endif
        #endif
    }

    private func editingRow(_ entry: VideoPlaylistEntry, index: Int, playlist: VideoPlaylist) -> some View {
        let title = ContentRatingGate.admitsStored(entry.reference.item) ? entry.reference.item.displayTitle : String(localized: "Restricted Content")
        return HStack(spacing: 16) {
            #if os(iOS)
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .draggable(dragPayload(entry))
                    .accessibilityLabel("Reorder \(title)")
                    .accessibilityIdentifier("Playlist.reorder." + entry.id.uuidString)
                    .accessibilityAction(named: "Move Up") {
                        if index > 0 {
                            move(index, by: -1, in: playlist)
                        }
                    }
                    .accessibilityAction(named: "Move Down") {
                        if index + 1 < playlist.entries.count {
                            move(index, by: 1, in: playlist)
                        }
                    }
            #elseif os(tvOS)
                PlaylistReorderHandle(title: title, moveUp: { move(index, by: -1, in: playlist) }, moveDown: { move(index, by: 1, in: playlist) }, canMoveUp: index > 0, canMoveDown: index + 1 < playlist.entries.count)
            #endif
            Text("\(index + 1)").monospacedDigit().frame(width: max(28, CGFloat(String(max(playlist.entries.count, 1)).count) * numberDigitWidth), alignment: .trailing).foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(title)
                if ContentRatingGate.admitsStored(entry.reference.item), let series = entry.reference.item.seriesName {
                    Text([series, entry.reference.item.episodeLocator].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button(role: .destructive) {
                mutate { _ = await lists.remove(entryID: entry.id, from: id, kind: .playlist, session: session) }
            } label: { Label("Remove \(title)", systemImage: "trash").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44) }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("Playlist.remove." + entry.id.uuidString)
        }
        .disabled(mutating)
    }

    private func dragPayload(_ entry: VideoPlaylistEntry) -> String {
        let payload = PlaylistItemDrag(scope: scope, playlistID: id, entryID: entry.id)
        return (try? JSONEncoder().encode(payload)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private func acceptMove(_ payloads: [String], before target: UUID?, playlist: VideoPlaylist) -> Bool {
        guard !mutating, serverList?.canEdit == true, payloads.count == 1,
              let data = payloads.first?.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PlaylistItemDrag.self, from: data),
              payload.scope == scope, payload.playlistID == id else { return false }
        let entries = playlist.entries.map(\.id)
        var before = target
        // A downward drop passes the target; an upward drop inserts before it.
        if let target, let sourceIndex = entries.firstIndex(of: payload.entryID),
           let targetIndex = entries.firstIndex(of: target), sourceIndex < targetIndex
        {
            before = entries.indices.contains(targetIndex + 1) ? entries[targetIndex + 1] : nil
        }
        guard let move = payload.destination(in: entries, scope: scope, playlistID: id, before: before) else { return false }
        mutate { _ = await lists.move(entryID: move.entryID, in: id, before: move.before, session: session) }
        return true
    }

    private func mutate(_ action: @escaping @MainActor () async -> Void) {
        guard !mutating, serverList?.canEdit == true else { return }
        mutating = true
        Task { await action(); mutating = false }
    }

    private func entryRow(_ entry: VideoPlaylistEntry, index: Int, playlist: VideoPlaylist, canEdit: Bool) -> some View {
        let admitted = ContentRatingGate.admitsStored(entry.reference.item)
        let isPlayable = [.movie, .episode, .video].contains(entry.reference.item.type) || entry.reference.item.isAudioPlayable
        return HStack(spacing: 16) {
            Text("\(index + 1)").monospacedDigit().frame(width: max(28, CGFloat(String(max(playlist.entries.count, 1)).count) * numberDigitWidth), alignment: .trailing).foregroundStyle(.secondary)
            if admitted && isPlayable {
                Button {
                    play(entry, fromBeginning: true)
                } label: {
                    VStack(alignment: .leading) {
                        Text(entry.reference.item.displayTitle)
                        if let series = entry.reference.item.seriesName {
                            Text([series, entry.reference.item.episodeLocator].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(editing || mutating)
                .accessibilityIdentifier("Playlist.entry." + entry.id.uuidString)
                .accessibilityHint("Plays the playlist starting with this item")
            } else if admitted {
                NavigationLink(value: ItemRef(item: entry.reference.item)) { Text(entry.reference.item.displayTitle) }
            } else {
                Label("Restricted Content", systemImage: "lock")
            }
        }
        .mediaItemContextMenu(item: admitted ? entry.reference.item : nil, groupName: playlist.name, canRemove: canEdit, remove: {
            _ = await lists.remove(entryID: entry.id, from: id, kind: .playlist, session: session)
        }) {
            Button("Play from Here") { play(entry, fromBeginning: true) }.disabled(!admitted || !isPlayable || editing || mutating)
            Button("Move Up") { move(index, by: -1, in: playlist) }.disabled(!canEdit || index == 0)
            Button("Move Down") { move(index, by: 1, in: playlist) }.disabled(!canEdit || index == playlist.entries.count - 1)
            Button("Choose Replacement") { replacing = entry }.disabled(!admitted || !canEdit)
        }
    }

    private func play(_ entry: VideoPlaylistEntry?, fromBeginning: Bool, shuffled: Bool = false) {
        guard let entry else { return }
        if let playlist, playlist.entries.allSatisfy({ $0.reference.item.isAudioPlayable }),
           let index = playlist.entries.firstIndex(where: { $0.id == entry.id })
        {
            audio.play(tracks: playlist.entries.map(\.reference.item), startIndex: index, shuffled: shuffled, playbackStart: fromBeginning ? .fromBeginning : .automatic, session: session, downloads: downloads)
            return
        }
        if let playlist, !playlist.entries.allSatisfy({ [.movie, .episode, .video].contains($0.reference.item.type) }) {
            player = ItemRef(item: entry.reference.item, serverID: scope.serverID, userID: scope.userID, playbackStart: fromBeginning ? .fromBeginning : .automatic)
            return
        }
        player = ItemRef(item: entry.reference.item, serverID: scope.serverID, userID: scope.userID, playlistID: lists.resolvedID(id, scope: scope), playlistEntryID: entry.id, playlistFromBeginning: fromBeginning, playlistShuffled: shuffled)
    }

    private func move(_ index: Int, by offset: Int, in playlist: VideoPlaylist) {
        var entries = playlist.entries
        let entry = entries.remove(at: index)
        let destination = min(max(index + offset, 0), entries.count)
        mutate { _ = await lists.move(entryID: entry.id, in: id, before: destination < entries.count ? entries[destination].id : nil, session: session) }
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
