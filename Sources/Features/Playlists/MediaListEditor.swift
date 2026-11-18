import ImageIO
import SwiftUI

/// The editor owns a draft. Only Save hands edits to the Jellyfin-backed stores.
struct MediaListEditor: View {
    @Environment(SessionStore.self) private var session
    @Environment(ServerMediaListsStore.self) private var playlists
    @Environment(RootNavigationState.self) private var root
    @Environment(\.dismiss) private var dismiss
    let list: EditableMediaList

    private struct Entry: Identifiable {
        let id: String
        let item: MediaItem
    }

    @State private var name = ""
    @State private var overview = ""
    @State private var originalName = ""
    @State private var originalOverview = ""
    @State private var originalOrder: [String] = []
    @State private var entries: [Entry] = []
    @State private var removed: Set<String> = []
    @State private var cover = MediaListCoverEdit.unchanged
    @State private var originalCoverTag: String?
    @State private var preview: CGImage?
    @State private var canRename = false
    @State private var canEditMetadata = false
    @State private var canEditCover = false
    @State private var canRemove = false
    @State private var loaded = false
    @State private var saving = false
    @State private var importing = false
    @State private var discarding = false
    @State private var error: String?
    @State private var submitted: [String] = []

    private var scope: AccountScope {
        session.references.scope
    }

    private var collections: CollectionStore {
        root.collectionStore(session: session)
    }

    private var playlistID: UUID? {
        if case let .playlist(id) = list {
            return id
        }
        return nil
    }

