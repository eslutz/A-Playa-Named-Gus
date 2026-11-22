import SwiftUI

/// Value destinations for the signed-in section stacks and externally opened detail sheets.
enum GusRoute: Hashable {
    case section(String)
    case library(LibraryRef)
    case item(ItemRef)
    case searchResult(ItemRef, query: String)
    case related(UUID)
    case playlist(VideoPlaylistRef)
    case bookSeries(BookSeriesRef)
    case collection(MediaCollectionRef)
    case collections(CollectionsRef)
    case screen(AppScreen)
    case nextUp
    case libraryGrid(LibraryGridScope)
    case seerr(SeerrRoute)
}

struct SeerrRoute: Hashable {
    enum Destination: Hashable {
        case title(SeerrMediaType, Int)
        case person(id: Int, name: String)
        case season(seriesID: Int, number: Int)
        case catalog(name: String, source: SeerrCatalogSource, featured: SeerrStoreReference<SeerrCatalogStore>? = nil)
        case categories(SeerrStoreReference<SeerrCategoryDirectory>)
        case search
    }

    let revision: UUID
    let destination: Destination
}

/// Retain the existing shelf store for shared directory loading and Trending backfill.
struct SeerrStoreReference<Store: AnyObject>: Hashable {
    let store: Store

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.store === rhs.store
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(store))
    }
}

extension SeerrStore {
    func navigationRoute(_ destination: SeerrRoute.Destination) -> GusRoute {
        .seerr(SeerrRoute(revision: revision, destination: destination))
    }
}

/// Photos use the stable session cover on iPad; other items retain typed push navigation.
struct MediaItemNavigationLink<Label: View>: View {
    @Environment(RootNavigationState.self) private var navigation
    @Environment(SessionStore.self) private var session
    let item: MediaItem
    var searchQuery: String?
    @ViewBuilder var label: () -> Label

    var body: some View {
        #if os(iOS)
            if DeviceIdentity.usesIPadPresentation, item.type == .photo {
                Button {
                    if let searchQuery {
                        navigation.globalSearch.typed.selectedResult(item, for: searchQuery, in: session.searchHistory)
                    }
                    navigation.playerItem = ItemRef(item: item, serverID: session.server.id, userID: session.user.id)
                } label: { label() }
            } else {
                itemLink
            }
        #else
            itemLink
        #endif
    }

    private var itemLink: some View {
        let ref = ItemRef(item: item)
        let route = searchQuery.map { GusRoute.searchResult(ref, query: $0) } ?? .item(ref)
        return NavigationLink(value: route) { label() }
    }
}

/// The type-routed detail surface for one media item — albums and playlists get the
/// track list, artists their albums, photos the viewer, everything else item detail.
/// Shared by pushed navigation (`gusItemDestinations`) and modally presented content
/// deep links (`ContentLinkHandler`).
struct ItemRouteDestination: View {
    let item: MediaItem

    var body: some View {
        switch item.type {
        case .genre:
            if let id = item.id {
                LibraryGridView(scope: .genre(id: id, name: item.displayTitle))
            } else {
                ContentUnavailableView("Genre Unavailable", systemImage: "tag")
            }
        case .musicAlbum:
            AlbumDetailView(album: item)
        case .playlist:
            if let id = item.id.flatMap(ServerMediaListID.uuid) {
                VideoPlaylistDetailView(id: id)
            } else {
                AlbumDetailView(album: item)
            }
        case .boxSet:
            if let id = item.id {
                MediaCollectionDetailView(id: id)
            } else {
                ItemDetailView(item: item)
            }
        case .musicArtist:
            ArtistAlbumsView(artist: item)
        case .photo:
            PhotoViewerView(photo: item)
        #if os(iOS) || os(tvOS)
            case .photoAlbum:
                LibraryGridView(library: item)
        #endif
        default:
            ItemDetailView(item: item)
        }
    }
}

extension View {
    /// A destination belongs to its enclosing stack, including when a section is reached from More.
    func gusItemDestinations() -> some View {
        navigationDestination(for: GusRoute.self) { route in
            GusRouteDestination(route: route).gusTVFocusScope()
        }
    }
}

private struct GusRouteDestination: View {
    @Environment(RootNavigationState.self) private var navigation
    let route: GusRoute

