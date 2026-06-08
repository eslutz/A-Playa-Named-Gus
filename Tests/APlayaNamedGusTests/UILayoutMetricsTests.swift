@testable import Gus
import Testing

@Suite("UI layout metrics")
struct UILayoutMetricsTests {
    @Test("iOS and iPadOS media rails use the shared larger card sizing")
    func iOSMediaRailSizing() {
        #if os(iOS)
            #expect(MediaRailMetrics.itemWidth(for: .poster) >= 140)
            #expect(MediaRailMetrics.itemWidth(for: .backdrop) >= 280)
            #expect(PosterGrid.minimumItemWidth >= 140)
        #endif
    }

    @Test("about cards use one fixed tile size")
    func aboutCardsUseOneFixedTileSize() {
        #expect(AboutCardMetrics.cardWidth > 0)
        #expect(AboutCardMetrics.cardHeight > 0)
        #expect(AboutCardMetrics.tileSize.width == AboutCardMetrics.cardWidth)
        #expect(AboutCardMetrics.tileSize.height == AboutCardMetrics.cardHeight)
    }

    @Test("environment picker expands by environment count up to five columns")
    func environmentPickerExpandsByEnvironmentCount() {
        #expect(EnvironmentPickerMetrics.columns(forEnvironmentCount: 1) == 1)
        #expect(EnvironmentPickerMetrics.columns(forEnvironmentCount: 2) == 2)
        #expect(EnvironmentPickerMetrics.columns(forEnvironmentCount: 5) == 5)
        #expect(EnvironmentPickerMetrics.columns(forEnvironmentCount: 6) == 5)
        #expect(EnvironmentPickerMetrics.width(forEnvironmentCount: 2) < EnvironmentPickerMetrics.width(forEnvironmentCount: 5))
        #expect(EnvironmentPickerMetrics.width(forEnvironmentCount: 6) == EnvironmentPickerMetrics.width(forEnvironmentCount: 5))
    }

    @Test("vision environment control uses a separated leading scene ornament")
    func visionEnvironmentControlUsesSeparatedLeadingSceneOrnament() {
        #expect(VisionSidebarLayout.environmentControlPlacement == .leadingSceneOrnament)
    }

    @Test("page content uses shared max width")
    func pageContentUsesSharedMaxWidth() {
        #expect(PageContentMetrics.maxWidth >= 1200)
    }
}
