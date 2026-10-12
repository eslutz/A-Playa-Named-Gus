import SwiftUI

/// Artwork takes its size from the tile, never from the loaded image's intrinsic ratio.
/// Keeping the image in an overlay also makes loading and failure geometry identical.
struct ArtworkTile: View {
    let url: URL?
    var aspectRatio: CGFloat = 2.0 / 3.0
    var contentMode: ContentMode = .fill
    var placeholderSymbol = "photo"
    var fallbackURLs: [URL] = []
    var onExhausted: (() async -> Void)?

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    AsyncPoster(url: url, contentMode: contentMode, placeholderSymbol: placeholderSymbol, fallbackURLs: fallbackURLs, onExhausted: onExhausted)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
    }
}
