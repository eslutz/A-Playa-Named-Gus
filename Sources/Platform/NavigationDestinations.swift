import SwiftUI

/// Photos use the stable session cover on iPad; other items retain typed push navigation.
struct MediaItemNavigationLink<Label: View>: View {
    @Environment(RootNavigationState.self) private var navigation
    @Environment(SessionStore.self) private var session
    let item: MediaItem
    var onSelect: (() -> Void)? = nil
    @ViewBuilder var label: () -> Label

    var body: some View {
        #if os(iOS)
            if DeviceIdentity.usesIPadPresentation, item.type == .photo {
                Button {
                    onSelect?()
                    navigation.playerItem = ItemRef(item: item, serverID: session.server.id, userID: session.user.id)
                } label: { label() }
            } else {
                itemLink
            }
        #else
            itemLink
        #endif
    }

    @ViewBuilder private var itemLink: some View {
        if let onSelect {
            Button {
                onSelect()
                navigation.paths[navigation.selectedSectionID, default: NavigationPath()].append(ItemRef(item: item))
            } label: { label() }
        } else {
            NavigationLink(value: ItemRef(item: item)) { label() }
        }
    }
}

/// The type-routed detail surface for one media item — albums and playlists get the
/// track list, artists their albums, photos the viewer, everything else item detail.
/// Shared by pushed navigation (`gusItemDestinations`) and modally presented content
/// deep links (`ContentLinkHandler`).
struct ItemRouteDestination: View {
    @Environment(RootNavigationState.self) private var navigation
    let item: MediaItem

    var body: some View {
        destination.toolbar {
            if navigation.selectedSectionID == RootNavigationState.searchID, navigation.keptSearch != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Show Search Results", systemImage: "magnifyingglass") {
                        navigation.detailItem = nil
                        navigation.resumeKeptSearch()
                    }
                    .accessibilityIdentifier("Search.resumeResults")
                    .gusTVToolbarIcon()
                }
            }
        }
    }

    @ViewBuilder private var destination: some View {
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
    /// Registers A Playa Named Gus's item/library navigation destinations once, at the root of a
    /// `NavigationStack`. Feature views push `LibraryRef`/`ItemRef` values via
    /// `NavigationLink(value:)`; centralizing the destinations here avoids duplicate
    /// `navigationDestination` declarations on the same stack.
    /// Each pushed page owns its TV focus scope; the stack's root scope does not
    /// supply the custom namespace to destination content.
    func gusItemDestinations() -> some View {
        navigationDestination(for: LibraryRef.self) { ref in
            Group {
                if ref.item.collectionType == .livetv {
                    LiveTVView()
                } else if ref.item.collectionType == .boxsets {
                    CollectionsView()
                } else {
                    LibraryGridView(library: ref.item)
                }
            }
            .gusTVFocusScope()
        }
        .navigationDestination(for: ItemRef.self) { ref in
            ItemRouteDestination(item: ref.item)
                .gusTVFocusScope()
        }
        .navigationDestination(for: VideoPlaylistRef.self) { ref in
            VideoPlaylistDetailView(id: ref.id)
                .gusTVFocusScope()
        }
        .navigationDestination(for: BookSeriesRef.self) { ref in
            BookSeriesDetailView(ref: ref).gusTVFocusScope()
        }
        .navigationDestination(for: MediaCollectionRef.self) { ref in
            ScopedCollectionDestination(ref: ref)
                .gusTVFocusScope()
        }
        .navigationDestination(for: CollectionsRef.self) { ref in
            ScopedCollectionsDestination(ref: ref)
                .gusTVFocusScope()
        }
        .navigationDestination(for: AppScreen.self) { screen in
            Group {
                switch screen {
                case .downloads: DownloadsView()
                case .navigationSettings: NavigationSettingsView()
                case .seerrRequests: SeerrRequestsView()
                }
            }
            .gusTVFocusScope()
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
            paths[selectedSectionID, default: NavigationPath()].append(AppScreen.seerrRequests)
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
                NavigationLink(value: AppScreen.seerrRequests) { Label("My Requests", systemImage: "clock") }
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
