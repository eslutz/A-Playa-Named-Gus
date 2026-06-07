@testable import Gus
import JellyfinAPI
import Testing

@Suite("Item detail actions")
struct ItemDetailActionTests {
    @Test("next up cards use a fixed widescreen frame")
    func nextUpCardsUseWidescreenFrame() {
        #expect(abs(MediaRailMetrics.aspectRatio(for: .backdrop) - (16.0 / 9.0)) < 0.000_001)
    }
}
