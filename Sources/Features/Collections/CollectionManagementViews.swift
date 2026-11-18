import SwiftUI

struct CollectionEditor: View {
    @Environment(RootNavigationState.self) private var root
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    var collectionID: String?
    var onCreate: () -> Void = {}
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
        guard createdID == nil else { return false }
        let creating = collectionID == nil
        let allowed = creating ? store.capabilities.create : store.capabilities.permitsEdit(artworkIncluded: artwork != nil)
        let validName = (!creating && !store.capabilities.editMetadata) || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return allowed && validName && store.canSubmitMutations && CollectionPlatform.canManage
    }

    var body: some View {
        Form {
            CollectionFeedback(store: store)
            if let createdID {
                if let collection = store.collection(createdID), ContentRatingGate.admitsStored(collection.item) {
                    Text(collection.item.displayTitle)
                } else if !store.isMutating && !store.needsMutationReview {
                    Text("This collection is no longer visible on Jellyfin.")
                }
            } else if collectionID == nil || store.capabilities.editMetadata {
                TextField("Name", text: $name)
                if collectionID == nil {
                    Text("Collections are shared on this Jellyfin server.").font(.footnote).foregroundStyle(.secondary)
                }
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
            ToolbarItem(placement: .confirmationAction) {
                if let createdID {
                    Button("Done") {
                        if store.collection(createdID) != nil {
                            onCreate()
                        }
                        dismiss()
                    }.disabled(!store.canSubmitMutations)
                } else {
                    Button("Save") { Task { await save() } }.disabled(!canSave)
                }
            }
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
        if let id = collectionID {
            if await store.saveEdits(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), overview: overview, artwork: artwork) {
                artwork = nil
                dismiss()
            }
            return
        }
        let saved = await store.mutate(verifying: .contains([])) {
            let id = try await session.mediaProvider.createCollection(name: name.trimmingCharacters(in: .whitespacesAndNewlines), itemIDs: [])
            createdID = id
            return id
        }
        if saved {
            onCreate()
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

    private var canAddItem: Bool {
        item.id != nil && ContentRatingGate.admitsStored(item) &&
            (item.isBookFormat ? CollectionPlatform.canManage : CollectionPlatform.canAddMembers)
    }

    @State private var createdID: String?

    var body: some View {
        List {
            CollectionFeedback(store: store)
            if let createdID {
                if !store.isMutating, !store.needsMutationReview {
                    // Creation returned an ID. If the seed was missing after readback,
                    // offer a membership change on that same collection.
                    if let collection = store.collection(createdID), ContentRatingGate.admitsStored(collection.item) {
                        Section {
                            Text(collection.item.displayTitle)
                            if collection.members.contains(where: { $0.id == item.id }) {
                                Button("Done") { dismiss() }
                            } else {
                                Button("Add") { Task { await add(to: collection) } }
                                    .disabled(!canAdd(to: collection))
                            }
                        }
                    } else {
                        Text("This collection is no longer visible on Jellyfin.")
                        Button("Done") { dismiss() }
                    }
                }
            } else {
                Section("Choose Collection") {
                    ForEach(store.collections.filter { ContentRatingGate.admitsStored($0.item) }) { collection in
                        Button {
                            Task { await add(to: collection) }
                        } label: {
                            HStack {
                                Text(collection.item.displayTitle)
                                if collection.members.contains(where: { $0.id == item.id }) {
                                    Spacer(); Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(!canAdd(to: collection))
                    }
                }
                if store.capabilities.create && CollectionPlatform.canManage {
                    Section {
                        TextField("Name", text: $name)
                        Button("Create and Add") { Task { await createAndAdd() } }
                            .disabled(name.trimmedNilIfEmpty == nil || !store.canSubmitMutations || !canAddItem)
                    } header: { Text("New Collection") } footer: { Text("Collections are shared on this Jellyfin server.") }
                }
            }
        }
        .navigationTitle("Add to Collection")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isMutating) } }
        .task { await store.load() }
        .interactiveDismissDisabled(store.isMutating)
    }

    private func canAdd(to collection: MediaCollection) -> Bool {
        canAddItem && store.canSubmitMutations && store.capabilities.addMembers &&
            collection.membersLoaded && store.memberErrors[collection.id] == nil &&
            !collection.members.contains { $0.id == item.id }
    }

    private func add(to collection: MediaCollection) async {
        guard let id = item.id, let current = store.collection(collection.id),
              ContentRatingGate.admitsStored(current.item), canAdd(to: current) else { return }
        if await store.mutate(collectionID: current.id, verifying: .contains([id]), {
            try await session.mediaProvider.addCollectionMembers(id: current.id, itemIDs: [id])
            return current.id
        }) {
            dismiss()
        }
    }

    private func createAndAdd() async {
        guard createdID == nil, canAddItem, let id = item.id, let title = name.trimmedNilIfEmpty,
              store.capabilities.create, CollectionPlatform.canManage else { return }
        if await store.mutate(verifying: .contains([id]), {
            let collectionID = try await session.mediaProvider.createCollection(name: title, itemIDs: [id])
            createdID = collectionID
            return collectionID
        }) {
            dismiss()
        }
    }
}

struct CollectionTitlePicker: View {
    @Environment(RootNavigationState.self) private var root
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let collectionID: String
    @State private var format: CollectionFormat
    @State private var query = ""
    @State private var selected: [String: MediaItem] = [:]
    @State private var searches: [CollectionFormat: SearchStore] = [:]

    private struct SearchInput: Equatable {
        let format: CollectionFormat
        let query: String
    }

    init(collectionID: String, initialFormat: CollectionFormat) {
        self.collectionID = collectionID
        _format = State(initialValue: initialFormat == .all ? .movies : initialFormat)
    }

    private var store: CollectionStore {
        root.collectionStore(session: session)
    }

    private var existing: Set<String> {
        Set(store.collection(collectionID)?.members.compactMap(\.id) ?? [])
    }

    private var selectedIDs: [String] {
        selected.filter { !existing.contains($0.key) && ContentRatingGate.admitsStored($0.value) }.keys.sorted()
    }

    private var canAdd: Bool {
        !selectedIDs.isEmpty && store.canSubmitMutations && store.capabilities.addMembers &&
            CollectionPlatform.canManage && store.collection(collectionID)?.membersLoaded == true && store.memberErrors[collectionID] == nil
    }

    var body: some View {
        let input = SearchInput(format: format, query: query)
        List {
            CollectionFeedback(store: store)
            Picker("Format", selection: $format) {
                ForEach(CollectionFormat.allCases.filter { $0.mediaType != nil }, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if let type = format.mediaType, let search = searches[format] {
                CollectionSearchResults(search: search, type: type, query: query, existing: existing, selected: $selected)
                    .disabled(store.isMutating)
            }
        }
        .searchable(text: $query, prompt: "Search Titles")
        .task(id: input) {
            guard let type = input.format.mediaType else { return }
            let search: SearchStore
            if let cached = searches[input.format] {
                search = cached
            } else {
                search = SearchStore(session: session, includeTypes: [type])
                searches[input.format] = search
            }
            do {
                try await Task.sleep(for: .milliseconds(300))
                await search.search(input.query)
            } catch {}
        }
        .navigationTitle("Add Titles")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isMutating) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    Task {
                        guard canAdd else { return }
                        let ids = selectedIDs
                        if await store.mutate(collectionID: collectionID, verifying: .contains(ids), {
                            try await session.mediaProvider.addCollectionMembers(id: collectionID, itemIDs: ids)
                            return collectionID
                        }) {
                            dismiss()
                        }
                    }
                }
                .disabled(!canAdd)
            }
        }
        .interactiveDismissDisabled(store.isMutating)
    }
}

