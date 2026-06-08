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

enum VisionEnvironmentControlPlacement: Equatable {
    case leadingSceneOrnament
}

enum VisionSidebarLayout {
    static let environmentControlPlacement: VisionEnvironmentControlPlacement = .leadingSceneOrnament
    static let environmentControlSystemImage = "mountain.2"
    static let environmentControlTopPadding: CGFloat = 116
    static let environmentControlTrailingPadding: CGFloat = 120
    static let environmentControlDiameter: CGFloat = 48
}
