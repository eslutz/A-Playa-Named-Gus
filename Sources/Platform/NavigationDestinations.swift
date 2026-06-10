import SwiftUI

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
            switch ref.item.type {
            case .musicAlbum, .playlist:
                AlbumDetailView(album: ref.item)
            case .musicArtist:
                ArtistAlbumsView(artist: ref.item)
            case .photo:
                PhotoViewerView(photo: ref.item)
            default:
                ItemDetailView(item: ref.item)
            }
        }
    }
}