    var body: some View {
        switch route {
        case let .section(id):
            SectionDestination(sectionID: id)
        case let .library(ref):
            if ref.item.collectionType == .livetv {
                LiveTVView()
            } else if ref.item.collectionType == .boxsets {
                CollectionsView()
            } else {
                LibraryGridView(library: ref.item)
            }
        case let .item(ref), let .searchResult(ref, _):
            ItemRouteDestination(item: ref.item)
        case let .related(id):
            RelatedResultsDestination(id: id)
        case let .playlist(ref):
            VideoPlaylistDetailView(id: ref.id)
        case let .bookSeries(ref):
            BookSeriesDetailView(ref: ref)
        case let .collection(ref):
            ScopedCollectionDestination(ref: ref)
        case let .collections(ref):
            ScopedCollectionsDestination(ref: ref)
        case let .screen(screen):
            switch screen {
            case .downloads: DownloadsView()
            case .navigationSettings: NavigationSettingsView()
            case .seerrRequests: SeerrRequestsView()
            case .seerrSettings: SeerrSettingsView()
            case .clientLogs: DeveloperDiagnosticsView()
            #if !os(tvOS)
                case .libraryIntelligence: LibraryIntelligenceSettingsView()
            #endif
            }
        case .nextUp:
            if let store = navigation.home {
                NextUpListView(store: store)
            }
        case let .libraryGrid(scope):
            LibraryGridView(scope: scope)
        case let .seerr(route):
            SeerrRouteDestination(route: route)
        }
    }
}

private struct SeerrRouteDestination: View {
    @Environment(SeerrStore.self) private var store
    let route: SeerrRoute

    var body: some View {
        if route.revision == store.revision, store.isConnected {
            switch route.destination {
            case let .title(type, id):
                SeerrTitleDetailView(mediaType: type, id: id, store: store)
            case let .person(id, name):
                SeerrPersonView(personID: id, displayName: name, store: store)
            case let .season(seriesID, number):
                SeerrSeasonView(seriesID: seriesID, seasonNumber: number, store: store)
            case let .catalog(name, source, featured):
                SeerrCatalogGridView(title: name, source: source, store: store, featuredCatalog: featured?.store)
            case let .categories(directory):
                SeerrCategoryGrid(directory: directory.store, store: store)
            case .search:
                DiscoverBrowseView(store: store, searchOnly: true)
            }
        }
    }
}

private struct ScopedCollectionDestination: View {
    @Environment(SessionStore.self) private var session
    let ref: MediaCollectionRef
    var body: some View {
        if ref.scope == session.references.scope {
            MediaCollectionDetailView(id: ref.id, format: ref.format)
        } else {
            ContentUnavailableView("Collection Unavailable", systemImage: "rectangle.stack")
        }
    }
}

private struct ScopedCollectionsDestination: View {
    @Environment(SessionStore.self) private var session
    let ref: CollectionsRef
    var body: some View {
        if ref.scope == session.references.scope {
            CollectionsView(initialFormat: ref.format, movieLibraryID: ref.movieLibraryID)
        } else {
            ContentUnavailableView("Collections Unavailable", systemImage: "rectangle.stack")
        }
    }
}

@MainActor extension RootNavigationState {
    /// Confirmation can leave its task sheet and reveal history in the iPad content stack.
    func pushIPadRequestHistory() -> Bool {
        #if os(iOS)
            guard DeviceIdentity.usesIPadPresentation else { return false }
            paths[selectedSectionID, default: []].append(.screen(.seerrRequests))
            return true
        #else
            return false
        #endif
    }
}

/// The iPad toolbar uses a value route; other platforms retain their current label.
struct SeerrRequestHistoryLink: View {
    var body: some View {
        #if os(iOS)
            if DeviceIdentity.usesIPadPresentation {
                NavigationLink(value: GusRoute.screen(.seerrRequests)) { Label("My Requests", systemImage: "clock") }
                    .labelStyle(.iconOnly)
            } else {
                standardLink
            }
        #elseif os(tvOS)
            NavigationLink { SeerrRequestsView() } label: { Image(systemName: "clock") }
                .accessibilityLabel("My Requests")
        #else
            standardLink
        #endif
    }

    private var standardLink: some View {
        NavigationLink("My Requests") { SeerrRequestsView() }
    }
}