/// A format change replaces only the search and its pagination. Selection is
/// owned by the picker so one Add can include titles from several formats.
private struct CollectionSearchResults: View {
    let search: SearchStore
    let type: MediaItemType
    let query: String
    let existing: Set<String>
    @Binding var selected: [String: MediaItem]

    var body: some View {
        if search.query == query.trimmingCharacters(in: .whitespacesAndNewlines), !search.query.isEmpty {
            if search.state == .loading {
                ProgressView()
            } else if case let .failed(message) = search.state {
                Text(message)
                Button("Retry") { Task { await search.search(query) } }
            } else if search.state == .loaded, search.results.isEmpty, !search.canLoadMore {
                ContentUnavailableView.search(text: search.query)
            }
            ForEach(search.results, id: \.id) { item in
                if let id = item.id, item.type == type, ContentRatingGate.admitsStored(item) {
                    Button {
                        if selected[id] == nil {
                            selected[id] = item
                        } else {
                            selected[id] = nil
                        }
                    } label: {
                        HStack {
                            Text(item.displayTitle)
                            Spacer()
                            if existing.contains(id) || selected[id] != nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(existing.contains(id))
                    .accessibilityAddTraits(existing.contains(id) || selected[id] != nil ? .isSelected : [])
                }
            }
            if search.canLoadMore {
                Button("Load More") { Task { await search.continueSearching() } }.disabled(search.isLoadingNextPage)
            }
            if let error = search.pageError ?? search.refreshError {
                Text(error)
            }
        }
    }
}
