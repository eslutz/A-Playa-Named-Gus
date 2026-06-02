import AVKit
import JellyfinAPI
import SwiftUI

/// Pure-AVKit player surface.
///
/// `VideoPlayer` on iOS/macOS/visionOS; `AVPlayerViewController` (via a representable) on
/// tvOS, which has no SwiftUI `VideoPlayer`. The `PlaybackStore` owns the `AVPlayer` and
/// tears it down on dismiss.
struct VideoPlayerView: View {

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let item: BaseItemDto

    @State private var store: PlaybackStore?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let store, let player = store.player {
                PlayerSurface(player: player)
                    .ignoresSafeArea()
            } else if case let .failed(message)? = store?.state {
                ContentUnavailableView {
                    Label("Can't Play This", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
                .foregroundStyle(.white)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        #if !os(tvOS)
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .padding()
            }
            .buttonStyle(.plain)
            .tint(.white)
            .padding(8)
        }
        #endif
        .task {
            if store == nil {
                let store = PlaybackStore(item: item, session: session)
                self.store = store
                await store.prepare()
            }
        }
        .onDisappear {
            store?.teardown()
        }
    }
}

/// Platform-divergent player surface.
private struct PlayerSurface: View {
    let player: AVPlayer

    var body: some View {
        #if os(tvOS)
        TVPlayerSurface(player: player)
        #else
        VideoPlayer(player: player)
        #endif
    }
}

#if os(tvOS)
/// tvOS-native `AVPlayerViewController`, which provides the full focus-engine transport.
private struct TVPlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}
#endif
