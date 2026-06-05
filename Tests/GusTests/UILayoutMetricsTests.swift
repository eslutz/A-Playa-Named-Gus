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
}
