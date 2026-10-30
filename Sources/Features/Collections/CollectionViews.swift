import SwiftUI

struct CollectionsView: View {
    @Environment(RootNavigationState.self) private var root
    @Environment(SessionStore.self) private var session
    @State private var creating = false
    private var store: CollectionStore {
        root.collectionStore(session: session)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                CollectionFeedback(store: store)
                if store.state == .loading {
                    ProgressView()
                }
                if store.collections.isEmpty, store.state == .loaded {
                    ContentUnavailableView("No Collections", systemImage: "rectangle.stack", description: Text("Create a collection or add a movie to one."))
                }
                LazyVGrid(columns: PosterGrid.columns, spacing: PosterGrid.spacing) {
                    ForEach(store.collections.filter { ContentRatingGate.admitsStored($0.item) }.sorted { $0.item.displayTitle.localizedStandardCompare($1.item.displayTitle) == .orderedAscending }) { collection in
                        CollectionLink(collection: collection)
                            .gusTVFocus(id: collection.id, section: "collections", ids: store.collections.map(\.id), initial: collection.id == store.collections.first?.id, item: collection.item)
                    }
                }
            }.gusTVPagePadding()
        }
        .navigationTitle("Collections")
        .toolbar {
            if CollectionPlatform.canManage && store.capabilities.create {
                ToolbarItem(placement: .primaryAction) { Button("New Collection", systemImage: "plus") { creating = true }.gusIPadIconOnly().collectionShortcut("n") }
            }
        }
        .sheet(isPresented: $creating) { NavigationStack { CollectionEditor() } }
        .task { await store.load() }
        .refreshable { await store.load(force: true) }
    }
}

struct CollectionLink: View {
    @Environment(SessionStore.self) private var session
    let collection: MediaCollection
    var body: some View {
        NavigationLink(value: MediaCollectionRef(id: collection.id, scope: session.references.scope)) {
            PosterCard(title: collection.item.displayTitle, subtitle: String(localized: "Collection"), imageURL: session.mediaProvider.primaryImageURL(for: collection.item, context: .posterGrid), placeholderSymbol: "rectangle.stack")
        }.posterNavigationStyle()
    }
}

/// Discovery loads separately from the movie grid and never replaces its loading state.
struct MovieCollectionsShelf: View {
    @Environment(RootNavigationState.self) private var root
    @Environment(SessionStore.self) private var session
    let libraryID: String?
    private var store: CollectionStore {
        root.collectionStore(session: session)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Collections").font(.title2.bold())
                Spacer()
                NavigationLink("See All", value: CollectionsRef(scope: session.references.scope))
            }
            if store.state == .loading {
                ProgressView()
            }
            if let message = store.discoveryError(libraryID: libraryID) {
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("Retry") { Task { await store.load(force: true); await store.loadLibrary(libraryID) } }
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: PosterGrid.spacing) {
                    ForEach(store.relevant(to: libraryID)) { collection in
                        CollectionLink(collection: collection).frame(width: MediaRailMetrics.itemWidth(for: .poster))
                            .gusTVFocus(id: collection.id, section: "collectionShelf:" + (libraryID ?? "movies"), ids: store.relevant(to: libraryID).map(\.id), item: collection.item)
                    }
                }
                .gusTVRailPadding()
                .tvFocusSection()
            }
            .gusTVRailViewport()
        }
        .task(id: store.revision) { await store.loadLibrary(libraryID) }
    }
}

struct MovieCollectionMemberships: View {
    @Environment(RootNavigationState.self) private var root
    @Environment(SessionStore.self) private var session
    let movieID: String
    private var store: CollectionStore {
        root.collectionStore(session: session)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.memberships(for: movieID).isEmpty {
                Text("Collections").font(.title2.bold())
                ForEach(store.memberships(for: movieID)) { collection in
                    NavigationLink(value: MediaCollectionRef(id: collection.id, scope: session.references.scope)) {
                        Label(collection.item.displayTitle, systemImage: "rectangle.stack")
                    }
                    .mediaItemContextMenu(item: nil, groupName: collection.item.displayTitle, canRemove: CollectionPlatform.canManage && store.capabilities.removeMembers, remove: {
                        _ = await store.mutate { try await session.mediaProvider.removeCollectionMembers(id: collection.id, itemIDs: [movieID]); return nil }
                    })
                }
            }
            if let message = store.errorMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("Retry Collections") { Task { await store.load(force: true) } }
            }
        }.task { await store.load() }
    }
}

struct MediaCollectionDetailView: View {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    private var artworkWidth: CGFloat {
        #if os(iOS)
            widthClass == .compact ? 120 : 140
        #elseif os(tvOS)
            300
        #else
            140
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
    let id: String
    @State private var sort = CollectionSort.serverDefault
    @State private var editing = false
    @State private var adding = false
    @State private var deleting = false
    @State private var loading = true
    private var store: CollectionStore {
        root.collectionStore(session: session)
    }