    private var collectionID: String? {
        if case let .collection(id) = list {
            return id
        }
        return nil
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var newName: String? {
        canRename && normalizedName != originalName ? normalizedName : nil
    }

    private var newOverview: String? {
        canEditMetadata && overview != originalOverview ? overview : nil
    }

    private var order: [String] {
        entries.map(\.id).filter { !removed.contains($0) }
    }

    private var dirty: Bool {
        newName != nil || newOverview != nil || order != originalOrder || cover != .unchanged
    }

    private var serverList: EditableMediaList {
        playlistID.map { .playlist(playlists.resolvedID($0, scope: scope)) } ?? list
    }

    var body: some View {
        Form {
            #if os(tvOS)
                Section {
                    HStack {
                        Button("Cancel", action: cancel)
                        saveButton
                    }
                    .buttonStyle(.bordered)
                }
            #endif
            if collectionID != nil {
                CollectionFeedback(store: collections)
            }
            if !submitted.isEmpty {
                ForEach(Array(submitted.enumerated()), id: \.offset) { _, message in
                    Text(message).foregroundStyle(.secondary)
                }
            }
            if let error {
                Text(error).foregroundStyle(.secondary)
                if !loaded {
                    Button("Try Again") { Task { await load() } }
                }
            }
            if loaded {
                if canRename || canEditMetadata {
                    details
                }
                if canRemove {
                    contents
                }
                if canEditCover {
                    artwork
                }
            } else if error == nil {
                ProgressView()
            }
        }
        .disabled(saving)
        .navigationTitle(playlistID == nil ? "Edit Collection" : "Edit Playlist")
        .toolbar {
            #if !os(tvOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel).disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) { saveButton }
            #endif
        }
        .confirmationDialog("Discard Unsaved Changes?", isPresented: $discarding) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .interactiveDismissDisabled(dirty || saving)
        .gusTVExitTask(cancel)
        .collectionArtworkImporter(isPresented: $importing, completion: importCover)
        .task { await load() }
    }

    private var saveButton: some View {
        Button("Save") { Task { await save() } }
            .disabled(!loaded || !dirty || (canRename && normalizedName.isEmpty) || saving ||
                (collectionID != nil && !collections.canSubmitMutations))
            .accessibilityIdentifier("MediaListEditor.save")
    }

    private var details: some View {
        Section("Details") {
            if canRename {
                TextField("Name", text: $name)
            }
            if canEditMetadata {
                TextField("Description", text: $overview, axis: .vertical)
                    .lineLimit(3 ... 8)
                    .accessibilityIdentifier("MediaListEditor.description")
            }
        }
    }

    private var contents: some View {
        Section("Contents") {
            if entries.isEmpty {
                Text("No Titles").foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                let title = ContentRatingGate.admitsStored(entry.item) ? entry.item.displayTitle : String(localized: "Restricted Content")
                HStack {
                    if playlistID != nil, !removed.contains(entry.id), order.count > 1 {
                        PlaylistDragHandle(
                            title: title,
                            moveUp: { move(entry.id, by: -1) }, moveDown: { move(entry.id, by: 1) },
                            canMoveUp: neighbor(of: entry.id, offset: -1) != nil, canMoveDown: neighbor(of: entry.id, offset: 1) != nil
                        )
                        .accessibilityIdentifier("Playlist.reorder." + entry.id)
                    }
                    Text(title)
                        .strikethrough(removed.contains(entry.id))
                    Spacer()
                    Button {
                        if !removed.insert(entry.id).inserted {
                            removed.remove(entry.id)
                        }
                    } label: {
                        Label(removed.contains(entry.id) ? "Undo Removal" : "Remove", systemImage: removed.contains(entry.id) ? "arrow.uturn.backward" : "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("MediaListEditor.remove." + entry.id)
                }
                .moveDisabled(removed.contains(entry.id))
            }
            .gusPlaylistMove(enabled: playlistID != nil && !saving) { indices, offset in
                entries.move(fromOffsets: indices, toOffset: offset)
            }
        }
    }

    private var artwork: some View {
        Section("Cover") {
            switch cover {
            case .unchanged:
                if let playlistID, let playlist = playlists.list(id: playlistID, kind: .playlist, scope: scope) {
                    PlaylistCoverArtwork(playlist: playlist.coverItem, entries: playlist.entries.map(\.item), maxWidth: 360)
                        .frame(width: 120)
                } else if let collectionID, let collection = collections.collection(collectionID) {
                    let urls = collection.coverURLs(using: session.mediaProvider, limit: ContentRatingGate.storedLimit(), hideUnrated: UserDefaults.standard.bool(forKey: ContentRatingGate.hideUnratedDefaultsKey))
                    ArtworkTile(url: urls.first, contentMode: .fit, fallbackURLs: Array(urls.dropFirst()))
                        .frame(width: 120)
                        .accessibilityHidden(true)
                }
            case .replace:
                if let preview {
                    Image(decorative: preview, scale: 1)
                        .resizable().scaledToFit().frame(maxWidth: 120, maxHeight: 160)
                        .accessibilityLabel("Selected Cover")
                }
            case .remove:
                Text("Cover will be removed on Save.").foregroundStyle(.secondary)
            }
            #if !os(tvOS)
                Button("Change Artwork", systemImage: "photo") { importing = true }
            #endif
            if originalCoverTag != nil, cover != .remove {
                Button("Remove Cover", systemImage: "trash", role: .destructive) { cover = .remove; preview = nil }
            }
            if cover != .unchanged {
                Button("Undo Cover Change") { cover = .unchanged; preview = nil }
            }
        }
    }

    private func neighbor(of id: String, offset: Int) -> Int? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        let candidates = offset < 0 ? Array(entries.indices.prefix(index).reversed()) : Array(entries.indices.dropFirst(index + 1))
        return candidates.first { !removed.contains(entries[$0].id) }
    }

    private func move(_ id: String, by offset: Int) {
        guard let source = entries.firstIndex(where: { $0.id == id }), let destination = neighbor(of: id, offset: offset) else { return }
        let entry = entries.remove(at: source)
        entries.insert(entry, at: destination)
    }

    private func cancel() {
        guard !saving else { return }
        if dirty {
            discarding = true
        } else {
            dismiss()
        }
    }

    private func importCover(_ result: Result<URL, Error>) {
        do {
            let jpeg = try CollectionArtwork.jpeg(from: result.get())
            cover = .replace(jpeg)
            if let source = CGImageSourceCreateWithData(jpeg as CFData, nil) {
                preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 480,
                ] as CFDictionary)
            }
            error = nil
        } catch {
            if (error as NSError).code != NSUserCancelledError {
                self.error = error.localizedDescription
            }
        }
    }

    private func load() async {
        guard !loaded else { return }
        error = nil
        switch list {
        case let .playlist(id):
            if playlists.list(id: id, kind: .playlist, scope: scope)?.entriesLoaded != true {
                await playlists.refresh(id: id, kind: .playlist, session: session)
            }
            guard let playlist = playlists.list(id: id, kind: .playlist, scope: scope), playlist.canEdit else {
                error = String(localized: "The editable playlist could not be loaded.")
                return
            }
            canRename = true
            canRemove = playlist.entriesLoaded
            originalName = playlist.name
            originalOverview = playlist.overview ?? ""
            originalCoverTag = playlist.primaryImageTag
            entries = playlist.entries.map { Entry(id: $0.id.uuidString, item: $0.item) }
            // An offline playlist still exposes its locally journaled controls.
            canEditMetadata = (try? await session.mediaProvider.canEditMediaListMetadata(serverList)) == true
            canEditCover = (try? await session.mediaProvider.canEditMediaListCover(serverList)) == true
        case let .collection(id):
            await collections.loadPermissions()
            await collections.loadDetail(id: id)
            guard let collection = collections.collection(id) else {
                error = String(localized: "The editable collection could not be loaded.")
                return
            }
            canRename = collections.capabilities.editMetadata
            canEditMetadata = collections.capabilities.editMetadata
            canEditCover = collections.capabilities.editArtwork
            canRemove = collection.membersLoaded && collections.memberErrors[id] == nil && collections.capabilities.removeMembers
            originalName = collection.item.displayTitle
            originalOverview = collection.item.overview ?? ""
            originalCoverTag = collection.item.imageTags["Primary"]
            entries = ContentRatingGate.filter(collection.members).compactMap { item in item.id.map { Entry(id: $0, item: item) } }
        }
        name = originalName
        overview = originalOverview
        originalOrder = entries.map(\.id)
        loaded = true
    }

