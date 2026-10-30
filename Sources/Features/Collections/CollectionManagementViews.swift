import SwiftUI

struct CollectionEditor: View {
    @Environment(RootNavigationState.self) private var root
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    var collectionID: String?
    @State private var name = ""
    @State private var overview = ""
    @State private var importing = false
    @State private var artwork: Data?
    @State private var artworkError: String?
    @State private var initialized = false
    @State private var createdID: String?
    private var store: CollectionStore {
        root.collectionStore(session: session)
    }

    private var canSave: Bool {
        let creating = collectionID == nil && createdID == nil
        let allowed = creating ? store.capabilities.create : store.capabilities.permitsEdit(artworkIncluded: artwork != nil)
        let validName = (!creating && !store.capabilities.editMetadata) || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return allowed && validName && !store.isMutating && CollectionPlatform.canManage
    }

    var body: some View {
        Form {
            CollectionFeedback(store: store)
            if collectionID == nil || store.capabilities.editMetadata {
                TextField("Name", text: $name)
                if collectionID != nil {
                    TextField("Description", text: $overview, axis: .vertical).lineLimit(3 ... 8)
                }
            }
            if collectionID != nil && store.capabilities.editArtwork {
                Button("Change Artwork", systemImage: "photo") { importing = true }
                if artwork != nil {
                    Text("New artwork selected")
                }
                if let artworkError {
                    Text(artworkError).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(collectionID == nil ? "New Collection" : "Edit Collection")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isMutating) }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(!canSave) }
        }
        .collectionArtworkImporter(isPresented: $importing) { result in
            do { artwork = try CollectionArtwork.jpeg(from: result.get()); artworkError = nil }
            catch { artworkError = error.localizedDescription }
        }
        .task {
            guard !initialized else { return }; initialized = true
            await store.load()
            if let collectionID {
                await store.loadDetail(id: collectionID); name = store.collection(collectionID)?.item.name ?? ""; overview = store.collection(collectionID)?.item.overview ?? ""
            }
        }
        .interactiveDismissDisabled(store.isMutating)
    }

    private func save() async {
        guard canSave else { return }
        if let id = collectionID ?? createdID {
            if await store.saveEdits(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), overview: overview, artwork: artwork) {
                artwork = nil
                dismiss()
            }
            return
        }
        let saved = await store.mutate {
            let id = try await session.mediaProvider.createCollection(name: name.trimmingCharacters(in: .whitespacesAndNewlines), itemIDs: [])
            createdID = id
            return id
        }
        if saved {
            dismiss()
        }
    }
}

struct AddToMediaCollectionView: View {
    @Environment(RootNavigationState.self) private var root
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    @State private var name = ""
    private var store: CollectionStore {
        root.collectionStore(session: session)
    }

    var body: some View {
        List {
            CollectionFeedback(store: store)
            Section("Choose Collection") {
                ForEach(store.collections.filter { ContentRatingGate.admitsStored($0.item) }) { collection in
                    let existing = collection.members.contains { $0.id == item.id }
                    Button {
                        guard let id = item.id else { return }
                        Task {
                            if await store.mutate({ try await session.mediaProvider.addCollectionMembers(id: collection.id, itemIDs: [id]); return nil }) {
                                dismiss()
                            }
                        }
                    } label: { HStack {
                        Text(collection.item.displayTitle); if existing {
                            Spacer(); Image(systemName: "checkmark")
                        }
                    } }
                    .disabled(existing || !store.capabilities.addMembers || store.isMutating || !CollectionPlatform.canAddMembers)
                }
            }
            if store.capabilities.create && CollectionPlatform.canManage {
                Section("New Collection") {
                    TextField("Name", text: $name)
                    Button("Create and Add") { Task {
                        guard let id = item.id else { return }
                        if await store.mutate({ try await session.mediaProvider.createCollection(name: name.trimmingCharacters(in: .whitespacesAndNewlines), itemIDs: [id]) }) {
                            dismiss()
                        }
                    } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isMutating)
                }
            }
        }
        .navigationTitle("Add to Collection")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isMutating) } }
        .task { await store.load() }
    }
}

struct CollectionMoviePicker: View {
    @Environment(RootNavigationState.self) private var root
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let collectionID: String
    @State private var search: SearchStore?
    @State private var query = ""
    @State private var selected: Set<String> = []
    private var store: CollectionStore {
        root.collectionStore(session: session)
    }

    var body: some View {
        List {
            CollectionFeedback(store: store)
            if let search {
                if search.state == .loading {
                    ProgressView()
                }
                if case let .failed(message) = search.state {
                    Text(message); Button("Retry") { Task { await search.search(query) } }
                }
                ForEach(search.results.filter { $0.type == .movie && ContentRatingGate.admitsStored($0) }, id: \.id) { item in
                    if let id = item.id {
                        let existing = store.collection(collectionID)?.members.contains { $0.id == id } == true
                        Button {
                            if selected.contains(id) {
                                selected.remove(id)
                            } else {
                                selected.insert(id)
                            }
                        } label: {
                            HStack {
                                Text(item.displayTitle); Spacer(); if existing || selected.contains(id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }.disabled(existing || store.isMutating)
                    }
                }
                if search.canLoadMore {
                    Button("Load More") { Task { await search.continueSearching() } }.disabled(search.isLoadingNextPage)
                }
                if let error = search.pageError {
                    Text(error)
                }
            }
        }
        .searchable(text: $query, prompt: "Search Movies")
        .task(id: query) {
            if search == nil {
                search = SearchStore(session: session, includeTypes: [.movie])
            }
            do { try await Task.sleep(for: .milliseconds(300)); await search?.search(query) } catch {}
        }
        .navigationTitle("Add Movies")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isMutating) }
            ToolbarItem(placement: .confirmationAction) { Button("Add") { Task {
                if await store.mutate({ try await session.mediaProvider.addCollectionMembers(id: collectionID, itemIDs: selected.sorted()); return nil }) {
                    dismiss()
                }
            } }.disabled(selected.isEmpty || store.isMutating || !store.capabilities.addMembers || !CollectionPlatform.canManage) }
        }
    }
}
