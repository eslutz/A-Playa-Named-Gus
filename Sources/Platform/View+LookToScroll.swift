import SwiftUI

/// visionOS interaction helper mirroring PR #2's `View+LookToScroll`.
///
/// On visionOS 2, `ScrollView` already supports gaze-driven scrolling; this modifier is
/// the attachment point for any additional look-to-scroll tuning and is a transparent
/// passthrough on every platform so feature code can call it unconditionally.
extension View {
    @ViewBuilder
    func lookToScroll(_ axes: Axis.Set = .vertical) -> some View {
        #if os(visionOS)
            if #available(visionOS 26.0, *) {
                scrollInputBehavior(.enabled, for: .look(axes: axes))
            } else {
                self
            }
        #else
            self
        #endif
    }
}
