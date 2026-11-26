import SwiftUI

/// Artwork takes its size from the tile, never from the loaded image's intrinsic ratio.
/// Keeping the image in an overlay also makes loading and failure geometry identical.
struct ArtworkTile: View {
    let url: URL?
    var aspectRatio: CGFloat = 2.0 / 3.0
    var contentMode: ContentMode = .fill
    var placeholderSymbol = "photo"
    var fallbackURLs: [URL] = []
    var fallbackArtwork: Image?
    var onExhausted: (() async -> Void)?

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    AsyncPoster(
                        url: url, contentMode: contentMode, placeholderSymbol: placeholderSymbol,
                        fallbackURLs: fallbackURLs, fallbackArtwork: fallbackArtwork, onExhausted: onExhausted
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                }
            }
    }
}

/// Built-in covers for library thumbnails and the matching empty category screens.
enum LibraryCover: String {
    case liveTV = "LibraryLiveTV"
    case music = "LibraryMusic"
    case photos = "LibraryPhotos"

    init?(library: MediaItem) {
        switch library.collectionType {
        case .livetv: self = .liveTV
        case .music: self = .music
        case .photos: self = .photos
        // Jellyfin's combined Home Videos and Photos type is also used for photo-only libraries.
        case .homevideos where library.name?.caseInsensitiveCompare("Photos") == .orderedSame: self = .photos
        default: return nil
        }
    }

    var image: Image {
        Image(rawValue)
    }
}
