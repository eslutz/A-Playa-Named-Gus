import CoreGraphics

enum EnvironmentPickerMetrics {
    static let maximumColumns = 5
    static let itemWidth: CGFloat = 120
    static let itemSpacing: CGFloat = 14
    static let horizontalPadding: CGFloat = 48

    static func columns(forEnvironmentCount count: Int) -> Int {
        max(1, min(maximumColumns, count))
    }

    static func width(forEnvironmentCount count: Int) -> CGFloat {
        let columnCount = CGFloat(columns(forEnvironmentCount: count))
        let spacing = max(0, columnCount - 1) * itemSpacing
        return horizontalPadding + columnCount * itemWidth + spacing
    }
}

#if os(visionOS)
    import AVFoundation
    import JellyfinAPI
    import SwiftUI

    enum CinemaEnvironment: String, CaseIterable, Identifiable {
        case gusCinema
        case pineapple

        var id: String {
            rawValue
        }

        var title: LocalizedStringKey {
            switch self {
            case .gusCinema: return "Gus Cinema"
            case .pineapple: return "Pineapple"
            }
        }

        var systemImage: String {
            switch self {
            case .gusCinema: return "movieclapper"
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
        private(set) var activeEnvironment: CinemaEnvironment?

        var renderedEnvironment: CinemaEnvironment {
            activeEnvironment ?? .gusCinema
        }

        func setOpen(_ open: Bool) {
            isOpen = open
        }

        func selectEnvironment(_ environment: CinemaEnvironment) {
            activeEnvironment = environment
        }

        func clearSelectedEnvironment() {
            activeEnvironment = nil
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

    struct VisionEnvironmentSidebarButton: View {
        @Environment(CinemaModel.self) private var cinema
        @Environment(\.openImmersiveSpace) private var openImmersiveSpace
        @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
        @State private var isPickerPresented = false

        var body: some View {
            Button {
                isPickerPresented = true
            } label: {
                Label("Environment", systemImage: VisionSidebarLayout.environmentControlSystemImage)
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .frame(
                        width: VisionSidebarLayout.environmentControlDiameter,
                        height: VisionSidebarLayout.environmentControlDiameter
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .glassBackgroundEffect(in: Circle())
            .accessibilityLabel("Environment")
            .accessibilityIdentifier("visionEnvironmentSidebarButton")
            .popover(isPresented: $isPickerPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
                EnvironmentPicker(
                    selectedEnvironment: cinema.activeEnvironment,
                    isOpen: cinema.isOpen,
                    select: { environment in
                        Task { await select(environment) }
                    }
                )
            }
        }

        @MainActor
        private func select(_ environment: CinemaEnvironment) async {
            if cinema.isOpen, cinema.activeEnvironment == environment {
                await closeEnvironment()
                return
            }

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
                cinema.clearSelectedEnvironment()
            @unknown default:
                cinema.setOpen(false)
                cinema.clearSelectedEnvironment()
            }
        }

        @MainActor
        private func closeEnvironment() async {
            await dismissImmersiveSpace()
            cinema.setOpen(false)
            cinema.clearSelectedEnvironment()
            cinema.clearPlaybackPresentation()
            isPickerPresented = false
        }
    }

    private struct EnvironmentPicker: View {
        let selectedEnvironment: CinemaEnvironment?
        let isOpen: Bool
        let select: (CinemaEnvironment) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Text("Select an Environment")
                    .font(.title3.weight(.semibold))

                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(environments) { environment in
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
                            .frame(width: EnvironmentPickerMetrics.itemWidth)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(environment == selectedEnvironment ? .accentColor : nil)
                        .accessibilityHint(environment == selectedEnvironment && isOpen ? "Closes the current environment." : "Opens this environment.")
                    }
                }
            }
            .padding(24)
            .frame(width: EnvironmentPickerMetrics.width(forEnvironmentCount: environments.count))
        }

        private var environments: [CinemaEnvironment] {
            CinemaEnvironment.allCases
        }

        private var columns: [GridItem] {
            Array(
                repeating: GridItem(.fixed(EnvironmentPickerMetrics.itemWidth), spacing: EnvironmentPickerMetrics.itemSpacing),
                count: EnvironmentPickerMetrics.columns(forEnvironmentCount: environments.count)
            )
        }
    }

#endif
