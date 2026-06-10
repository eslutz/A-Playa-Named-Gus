import AVFoundation
import AVKit
import SwiftUI

/// Constrained direct video playback per the watchOS brief: user-initiated, foreground
/// only, conservative bitrate, native `VideoPlayer` surface — a novelty path, never the
/// primary use case. Failures offer remote playback to another client instead.
struct WatchVideoPlayerView: View {
    /// Conservative streaming bitrate for the watch (cellular/Wi-Fi friendly).
    private static let maxStreamingBitrate = 3_000_000

    @Environment(SessionStore.self) private var session
    let item: MediaItem

    @State private var player: AVPlayer?
    @State private var errorMessage: String?
    @State private var isTargetPickerPresented = false

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else if let errorMessage {
                ScrollView {
                    VStack(spacing: 8) {
                        Text("Can't Play on Watch")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            isTargetPickerPresented = true
                        } label: {
                            Label("Play On…", systemImage: "play.tv")
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            await prepare()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .sheet(isPresented: $isTargetPickerPresented) {
            WatchPlayTargetPicker(item: item, startPositionTicks: PlaybackTime.resumePositionTicks(for: item))
        }
    }

    private func prepare() async {
        guard player == nil, let itemID = item.id else { return }
        do {
            let resolution = try await session.mediaProvider.resolvePlayback(
                for: itemID,
                maxStreamingBitrate: Self.maxStreamingBitrate,
                streamSelection: .none,
                startTimeTicks: PlaybackTime.resumePositionTicks(for: item),
                stereoLayout: .none
            )
            let player = AVPlayer(url: resolution.url)
            self.player = player
            player.play()
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            errorMessage = gusError.localizedDescription
        }
    }
}
