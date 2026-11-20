import SwiftUI

struct CollectionsView: View {
    @Environment(RootNavigationState.self) private var root
    @Environment(SessionStore.self) private var session
    @State private var creating = false
    @State private var format: CollectionFormat
    let initialFormat: CollectionFormat
    let movieLibraryID: String?

    init(initialFormat: CollectionFormat = .all, movieLibraryID: String? = nil) {
        self.movieLibraryID = movieLibraryID
        self.initialFormat = initialFormat
        _format = State(initialValue: initialFormat)
    }

    private var store: CollectionStore {
        root.collectionStore(session: session)
    }

    var body: some View {
        let libraryID = format == .movies ? movieLibraryID : nil
        let libraryReady = libraryID.map(store.hasLibraryMembership) ?? true
        let libraryError = libraryID.flatMap { store.libraryErrors[$0] }
        let finishedFiltering = format == .all || (store.hasCompleteMembershipCatalog && libraryReady)
        let eligible = libraryID.map { store.relevant(to: $0) } ?? store.collections.filter { format.includes($0) }
        let visible = eligible.sorted {
            $0.item.displayTitle.localizedStandardCompare($1.item.displayTitle) == .orderedAscending
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Format", selection: $format) {
                    ForEach(CollectionFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                CollectionFeedback(store: store)
                if let libraryError, let libraryID {
                    Text(libraryError).foregroundStyle(.secondary)
                    Button("Retry") { Task { await store.loadLibrary(libraryID) } }
                }
                if store.state == .loading || (store.state == .loaded && !finishedFiltering && store.errorMessage == nil && libraryError == nil) {
                    ProgressView()
                }
                if visible.isEmpty, store.state == .loaded, finishedFiltering, libraryError == nil {
                    if format == .all {
                        ContentUnavailableView("No Collections", systemImage: "rectangle.stack")
                    } else {
                        ContentUnavailableView("No Matching Collections", systemImage: "rectangle.stack", description: Text("Choose All to see every collection, including empty ones."))
                    }
                }
                LazyVGrid(columns: PosterGrid.columns, spacing: PosterGrid.spacing) {
                    ForEach(visible) { collection in
                        CollectionLink(collection: collection, format: format == .all ? initialFormat : format)
                            .gusTVFocus(id: collection.id, section: "collections", ids: visible.map(\.id), initial: collection.id == visible.first?.id, item: collection.item)
                    }
                }
            }.gusTVPagePadding()
        }
        .gusVisibleContent(.collections, isLoading: store.state.isLoading)
        .navigationTitle("Collections")
        .toolbar {
            if CollectionPlatform.canManage && store.capabilities.create {
                ToolbarItem(placement: .primaryAction) { Button("New Collection", systemImage: "plus") { creating = true }.disabled(!store.canSubmitMutations).gusIPadIconOnly().collectionShortcut("n") }
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack { CollectionEditor(onCreate: { format = .all }) }
        }
        .task(id: libraryID == nil ? nil : store.revision) { await store.loadLibrary(libraryID) }
        .refreshable {
            await store.load(force: true)
            if let libraryID {
                await store.loadLibrary(libraryID)
            }
        }
    }
}

struct CollectionLink: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var limit = ContentRatingGate.Limit.off
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false
    let collection: MediaCollection
    var format = CollectionFormat.all
    var body: some View {
        let urls = collection.coverURLs(using: session.mediaProvider, limit: limit, hideUnrated: hideUnrated)
        NavigationLink(value: MediaCollectionRef(id: collection.id, scope: session.references.scope, format: format)) {
            PosterCard(title: collection.item.displayTitle, subtitle: String(localized: "Collection"), statusItem: collection.item, imageURL: urls.first, placeholderSymbol: "rectangle.stack", fallbackURLs: Array(urls.dropFirst()))
        }.posterNavigationStyle()
    }
}

struct ItemCollectionMemberships: View {
    @Environment(RootNavigationState.self) private var root
    @Environment(SessionStore.self) private var session
    let itemID: String
    let format: CollectionFormat
    private var store: CollectionStore {
        root.collectionStore(session: session)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.memberships(for: itemID).isEmpty {
                Text("Collections").font(.title2.bold())
                ForEach(store.memberships(for: itemID)) { collection in
                    NavigationLink(value: MediaCollectionRef(id: collection.id, scope: session.references.scope, format: format)) {
                        Label(collection.item.displayTitle, systemImage: "rectangle.stack")
                    }
                    .mediaItemContextMenu(item: nil, groupName: collection.item.displayTitle, canRemove: store.capabilities.removeMembers && store.canSubmitMutations && store.memberErrors[collection.id] == nil, remove: {
                        await store.mutate(collectionID: collection.id, verifying: .excludes([itemID])) {
                            try await session.mediaProvider.removeCollectionMembers(id: collection.id, itemIDs: [itemID])
                            return collection.id
                        }
                    })
                }
            }
            if store.needsMutationReview || store.isMutating {
                CollectionFeedback(store: store)
            } else if let message = store.errorMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("Retry Collections") { Task { await store.load(force: true) } }
            }
        }
        .gusVisibleContent(.collections, isLoading: store.state.isLoading)
        .task { await store.load() }
    }
}