    private func save() async {
        guard dirty, !saving, session.isActive else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            if newOverview != nil || (collectionID != nil && newName != nil) {
                guard try await session.mediaProvider.canEditMediaListMetadata(serverList) else { throw GusError.forbidden }
            }
            if cover != .unchanged {
                guard try await session.mediaProvider.canEditMediaListCover(serverList) else { throw GusError.forbidden }
            }
            if let playlistID {
                guard try await savePlaylist(playlistID) else { return }
            } else if let collectionID {
                guard try await saveCollection(collectionID) else { return }
            }
            dismiss()
        } catch {
            let failure = GusError(from: error)
            failure.handleIfUnauthorized(session: session)
            self.error = failure.localizedDescription
        }
    }

    private func savePlaylist(_ id: UUID) async throws -> Bool {
        if newName != nil || order != originalOrder {
            let outcome = try await playlists.savePlaylistEdit(
                id: id,
                expectedName: originalName,
                name: newName,
                expectedOrder: originalOrder.compactMap(UUID.init(uuidString:)),
                order: order == originalOrder ? nil : order.compactMap(UUID.init(uuidString:)),
                session: session
            )
            originalName = normalizedName
            acceptMembership()
            if outcome == .uncertain {
                submitted.append(String(localized: "Playlist changes need server review."))
                return false
            }
            submitted.append(outcome == .queued
                ? String(localized: "Playlist changes queued on this device.")
                : String(localized: "Playlist changes submitted."))
        }
        guard newOverview != nil || cover != .unchanged else { return true }
        await playlists.refresh(id: id, kind: .playlist, session: session)
        guard session.isActive else { throw GusError.cancelled }
        let nativeID = playlists.resolvedID(id, scope: scope)
        guard !playlists.pendingEdits(scope: scope).contains(where: { playlists.resolvedID($0.listID, scope: scope) == nativeID }) else {
            error = String(localized: "The description and cover can be saved after the pending playlist changes reach Jellyfin.")
            return false
        }
        do {
            if let newOverview {
                try await session.mediaProvider.editMediaListMetadata(
                    serverList,
                    name: nil,
                    expectedName: originalName,
                    overview: newOverview,
                    expectedOverview: originalOverview
                )
                originalOverview = newOverview
                submitted.append(String(localized: "Description saved."))
            }
            if cover != .unchanged {
                try await session.mediaProvider.editMediaListCover(serverList, change: cover, expectedTag: originalCoverTag)
                cover = .unchanged
                preview = nil
            }
        } catch {
            await playlists.refresh(id: id, kind: .playlist, session: session)
            throw error
        }
        await playlists.refresh(id: id, kind: .playlist, session: session)
        return true
    }

    private func saveCollection(_ id: String) async throws -> Bool {
        if !removed.isEmpty {
            let ids = removed.sorted()
            guard try await session.mediaProvider.collectionCapabilities(id: id).removeMembers else { throw GusError.forbidden }
            guard await collections.mutate(collectionID: id, verifying: .excludes(ids), {
                try await session.mediaProvider.removeCollectionMembers(id: id, itemIDs: ids)
                return id
            }) else { return false }
            acceptMembership()
            submitted.append(String(localized: "Titles removed."))
        }
        if newName != nil || newOverview != nil {
            guard await collections.saveMetadata(
                id: id,
                name: newName,
                expectedName: originalName,
                overview: newOverview,
                expectedOverview: originalOverview
            ) else { return false }
            originalName = normalizedName
            originalOverview = overview
            submitted.append(String(localized: "Details saved."))
        }
        if cover != .unchanged {
            guard await collections.saveCover(id: id, change: cover, expectedTag: originalCoverTag) else { return false }
            cover = .unchanged
            preview = nil
        }
        return true
    }

    private func acceptMembership() {
        entries.removeAll { removed.contains($0.id) }
        removed = []
        originalOrder = entries.map(\.id)
    }
}