    private var collection: MediaCollection? {
        store.collection(id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CollectionFeedback(store: store)
                if let collection, ContentRatingGate.admitsStored(collection.item) {
                    HStack(alignment: .top, spacing: 20) {
                        AsyncPoster(url: session.mediaProvider.primaryImageURL(for: collection.item, context: .posterGrid)).frame(width: artworkWidth, height: artworkWidth * 1.5)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(collection.item.displayTitle).font(collectionTitleFont)
                            if collection.membersLoaded {
                                Text("\(admitted(collection).count) titles").foregroundStyle(.secondary)
                            }
                            if !collection.item.genres.isEmpty {
                                Text(collection.item.genres.joined(separator: " / ")).foregroundStyle(.secondary)
                            }
                            if let overview = collection.item.overview, !overview.isEmpty {
                                Text(overview)
                            }
                        }
                    }
                    if collection.membersLoaded {
                        if admitted(collection).isEmpty {
                            ContentUnavailableView("No Titles", systemImage: "film")
                        }
                        memberSection("Movies", members: admitted(collection).filter { $0.type == .movie }, collection: collection)
                        memberSection("Series", members: admitted(collection).filter { $0.type == .series }, collection: collection)
                        memberSection("Other Titles", members: admitted(collection).filter { ![.movie, .series].contains($0.type) }, collection: collection)
                    }
                } else if loading {
                    ProgressView()
                } else {
                    ContentUnavailableView("Collection Unavailable", systemImage: "rectangle.stack", description: Text("Refresh while connected to Jellyfin to load this collection."))
                }
                if let error = store.memberErrors[id] {
                    Text(error); Button("Retry") { Task { await store.loadDetail(id: id, force: true) } }
                }
            }.gusTVPagePadding()
        }
        .navigationTitle(collection?.item.displayTitle ?? String(localized: "Collection"))
        .gusTVSingleContentTitle()
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Sort", selection: $sort) { ForEach(CollectionSort.allCases) { Text($0.title).tag($0) } }
                    if CollectionPlatform.canManage {
                        if store.capabilities.addMembers {
                            Button("Add Movies", systemImage: "plus") { adding = true }
                        }
                        if store.capabilities.editMetadata || store.capabilities.editArtwork {
                            Button("Edit", systemImage: "pencil") { editing = true }.collectionShortcut("e")
                        }
                        if store.permissions(for: id).delete {
                            Button("Delete Collection", systemImage: "trash", role: .destructive) { deleting = true }
                        }
                    }
                } label: { Label("More", systemImage: "ellipsis.circle") }.gusIPadIconOnly().gusTVToolbarIcon().disabled(store.isMutating || collection == nil)
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { CollectionEditor(collectionID: id) } }
        .sheet(isPresented: $adding) { NavigationStack { CollectionMoviePicker(collectionID: id) } }
        .confirmationDialog("Delete Collection?", isPresented: $deleting) {
            Button("Delete Collection", role: .destructive) { Task {
                if await store.mutate({ try await session.mediaProvider.deleteCollection(id: id); return nil }) {
                    dismiss()
                }
            } }
        } message: { Text("This deletes the collection from Jellyfin. Its movies and watched history remain.") }
        .task { await store.load(); await store.loadDetail(id: id); loading = false }
        .refreshable { await store.load(force: true); await store.loadDetail(id: id, force: true) }
    }

    private func admitted(_ collection: MediaCollection) -> [MediaItem] {
        collection.members.filter { ContentRatingGate.admitsStored($0) }
    }

    @ViewBuilder private func memberSection(_ title: LocalizedStringKey, members: [MediaItem], collection: MediaCollection) -> some View {
        if !members.isEmpty {
            Text(title).font(.title2.bold())
            LazyVGrid(columns: PosterGrid.columns, spacing: PosterGrid.spacing) {
                ForEach(sort.sorted(members), id: \.id) { item in
                    NavigationLink(value: ItemRef(item: item)) { PosterCard(item: item, imageURL: session.mediaProvider.primaryImageURL(for: item, context: .posterGrid)) }
                        .posterNavigationStyle()
                        .gusTVFocus(id: item.id ?? "", section: "collection:" + id, ids: sort.sorted(members).compactMap(\.id), item: item)
                        .mediaItemContextMenu(item: item, groupName: collection.item.displayTitle, canRemove: CollectionPlatform.canManage && store.capabilities.removeMembers && !store.isMutating, remove: {
                            if let itemID = item.id {
                                _ = await store.mutate { try await session.mediaProvider.removeCollectionMembers(id: id, itemIDs: [itemID]); return nil }
                            }
                        })
                }
            }
        }
    }
}

struct CollectionFeedback: View {
    let store: CollectionStore
    var body: some View {
        if let message = store.errorMessage {
            Text(message).foregroundStyle(.secondary)
            Button("Refresh Collections") { Task { await store.load(force: true) } }
            Button("Dismiss Error") { store.clearError() }
        }
        if let message = store.statusMessage {
            Text(message).foregroundStyle(.secondary)
        }
    }
}