struct MediaCollectionDetailView: View {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    private var artworkWidth: CGFloat {
        #if os(iOS)
            widthClass == .compact ? 200 : 240
        #elseif os(tvOS)
            300
        #else
            240
        #endif
    }

    private var collectionTitleFont: Font {
        #if os(iOS)
            widthClass == .compact ? .title.bold() : .largeTitle.bold()
        #else
            .largeTitle.bold()
        #endif
    }

    @Environment(RootNavigationState.self) private var root
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var limit = ContentRatingGate.Limit.off
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false
    let id: String
    var format = CollectionFormat.all
    @State private var sort = CollectionSort.serverDefault
    @State private var editing = false
    @State private var adding = false
    @State private var deleting = false
    @State private var loading = true
    private var store: CollectionStore {
        root.collectionStore(session: session)
    }

    private var collection: MediaCollection? {
        guard let collection = store.collection(id), ContentRatingGate.admitsStored(collection.item) else { return nil }
        return collection
    }

    var body: some View {
        ArtworkDetailPage {
            if let collection {
                let urls = collection.coverURLs(using: session.mediaProvider, limit: limit, hideUnrated: hideUnrated)
                DetailCoverHeader(maximumCoverWidth: artworkWidth) {
                    ArtworkTile(url: urls.first, contentMode: .fit, placeholderSymbol: "rectangle.stack", fallbackURLs: Array(urls.dropFirst()))

                } summary: {
                    Text(collection.item.displayTitle).font(collectionTitleFont).accessibilityAddTraits(.isHeader)
                    if collection.membersLoaded {
                        Text("\(admitted(collection).count) titles").foregroundStyle(.secondary)
                    }
                    if !collection.item.genres.isEmpty {
                        Text(collection.item.genres.joined(separator: " / ")).foregroundStyle(.secondary)
                    }
                    if let overview = collection.item.overview {
                        DetailSynopsis(title: collection.item.displayTitle, overview: overview)
                    }
                    #if os(tvOS)
                        collectionActions
                    #endif
                }
                #if os(tvOS)
                .focusSection()
                #endif
            }
        } sections: {
            CollectionFeedback(store: store)
            if let collection {
                let members = admitted(collection)
                if collection.membersLoaded {
                    if members.isEmpty {
                        ContentUnavailableView("No Titles", systemImage: "rectangle.stack")
                    }
                    memberSection("Movies", members: members.filter { $0.type == .movie }, collection: collection)
                    memberSection("Series", members: members.filter { $0.type == .series }, collection: collection)
                    memberSection("Books", members: members.filter { $0.type == .book }, collection: collection)
                    memberSection("Audiobooks", members: members.filter { $0.type == .audioBook }, collection: collection)
                    memberSection("Other Titles", members: members.filter { ![.movie, .series, .book, .audioBook].contains($0.type) }, collection: collection)
                }
            } else if loading {
                ProgressView()
            } else {
                ContentUnavailableView("Collection Unavailable", systemImage: "rectangle.stack", description: Text("Refresh while connected to Jellyfin to load this collection."))
            }
            if let error = store.memberErrors[id] {
                Text(error); Button("Retry") { Task { await store.loadDetail(id: id, force: true) } }
            }
        }
        .navigationTitle(collection?.item.displayTitle ?? String(localized: "Collection"))
        .toolbarTitleDisplayMode(.inline)
        .gusTVDetailTitle()
        .toolbar {
            #if !os(tvOS)
                ToolbarItem { collectionActions }
            #endif
        }
        .gusTVTask(isPresented: $editing) { NavigationStack { MediaListEditor(list: .collection(id)) } }
        .sheet(isPresented: $adding) { NavigationStack { CollectionTitlePicker(collectionID: id, initialFormat: format) } }
        .confirmationDialog("Delete Collection?", isPresented: $deleting) {
            Button("Delete Collection", role: .destructive) { Task {
                if await store.mutate(collectionID: id, verifying: .deleted, { try await session.mediaProvider.deleteCollection(id: id); return id }) {
                    dismiss()
                }
            } }
        } message: { Text("This deletes the shared collection from Jellyfin. Its titles and their progress are kept.") }
        .gusVisibleContent(.collections, isLoading: store.state.isLoading)
        .task { await store.load(); await store.loadDetail(id: id); loading = false }
        .refreshable { await store.load(force: true); await store.loadDetail(id: id, force: true) }
    }

