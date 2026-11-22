import CoreGraphics

/// Distances between app-owned elements. System lists, forms, and controls own their insets.
enum ContentSpacing {
    static let caption: CGFloat = 4
    #if os(tvOS)
        static let group: CGFloat = 12
        static let card: CGFloat = 20
        static let section: CGFloat = 40
    #elseif os(visionOS)
        static let group: CGFloat = 10
        static let card: CGFloat = 16
        static let section: CGFloat = 24
    #else
        static let group: CGFloat = 8
        static let card: CGFloat = 12
        static let section: CGFloat = 24
    #endif
}

enum PageContentMetrics {
    static var maxWidth: CGFloat {
        #if os(tvOS)
            .infinity
        #else
            1320
        #endif
    }
}

enum AboutCardMetrics {
    #if os(tvOS)
        static let cardWidth: CGFloat = 480
        static let cardHeight: CGFloat = 360
        static let posterSize = CGSize(width: 120, height: 180)
    #else
        static let cardWidth: CGFloat = 260
        static let cardHeight: CGFloat = 150
        static let posterSize = CGSize(width: 74, height: 110)
    #endif

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
    static let environmentControlTrailingPadding: CGFloat = 116
    static let environmentControlDiameter: CGFloat = 56
}

/// Portraits must remain legible at television viewing distance.
enum CastCardMetrics {
    #if os(tvOS)
        static let width: CGFloat = 240
        static let height: CGFloat = 300
    #else
        static let width: CGFloat = 120
        static let height: CGFloat = 150
    #endif
}
