import SwiftUI

/// Movie discovery and its paginated grid keep independent load states.
struct LibraryGridView: View {
    @Environment(RootNavigationState.self) private var navigationState
    @Environment(SessionStore.self) private var session
    let scope: LibraryGridScope
    @State private var store: LibraryStore?
    private var showsList: Bool {
        get { navigationState.libraryListModes[scope.storeIdentity, default: false] }
        nonmutating set { navigationState.libraryListModes[scope.storeIdentity] = newValue }
    }

    private var showsPhotoAlbums: Bool {
        get { navigationState.photoAlbumModes[scope.storeIdentity, default: false] }
        nonmutating set { navigationState.photoAlbumModes[scope.storeIdentity] = newValue }
    }

    private var photoAlbumsSelection: Binding<Bool> {
        Binding(get: { showsPhotoAlbums }, set: { showsPhotoAlbums = $0 })
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    init(library: MediaItem) {
        scope = .library(library)
    }

    init(scope: LibraryGridScope) {
        self.scope = scope
    }

    private var isMovies: Bool {
        switch scope {
        case let .library(item): item.collectionType == .movies
        case let .category(category): category == .movies
        case .photoLibrary, .musicLibrary, .latest: false
        }
    }

    private var isPhotos: Bool {
        switch scope {
        case let .library(item): item.collectionType == .photos
        case let .category(category): category == .photos
        case .photoLibrary: true
        case .musicLibrary, .latest: false
        }
    }

    private var isMusic: Bool {
        switch scope {
        case let .library(item): item.collectionType == .music
        case let .category(category): category == .music
        case .musicLibrary: true
        case .photoLibrary, .latest: false
        }
    }

    private var usesMusicLayout: Bool {
        #if os(iOS)
            isMusic && (widthClass == .compact || DeviceIdentity.usesIPadPresentation)
        #else
            false
        #endif
    }

    private var effectiveScope: LibraryGridScope {
        #if os(iOS)
            if usesMusicLayout {
                return .musicLibrary(parentID: scope.parentID)
            }
            if isPhotos, widthClass == .compact || DeviceIdentity.usesIPadPresentation {
                return .photoLibrary(parentID: scope.parentID, albums: showsPhotoAlbums)
            }
        #endif
        return scope
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                #if os(tvOS)
                    HStack {
                        Text(scope.title).font(.largeTitle.bold())
                        Spacer()
                        if let store {
                            LibraryFilterMenu(store: store).disabled(store.isLoading)
                        }
                    }
                    .focusSection()
                    .padding(.bottom, 24)
                #endif
                if isMovies {
                    MovieCollectionsShelf(libraryID: scope.parentID)
                }
                if let store {
                    LoadingStateView(state: store.state, isEmpty: store.items.isEmpty && !store.canLoadMore, emptyTitle: "Empty Library", emptySymbol: "rectangle.on.rectangle", retryAction: { Task { await store.load() } }) {
                        grid(store)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .gusTVPagePadding()
            .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .gusTVBrowseViewport()
        .navigationTitle(scope.title)
        .gusTVDetailTitle()
        .toolbar {
            #if !os(tvOS)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsList.toggle()
                    } label: {
                        Label(showsList ? "Grid" : "List", systemImage: showsList ? "square.grid.2x2" : "list.bullet")
                    }
                    .accessibilityIdentifier("Library.displayMode")
                    .gusIPadIconOnly()
                    .gusIPhoneOrIPadOnly()
                }
                if let store {
                    ToolbarItem { LibraryFilterMenu(store: store).disabled(store.isLoading) }
                }
            #endif
        }
        .safeAreaInset(edge: .top) {
            if isPhotos {
                Picker("Photos", selection: photoAlbumsSelection) {
                    Text("All Photos").tag(false)
                    Text("Albums").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24).padding(.vertical, 8)
                .background(.background)
                .gusIPhoneOrIPadOnly()
            }
        }
        .task(id: effectiveScope.storeIdentity) { store = navigationState.libraryStore(for: effectiveScope, session: session) }
        .scrollPosition(id: navigationState.scrollBinding(for: "library:" + scope.storeIdentity))
        .lookToScroll()
        .refreshable {
            await store?.load()
            if isMovies {
                await navigationState.collectionStore(session: session).load(force: true); await navigationState.collectionStore(session: session).loadLibrary(scope.parentID)
            }
        }
    }

    @ViewBuilder private func grid(_ store: LibraryStore) -> some View {
        if usesMusicLayout {
            musicContent(store)
        } else if showsList {
            LazyVStack(spacing: 0) {
                ForEach(store.items, id: \.id) { item in
                    MediaItemNavigationLink(item: item) { MediaLibraryRow(item: item) }
                        .buttonStyle(.plain)
                        .mediaItemContextMenu(item: item)
                        .id(ItemRef(item: item).id)
                        .task { await store.loadMoreIfNeeded(currentItem: item) }
                    Divider()
                }
                if let error = store.pageError {
                    Text(error).foregroundStyle(.secondary)
                }
                if store.canLoadMore {
                    Button("Continue Searching") { Task { await store.continueSearching() } }
                        .disabled(store.isLoadingNextPage).frame(minHeight: 44)
                }
                if store.isLoadingNextPage {
                    ProgressView()
                }
            }
            .scrollTargetLayout()
        } else {
            posterGrid(store)
        }
    }

    private func musicContent(_ store: LibraryStore) -> some View {
        let albums = store.items.filter { $0.type == .musicAlbum }
        let artists = store.items.filter { $0.type == .musicArtist }
        return VStack(alignment: .leading, spacing: 24) {
            ViewThatFits(in: .horizontal) {
                if usesMusicColumns && !artists.isEmpty {
                    HStack(alignment: .top, spacing: 32) {
                        musicAlbums(albums, store: store).frame(minWidth: 360, maxWidth: .infinity)
                        musicArtists(artists, store: store).frame(width: 240)
                    }
                }
                VStack(alignment: .leading, spacing: 24) {
                    musicAlbums(albums, store: store)
                    if !artists.isEmpty {
                        musicArtists(artists, store: store)
                    }
                }
            }
            if let error = store.pageError {
                Text(error).foregroundStyle(.secondary)
            }
            if store.canLoadMore {
                Button("Continue Searching") { Task { await store.continueSearching() } }
                    .disabled(store.isLoadingNextPage).frame(minHeight: 44)
            }
            if store.isLoadingNextPage {
                ProgressView()
            }
        }
        .scrollTargetLayout()
    }

    private var usesMusicColumns: Bool {
        #if os(iOS)
            DeviceIdentity.usesIPadPresentation && widthClass == .regular && !dynamicTypeSize.isAccessibilitySize
        #else
            false
        #endif
    }

    private func musicAlbums(_ albums: [MediaItem], store: LibraryStore) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if usesMusicColumns {
                Text("Albums").font(.title3.bold()).accessibilityAddTraits(.isHeader)
            }
            if showsList {
                LazyVStack(spacing: 0) {
                    ForEach(albums, id: \.id) { album in
                        musicRow(album, subtitle: musicSubtitle(album), store: store)
                    }
                }
            } else {
                LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: PosterGrid.spacing) {
                    ForEach(albums, id: \.id) { album in
                        NavigationLink(value: ItemRef(item: album)) {
                            PosterCard(title: album.displayTitle, subtitle: musicSubtitle(album), imageURL: session.mediaProvider.primaryImageURL(for: album, context: .posterGrid), aspectRatio: 1, placeholderSymbol: "music.note")
                        }
                        .posterNavigationStyle()
                        .mediaItemContextMenu(item: album)
                        .id(ItemRef(item: album).id)
                        .task { await store.loadMoreIfNeeded(currentItem: album) }
                    }
                }
            }
        }
    }

    private func musicArtists(_ artists: [MediaItem], store: LibraryStore) -> some View {
        VStack(alignment: .leading, spacing: usesMusicColumns ? 16 : 24) {
            if !artists.isEmpty {
                Text("Artists").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                LazyVStack(spacing: 0) {
                    ForEach(artists, id: \.id) { artist in
                        musicRow(artist, subtitle: nil, store: store)
                    }
                }
            }
        }
    }

    private func musicSubtitle(_ album: MediaItem) -> String? {
        let fields = [album.albumArtist ?? album.artists.first, album.productionYear.map(String.init)].compactMap { $0 }
        return fields.isEmpty ? nil : fields.joined(separator: " · ")
    }

    private func musicRow(_ item: MediaItem, subtitle: String?, store: LibraryStore) -> some View {
        NavigationLink(value: ItemRef(item: item)) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayTitle).foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .mediaItemContextMenu(item: item)
        .id(ItemRef(item: item).id)
        .task { await store.loadMoreIfNeeded(currentItem: item) }
    }

    private func posterGrid(_ store: LibraryStore) -> some View {
        LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: PosterGrid.spacing) {
            ForEach(store.items, id: \.id) { item in
                MediaItemNavigationLink(item: item) { PosterCard(item: item, imageURL: session.mediaProvider.primaryImageURL(for: item, context: .posterGrid)) }
                    .id(ItemRef(item: item).id)
                    .posterNavigationStyle()
                    .mediaItemContextMenu(item: item)
                    .gusTVFocus(id: ItemRef(item: item).id, section: "library:" + scope.storeIdentity, ids: store.items.map { ItemRef(item: $0).id }, initial: item.id == store.items.first?.id, item: item)
                    .task { await store.loadMoreIfNeeded(currentItem: item) }
            }
            if let error = store.pageError {
                Text(error).foregroundStyle(.secondary)
            }
            if store.canLoadMore {
                Button("Continue Searching") { Task { await store.continueSearching() } }.disabled(store.isLoadingNextPage).frame(minHeight: 44)
            }
            if store.isLoadingNextPage {
                ProgressView().gridCellColumns(PosterGrid.columns.count).frame(maxWidth: .infinity).padding(.vertical)
            }
        }
        .scrollTargetLayout()
        .tvFocusSection()
    }
}