    private var collectionActions: some View {
        Menu {
            Picker("Sort", selection: $sort) { ForEach(CollectionSort.allCases) { Text($0.title).tag($0) } }
            if store.capabilities.editMetadata || store.capabilities.editArtwork || store.capabilities.removeMembers {
                Button("Edit", systemImage: "pencil") { editing = true }
                    .collectionShortcut("e").disabled(!store.canSubmitMutations)
            }
            if CollectionPlatform.canManage {
                if store.capabilities.addMembers {
                    Button("Add Titles", systemImage: "plus") { adding = true }
                        .disabled(!store.canSubmitMutations || collection?.membersLoaded != true || store.memberErrors[id] != nil)
                }
                if store.permissions(for: id).delete {
                    Button("Delete Collection", systemImage: "trash", role: .destructive) { deleting = true }.disabled(!store.canSubmitMutations)
                }
            }
        } label: { GusToolbarLabel("More", systemImage: "ellipsis.circle", tvSystemImage: "ellipsis") }.gusIPadIconOnly().gusTVToolbarIcon().accessibilityLabel("More").disabled(collection == nil)
    }

    private func admitted(_ collection: MediaCollection) -> [MediaItem] {
        collection.members.filter { ContentRatingGate.admitsStored($0) }
    }

    @ViewBuilder private func memberSection(_ title: LocalizedStringKey, members: [MediaItem], collection: MediaCollection) -> some View {
        if !members.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.title2.bold())
                LazyVGrid(columns: PosterGrid.columns, spacing: PosterGrid.spacing) {
                    ForEach(sort.sorted(members), id: \.id) { item in
                        let urls = session.mediaProvider.artworkURLs(for: item, request: .init(role: item.coverArtworkRole, maxWidth: 360))
                        NavigationLink(value: ItemRef(item: item)) { PosterCard(item: item, imageURL: urls.first, fallbackURLs: Array(urls.dropFirst())) }
                            .posterNavigationStyle()
                            .gusTVFocus(id: item.id ?? "", section: "collection:" + id, ids: sort.sorted(members).compactMap(\.id), item: item)
                            .mediaItemContextMenu(item: item, groupName: collection.item.displayTitle, canRemove: store.capabilities.removeMembers && store.canSubmitMutations && store.memberErrors[id] == nil, remove: {
                                if let itemID = item.id {
                                    await store.mutate(collectionID: id, verifying: .excludes([itemID])) {
                                        try await session.mediaProvider.removeCollectionMembers(id: id, itemIDs: [itemID])
                                        return id
                                    }
                                }
                            })
                    }
                }
            }
        }
    }
}

struct CollectionFeedback: View {
    let store: CollectionStore
    var body: some View {
        if store.actionOutcome == .pending {
            ProgressView("Updating…")
        } else if let outcome = store.actionOutcome {
            Text(outcome.accessibilityValue).font(.caption).foregroundStyle(.secondary)
        }
        if let message = store.errorMessage {
            Text(message).foregroundStyle(.secondary)
            Button("Refresh Collections") { Task { await store.load(force: true) } }
            if !store.needsMutationReview {
                Button("Dismiss Error") { store.clearError() }
            }
        } else if store.needsMutationReview {
            Button("Refresh Collections") { Task { await store.load(force: true) } }
        }
        if store.needsMutationReview {
            if store.canKeepCurrentServerState {
                Section("Review Server Collections") {
                    if store.reviewCollectionID != nil {
                        if let collection = store.reviewedCollection, ContentRatingGate.admitsStored(collection.item) {
                            Text(collection.item.displayTitle).font(.headline)
                            reviewMembers(collection)
                        } else {
                            Text("This collection is no longer visible on Jellyfin.")
                        }
                    } else {
                        ForEach(store.collections.filter { ContentRatingGate.admitsStored($0.item) }) { collection in
                            NavigationLink(collection.item.displayTitle) {
                                List { reviewMembers(collection) }.navigationTitle(collection.item.displayTitle)
                            }
                        }
                    }
                }
                Button("Use Current Server State") { store.keepCurrentServerState() }
            }
        }
        if let message = store.statusMessage {
            Text(message).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func reviewMembers(_ collection: MediaCollection) -> some View {
        let members = ContentRatingGate.filter(collection.members)
        if members.isEmpty {
            Text("No Titles").foregroundStyle(.secondary)
        } else {
            ForEach(members, id: \.id) { member in Text(member.displayTitle) }
        }
    }
}
