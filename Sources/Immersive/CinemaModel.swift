#if os(visionOS)
    import AVFoundation
    import JellyfinAPI
    import SwiftUI

    struct CinemaPlaybackPresentation {
        let player: AVPlayer
        let title: String
        let stereoLayout: Stereo3DLayout?

        var isFramePackedStereo: Bool {
            stereoLayout.flatMap(Stereo3DScreenMetrics.samplingPlan(for:)) != nil
        }
    }

    /// Tracks whether the "Gus Cinema" immersive space is open.
    ///
    /// Ported from PR #2's `CinemaModel`, re-expressed on the **Observation** framework
    /// (`@Observable` + `@Environment`) instead of `ObservableObject`/`@Published`/`Factory`.
    @MainActor
    @Observable
    final class CinemaModel {
        private(set) var isOpen = false
        private(set) var playbackPresentation: CinemaPlaybackPresentation?

        func setOpen(_ open: Bool) {
            isOpen = open
        }

        func present(player: AVPlayer, title: String, stereoLayout: Stereo3DLayout?) {
            playbackPresentation = CinemaPlaybackPresentation(
                player: player,
                title: title,
                stereoLayout: stereoLayout
            )
        }

        func clearPlaybackPresentation() {
            playbackPresentation = nil
        }
    }

    /// Opt-in toggle that opens/closes the immersive cinema. The windowed AVKit player keeps
    /// playing across the transition; if `openImmersiveSpace` fails we fall back to the window.
    struct CinemaToggleButton: View {
        @Environment(CinemaModel.self) private var cinema
        @Environment(\.openImmersiveSpace) private var openImmersiveSpace
        @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

        let item: BaseItemDto

        var body: some View {
            Button {
                Task {
                    if cinema.isOpen {
                        await dismissImmersiveSpace()
                        cinema.setOpen(false)
                        cinema.clearPlaybackPresentation()
                    } else {
                        switch await openImmersiveSpace(id: GusCinema.spaceID) {
                        case .opened:
                            cinema.setOpen(true)
                        case .error, .userCancelled:
                            cinema.setOpen(false) // graceful windowed fallback
                        @unknown default:
                            cinema.setOpen(false)
                        }
                    }
                }
            } label: {
                Label(
                    cinema.isOpen ? "Leave Cinema" : "Gus Cinema",
                    systemImage: cinema.isOpen ? "xmark.circle" : "movieclapper"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel(cinema.isOpen ? "Leave Gus Cinema" : "Watch \(item.displayTitle) in Gus Cinema")
        }
    }
#endif
