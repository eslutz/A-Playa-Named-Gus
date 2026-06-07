import CoreGraphics

enum PageContentMetrics {
    static let maxWidth: CGFloat = 1320
}

enum AboutCardMetrics {
    static let cardWidth: CGFloat = 260
    static let cardHeight: CGFloat = 150

    static var tileSize: CGSize {
        CGSize(width: cardWidth, height: cardHeight)
    }
}
