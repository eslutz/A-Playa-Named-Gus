import SwiftUI

/// Enable native gaze scrolling on visionOS.
extension View {
    @ViewBuilder
    func lookToScroll(_ axes: Axis.Set = .vertical) -> some View {
        #if os(visionOS)
            scrollInputBehavior(.enabled, for: .look(axes: axes))

        #else
            self
        #endif
    }
}
