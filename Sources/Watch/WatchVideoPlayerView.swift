import AVKit
import SwiftUI

/// Foreground-only, conservative native video uses the same session ownership,
/// reporting, preparation and cancellation rules as the primary Apple platforms.
struct WatchVideoPlayerView: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    let request: PlaybackRequest
    @State private var store: PlaybackStore?
    @State private var refresh = PlaybackRefreshStore()
    @State private var isTargetPickerPresented = false

    var body: some View {
        Group {
            if let store, store.state == .ready, let player = store.player {
                VideoPlayer(player: player)
            } else if case let .failed(message)? = store?.state {
                ScrollView {
                    VStack(spacing: 8) {
                        Text("Can't Play on Watch").font(.headline)
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                        Button("Try Again") { Task { await store?.prepare() } }
                        Button("Play On…", systemImage: "play.tv") { isTargetPickerPresented = true }
                    }
                }
            } else if store?.state == .idle {
                Button("Play", systemImage: "play.fill") { Task { await store?.prepare() } }
            } else {
                VStack {
                    ProgressView()
                    Button("Cancel", role: .cancel) { store?.teardown(); dismiss() }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if let notice = store?.trackSelectionNotice {
                VStack(spacing: 4) {
                    Text(notice).font(.footnote).foregroundStyle(.secondary)
                    Button("OK") { store?.trackSelectionNotice = nil }
                }
            }
        }
        .task {
            guard store == nil else { return }
            var constrained = request
            constrained.maxStreamingBitrate = min(request.maxStreamingBitrate ?? 3_000_000, 3_000_000)
            constrained.presentation = .twoD
            let player = PlaybackStore(request: constrained, session: session, playbackRefresh: refresh, downloads: downloads)
            store = player
            player.setPresentationActive(phase == .active)
            await player.prepare()
        }
        .onChange(of: phase) { _, phase in
            store?.setPresentationActive(phase == .active)
            if phase == .background {
                store?.teardown()
            }
        }
        .onChange(of: store?.didFinishPlayback ?? false) {
            _, ended in if ended {
                dismiss()
            }
        }
        .onDisappear { store?.teardown() }
        .sheet(isPresented: $isTargetPickerPresented) { WatchPlayTargetPicker(request: store?.request ?? request) }
    }
}
