import SwiftUI

/// The type-routed detail surface for one media item — albums and playlists get the
/// track list, artists their albums, photos the viewer, everything else item detail.
/// Shared by pushed navigation (`gusItemDestinations`) and modally presented content
/// deep links (`ContentLinkHandler`).
struct ItemRouteDestination: View {
    let item: MediaItem

    var body: some View {
        switch item.type {
        case .musicAlbum:
            AlbumDetailView(album: item)
        case .playlist:
            if let id = item.id.flatMap(ServerMediaListID.uuid) {
                VideoPlaylistDetailView(id: id)
            } else {
                AlbumDetailView(album: item)
            }
        case .boxSet:
            if let id = item.id.flatMap(ServerMediaListID.uuid) {
                MediaCollectionDetailView(id: id)
            } else {
                ItemDetailView(item: item)
            }
        case .musicArtist:
            ArtistAlbumsView(artist: item)
        case .photo:
            PhotoViewerView(photo: item)
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
    func gusItemDestinations() -> some View {
        navigationDestination(for: LibraryRef.self) { ref in
            if ref.item.collectionType == .livetv {
                LiveTVView()
            } else {
                LibraryGridView(library: ref.item)
            }
        }
        .navigationDestination(for: ItemRef.self) { ref in
            ItemRouteDestination(item: ref.item)
        }
        .navigationDestination(for: VideoPlaylistRef.self) { ref in
            VideoPlaylistDetailView(id: ref.id)
        }
        .navigationDestination(for: MediaCollectionRef.self) { ref in
            MediaCollectionDetailView(id: ref.id)
        }
        .navigationDestination(for: AppScreen.self) { screen in
            switch screen {
            case .downloads: DownloadsView()
            case .navigationSettings: NavigationSettingsView()
            }
        }
    }
}
