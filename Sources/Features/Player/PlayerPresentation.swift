import SwiftUI

extension View {
    /// Presents the video player full-screen where supported, falling back to a sheet on
    /// macOS (which has no `fullScreenCover`). The presented content inherits the
    /// environment, so `SessionStore` is available inside the player.
    @ViewBuilder
    func playerPresentation(item: Binding<ItemRef?>) -> some View {
        #if os(macOS)
        sheet(item: item) { ref in
            VideoPlayerView(item: ref.item)
                .frame(minWidth: 640, minHeight: 360)
        }
        #else
        fullScreenCover(item: item) { ref in
            VideoPlayerView(item: ref.item)
        }
        #endif
    }
}
