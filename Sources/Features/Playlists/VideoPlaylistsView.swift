import SwiftUI

/// Lists are owned by Jellyfin; the local cache permits browsing without a server.
struct VideoPlaylistsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ServerMediaListsStore.self) private var lists
    @Environment(SavedMediaStore.self) private var supplemental
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
            if let message = lists.statusMessage, !message.isEmpty {
                Section { Text(message).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = .playlist } label: { GusToolbarLabel("New Playlist", systemImage: "plus") }
                    .labelStyle(.iconOnly)
                    .gusTVToolbarIcon()
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

    private var rowCoverWidth: CGFloat {
        #if os(tvOS)
            72
        #else
            52
        #endif
    }

    private func label(_ list: ServerMediaList) -> some View {
        HStack(spacing: 24) {
            PlaylistCoverArtwork(playlist: list.coverItem, entries: list.entries.map(\.item), maxWidth: Int(rowCoverWidth * 3))
                .frame(width: rowCoverWidth, height: rowCoverWidth)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
    @Environment(SavedMediaStore.self) private var supplemental
    @Environment(AudioPlaybackCoordinator.self) private var audio
    @Environment(OfflineDownloadStore.self) private var downloads
    let id: UUID
    @State private var adding = false
    @State private var replacing: VideoPlaylistEntry?
    @State private var player: ItemRef?
    @State private var loadingEntries = false
    @State private var editing = false
    @State private var deletingPlaylist = false
    @State private var mutating = false
    @ScaledMetric(relativeTo: .body) private var numberDigitWidth: CGFloat = 10.5
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
                List {
                    Section {
                        playlistHeader(playlist, list: serverList)
                    }
                    .listRowBackground(Color.clear)
                    if serverList.entriesLoaded {
                        Section {
                            if playlist.entries.isEmpty {
                                Text("Add movies or individual episodes to get started.").foregroundStyle(.secondary)
                            }
                            ForEach(Array(playlist.entries.enumerated()), id: \.element.id) { index, entry in
                                entryRow(entry, index: index, playlist: playlist, canEdit: serverList.canEdit)
                            }
                            .gusPlaylistMove(enabled: serverList.canEdit && !mutating) { indices, destination in
                                guard indices.count == 1, let source = indices.first else { return }
                                move(source, by: destination > source ? destination - source - 1 : destination - source, in: playlist)
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
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { adding = true } label: { GusToolbarLabel("Add Items", systemImage: "text.badge.plus", tvSystemImage: "plus") }
                            .labelStyle(.iconOnly)
                            .disabled(!serverList.canEdit || mutating)
                            .gusTVToolbarIcon()
                            .accessibilityIdentifier("Playlist.addItems")
                            .accessibilityLabel("Add Items")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Edit", systemImage: "pencil") { editing = true }
                            Divider()
                            Button("Delete Playlist", systemImage: "trash", role: .destructive) { deletingPlaylist = true }.disabled(!serverList.canEdit)
                        } label: { GusToolbarLabel("More", systemImage: "ellipsis") }
                            .gusIPadIconOnly()
                            .disabled(mutating)
                            .gusTVToolbarIcon()
                            .accessibilityIdentifier("Playlist.more")
                            .accessibilityLabel("More")
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
        .gusTVTask(isPresented: $editing) {
            NavigationStack { MediaListEditor(list: .playlist(id)) }
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

    private func playlistHeader(_ playlist: VideoPlaylist, list: ServerMediaList) -> some View {
        DetailCoverHeader {
            PlaylistCoverArtwork(playlist: list.coverItem, entries: list.entries.map(\.item), maxWidth: 720, contentMode: .fit)
                .frame(maxWidth: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } summary: {
            VStack(alignment: .leading, spacing: 12) {
                Text(playlist.name).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                if list.entriesLoaded {
                    Text("\(playlist.entries.count) items").font(.subheadline).foregroundStyle(.secondary)
                    if !list.entries.isEmpty && list.entries.allSatisfy({ $0.item.isAudioPlayable }) {
                        NavigationLink("Open Audio Playlist") { AlbumDetailView(album: list.coverItem) }
                    } else {
                        playbackSummary(playlist)
                    }
                }
                if let overview = list.overview {
                    DetailSynopsis(title: playlist.name, overview: overview)
                }
            }
        }
    }

    private func playbackSummary(_ playlist: VideoPlaylist) -> some View {
        let selection = playlist.playbackAction
        let isVideo = !playlist.entries.isEmpty && playlist.entries.allSatisfy { [.movie, .episode, .video].contains($0.reference.item.type) }
        return VStack(alignment: .leading, spacing: 12) {
            if selection.isUnavailable {
                Label("Resume Entry Unavailable", systemImage: "exclamationmark.triangle")
                Text("Choose an entry to play from, or start this playlist again.").foregroundStyle(.secondary)
            }
            if !selection.hasProgress, !playlist.entries.isEmpty {
                Text("Item 1 of \(playlist.entries.count)").font(.caption).foregroundStyle(.secondary)
            } else if selection.hasProgress, let current = playlist.entries.firstIndex(where: { $0.id == playlist.cursor?.entryID }) {
                Text("Resume at item \(current + 1) of \(playlist.entries.count)").font(.caption).foregroundStyle(.secondary)
            }
            DetailPrimaryButton(selection.hasProgress ? "Resume" : "Play", systemImage: "play.fill") {
                play(playlist.entries.first(where: { $0.id == selection.entryID }), fromBeginning: !selection.hasProgress)
            }
            .disabled(!isVideo || selection.isUnavailable || editing || mutating)
            .accessibilityIdentifier("Playlist.play")
            DetailActionRow {
                nextUpButton(playlist)
                ItemUserActionButton(title: "Start from Beginning", compactTitle: "Restart", systemImage: "arrow.counterclockwise") {
                    play(playlist.entries.first, fromBeginning: true)
                }
                .disabled(!isVideo || editing || mutating)
                .accessibilityIdentifier("Playlist.restart")
                ItemUserActionButton(title: "Shuffle", systemImage: "shuffle") {
                    play(playlist.entries.randomElement(), fromBeginning: true, shuffled: true)
                }
                .disabled(!isVideo || editing || mutating)
                .accessibilityIdentifier("Playlist.shuffle")
            }
            .gusPhoneHeroAccessoryStyle(onArtwork: false)
            .frame(maxWidth: DetailActionMetrics.maximumRowWidth)
            if !isVideo && !playlist.entries.isEmpty {
                Text("Play mixed media individually. Ordered video playback supports movies and episodes.").foregroundStyle(.secondary)
            }
        }
    }

    private func nextUpButton(_ playlist: VideoPlaylist) -> some View {
        let resolved = lists.resolvedID(id, scope: scope)
        let key = "playlist:" + resolved.uuidString
        let queued = playlist.appearsInNextUp && !NextUpActivityStore.shared.isDismissed(key, scope: scope)
        return ItemUserActionButton(
            title: queued ? "Remove from Next Up" : "Add to Next Up",
            compactTitle: "Next Up",
            systemImage: queued ? MediaActionSymbols.removeFromNextUp : MediaActionSymbols.addToNextUp
        ) {
            supplemental.setQueued(id: resolved, queued: !queued, scope: scope)
            NextUpActivityStore.shared.setDismissed(key, dismissed: queued, scope: scope)
        }
        .accessibilityIdentifier("Playlist.nextUp")
    }

    private func mutate(_ action: @escaping @MainActor () async -> Void) {
        guard !mutating, serverList?.canEdit == true else { return }
        mutating = true
        Task { await action(); mutating = false }
    }

    private func entryRow(_ entry: VideoPlaylistEntry, index: Int, playlist: VideoPlaylist, canEdit: Bool) -> some View {
        let admitted = ContentRatingGate.admitsStored(entry.reference.item)
        let isPlayable = [.movie, .episode, .video].contains(entry.reference.item.type) || entry.reference.item.isAudioPlayable
        let title = admitted ? entry.reference.item.displayTitle : String(localized: "Restricted Content")
        return HStack(spacing: 16) {
            Text("\(index + 1)").monospacedDigit().frame(width: max(28, CGFloat(String(max(playlist.entries.count, 1)).count) * numberDigitWidth), alignment: .trailing).foregroundStyle(.secondary)
            entryContent(entry, admitted: admitted, isPlayable: isPlayable)
                .mediaItemContextMenu(item: admitted ? entry.reference.item : nil, groupName: playlist.name, canRemove: canEdit && !mutating, remove: { remove(entry) }) {
                    Button("Play from Here") { play(entry, fromBeginning: true) }.disabled(!admitted || !isPlayable || editing || mutating)
                    Button("Move Up") { move(index, by: -1, in: playlist) }.disabled(!canEdit || index == 0)
                    Button("Move Down") { move(index, by: 1, in: playlist) }.disabled(!canEdit || index == playlist.entries.count - 1)
                    Button("Choose Replacement") { replacing = entry }.disabled(!admitted || !canEdit)
                }
        }
        .gusPlaylistSwipeRemove(title: title, enabled: canEdit && !mutating) {
            remove(entry)
        }
    }

    @ViewBuilder private func entryContent(_ entry: VideoPlaylistEntry, admitted: Bool, isPlayable: Bool) -> some View {
        if admitted && isPlayable {
            Button {
                play(entry, fromBeginning: true)
            } label: {
                HStack(spacing: 12) {
                    PlaylistEntryThumbnail(item: entry.reference.item)
                    VStack(alignment: .leading) {
                        Text(entry.reference.item.displayTitle)
                        if let series = entry.reference.item.seriesName {
                            Text([series, entry.reference.item.episodeLocator].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .disabled(editing || mutating)
            .accessibilityIdentifier("Playlist.entry." + entry.id.uuidString)
            .accessibilityHint("Plays the playlist starting with this item")
        } else if admitted {
            NavigationLink(value: ItemRef(item: entry.reference.item)) {
                HStack(spacing: 12) {
                    PlaylistEntryThumbnail(item: entry.reference.item)
                    Text(entry.reference.item.displayTitle)
                }
            }
        } else {
            Label("Restricted Content", systemImage: "lock")
        }
    }

    private func remove(_ entry: VideoPlaylistEntry) {
        mutate { _ = await lists.remove(entryID: entry.id, from: id, kind: .playlist, session: session) }
    }

    private func play(_ entry: VideoPlaylistEntry?, fromBeginning: Bool, shuffled: Bool = false) {
        guard let entry else { return }
        if let playlist, playlist.entries.allSatisfy({ $0.reference.item.isAudioPlayable }),
           let index = playlist.entries.firstIndex(where: { $0.id == entry.id })
        {
            audio.play(tracks: playlist.entries.map(\.reference.item), startIndex: index, shuffled: shuffled, request: PlaybackRequest(item: entry.reference.item, start: fromBeginning ? .fromBeginning : .automatic), session: session, downloads: downloads)
            return
        }
        if let playlist, !playlist.entries.allSatisfy({ [.movie, .episode, .video].contains($0.reference.item.type) }) {
            player = ItemRef(item: entry.reference.item, serverID: scope.serverID, userID: scope.userID, playbackRequest: PlaybackRequest(item: entry.reference.item, start: fromBeginning ? .fromBeginning : .automatic))
            return
        }
        player = ItemRef(item: entry.reference.item, serverID: scope.serverID, userID: scope.userID, playlistID: lists.resolvedID(id, scope: scope), playlistEntryID: entry.id, playlistFromBeginning: fromBeginning, playlistShuffled: shuffled)
    }

    private func move(_ index: Int, by offset: Int, in playlist: VideoPlaylist) {
        guard offset != 0, playlist.entries.indices.contains(index) else { return }
        var entries = playlist.entries
        let entry = entries.remove(at: index)
        let destination = min(max(index + offset, 0), entries.count)
        mutate { _ = await lists.move(entryID: entry.id, in: id, before: destination < entries.count ? entries[destination].id : nil, session: session) }
    }
}

struct PlaylistCoverArtwork: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var limit = ContentRatingGate.Limit.off
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false
    let playlist: MediaItem
    let entries: [MediaItem]
    let maxWidth: Int
    var aspectRatio: CGFloat = 1
    var contentMode: ContentMode = .fill

    var body: some View {
        let items = ContentRatingGate.playlistCoverItems(playlist: playlist, entries: entries, limit: limit, hideUnrated: hideUnrated)
        let urls = items.flatMap { session.mediaProvider.artworkURLs(for: $0, request: .init(role: .square, maxWidth: maxWidth)) }
        ArtworkTile(url: urls.first, aspectRatio: aspectRatio, contentMode: contentMode, placeholderSymbol: "list.and.film", fallbackURLs: Array(urls.dropFirst()))
            .accessibilityHidden(true)
    }
}

/// Keep the row stable while the server supplies an episode still, cover, or poster.
struct PlaylistEntryThumbnail: View {
    @Environment(SessionStore.self) private var session
    let item: MediaItem

    var body: some View {
        let role: MediaArtworkRole = item.type == .episode ? .episodeStill : (item.isAudioPlayable ? .square : .poster)
        let ratio: CGFloat = role == .episodeStill ? 16 / 9 : (role == .square ? 1 : 2 / 3)
        let urls = session.mediaProvider.artworkURLs(for: item, request: .init(role: role, maxWidth: 240))
        ArtworkTile(url: urls.first, aspectRatio: ratio, placeholderSymbol: item.artworkPlaceholderSymbol, fallbackURLs: Array(urls.dropFirst()))
            .frame(width: min(72, 48 * ratio))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .accessibilityHidden(true)
    }
}

/// Supplemental queue and cursor failures remain independent of native list errors.
struct SavedPlaylistErrorBanner: View {
    @Environment(SavedMediaStore.self) private var store

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