private struct LibraryFilterMenu: View {
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    let store: LibraryStore

    private var filterSymbol: String {
        store.filter.hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
    }

    var body: some View {
        Menu {
            Picker("Sort", selection: sortSelection) {
                ForEach(LibrarySortOption.allCases) { option in
                    Text(option.title)
                        .tag(option)
                }
            }

            Picker("Filter", selection: statusSelection) {
                ForEach(LibraryStatusFilter.allCases) { option in
                    Text(option.title)
                        .tag(option)
                }
            }
        } label: {
            GusToolbarLabel("Filter", systemImage: filterSymbol, tvSystemImage: "line.3.horizontal.decrease")
                .accessibilityValue(store.filter.hasActiveFilter ? String(localized: "Active") : "")
        }
        .gusIPadIconOnly()
        .gusTVToolbarIcon()
        .accessibilityLabel("Filter")
        .accessibilityValue(store.filter.hasActiveFilter ? String(localized: "Active") : "")
    }

    private var sortSelection: Binding<LibrarySortOption> {
        Binding {
            store.filter.sort
        } set: { sort in
            var filter = store.filter
            filter.sort = sort
            Task { await store.applyFilter(filter) }
        }
    }

    private var statusSelection: Binding<LibraryStatusFilter> {
        Binding {
            store.filter.status
        } set: { status in
            var filter = store.filter
            filter.status = status
            Task { await store.applyFilter(filter) }
        }
    }
}
