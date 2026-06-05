#if os(visionOS)
    import AVFoundation
    import JellyfinAPI
    import SwiftUI

    enum CinemaEnvironment: String, CaseIterable, Identifiable {
        case gusCinema
        case midnight
        case ocean
        case pineapple

        var id: String {
            rawValue
        }

        var title: LocalizedStringKey {
            switch self {
            case .gusCinema: return "Gus Cinema"
            case .midnight: return "Midnight"
            case .ocean: return "Ocean"
            case .pineapple: return "Pineapple"
            }
        }

        var systemImage: String {
            switch self {
            case .gusCinema: return "movieclapper"
            case .midnight: return "moon.stars"
            case .ocean: return "water.waves"
            case .pineapple: return "sparkles"
            }
        }
    }

    struct CinemaPlaybackPresentation {
        let player: AVPlayer
        let title: String
        let stereoLayout: Stereo3DLayout?
        /// Non-nil when the layout is frame-packed (SBS/TAB); drives the stereo screen entity.
        let stereoRenderer: StereoFrameRenderer?

        /// True when a `StereoFrameRenderer` is present and the layout is a supported frame-packed format.
        var isFramePackedStereo: Bool {
            stereoRenderer != nil && stereoLayout.flatMap(Stereo3DScreenMetrics.samplingPlan(for:)) != nil
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
        var selectedEnvironment: CinemaEnvironment = .gusCinema

        func setOpen(_ open: Bool) {
            isOpen = open
        }

        func selectEnvironment(_ environment: CinemaEnvironment) {
            selectedEnvironment = environment
        }

        func present(player: AVPlayer, title: String, stereoLayout: Stereo3DLayout?, stereoRenderer: StereoFrameRenderer? = nil) {
            playbackPresentation = CinemaPlaybackPresentation(
                player: player,
                title: title,
                stereoLayout: stereoLayout,
                stereoRenderer: stereoRenderer
            )
        }

        func clearPlaybackPresentation() {
            playbackPresentation = nil
        }
    }

    struct VisionEnvironmentOrnament: View {
        @Environment(CinemaModel.self) private var cinema
        @Environment(\.openImmersiveSpace) private var openImmersiveSpace
        @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
        @State private var isPickerPresented = false

        var body: some View {
            Button {
                isPickerPresented = true
            } label: {
                Label("Environment", systemImage: cinema.selectedEnvironment.systemImage)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel("Environment")
            .popover(isPresented: $isPickerPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
                EnvironmentPicker(
                    selectedEnvironment: cinema.selectedEnvironment,
                    isOpen: cinema.isOpen,
                    select: { environment in
                        Task { await select(environment) }
                    },
                    close: {
                        Task { await closeEnvironment() }
                    }
                )
            }
        }

        @MainActor
        private func select(_ environment: CinemaEnvironment) async {
            cinema.selectEnvironment(environment)

            guard !cinema.isOpen else {
                isPickerPresented = false
                return
            }

            switch await openImmersiveSpace(id: GusCinema.spaceID) {
            case .opened:
                cinema.setOpen(true)
                isPickerPresented = false
            case .error, .userCancelled:
                cinema.setOpen(false)
            @unknown default:
                cinema.setOpen(false)
            }
        }

        @MainActor
        private func closeEnvironment() async {
            await dismissImmersiveSpace()
            cinema.setOpen(false)
            cinema.clearPlaybackPresentation()
            isPickerPresented = false
        }
    }

    private struct EnvironmentPicker: View {
        let selectedEnvironment: CinemaEnvironment
        let isOpen: Bool
        let select: (CinemaEnvironment) -> Void
        let close: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Text("Select an Environment")
                    .font(.title3.weight(.semibold))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(CinemaEnvironment.allCases) { environment in
                        Button {
                            select(environment)
                        } label: {
                            VStack(spacing: 10) {
                                Image(systemName: environment.systemImage)
                                    .font(.title2)
                                    .frame(width: 58, height: 58)
                                    .background(.thinMaterial, in: Circle())

                                Text(environment.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(environment == selectedEnvironment ? .accentColor : nil)
                    }
                }

                if isOpen {
                    Button(role: .cancel) {
                        close()
                    } label: {
                        Label("Close Environment", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(width: 520)
        }
    }

#endif
