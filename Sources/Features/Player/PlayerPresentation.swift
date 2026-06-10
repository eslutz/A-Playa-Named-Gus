import SwiftUI

extension View {
    /// Presents the appropriate player full-screen where supported, falling back to a
    /// sheet on macOS (which has no `fullScreenCover`). Audio items (songs, audiobooks)
    /// open the audio player; everything else opens the video player. The presented
    /// content inherits the environment, so `SessionStore` is available inside.
    @ViewBuilder
    func playerPresentation(item: Binding<ItemRef?>) -> some View {
        #if os(macOS)
            sheet(item: item) { ref in
                PresentedPlayer(item: ref.item)
                    .frame(minWidth: 640, minHeight: 360)
            }
        #else
            fullScreenCover(item: item) { ref in
                PresentedPlayer(item: ref.item)
            }
        #endif
    }
}

private struct PresentedPlayer: View {
    let item: MediaItem

    var body: some View {
        if item.isAudioPlayable {
            AudioPlayerScreen(item: item)
        } else {
            VideoPlayerView(item: item)
        }
    }
}
