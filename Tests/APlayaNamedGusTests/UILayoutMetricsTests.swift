import Foundation
@testable import Gus
import Testing

@Suite("UI layout metrics")
struct UILayoutMetricsTests {
    @Test("iOS and iPadOS media rails use the shared larger card sizing")
    func iOSMediaRailSizing() {
        #if os(iOS)
            #expect(MediaRailMetrics.itemWidth(for: .poster) >= 140)
            #expect(MediaRailMetrics.itemWidth(for: .backdrop) >= 280)
            #expect(PosterGrid.minimumItemWidth >= 140)
        #endif
    }

    @Test("about cards use one fixed tile size")
    func aboutCardsUseOneFixedTileSize() {
        #expect(AboutCardMetrics.cardWidth > 0)
        #expect(AboutCardMetrics.cardHeight > 0)
        #expect(AboutCardMetrics.tileSize.width == AboutCardMetrics.cardWidth)
        #expect(AboutCardMetrics.tileSize.height == AboutCardMetrics.cardHeight)
    }

    @Test("environment picker expands by environment count up to five columns")
    func environmentPickerExpandsByEnvironmentCount() {
        #expect(EnvironmentPickerMetrics.columns(forEnvironmentCount: 1) == 1)
        #expect(EnvironmentPickerMetrics.columns(forEnvironmentCount: 2) == 2)
        #expect(EnvironmentPickerMetrics.columns(forEnvironmentCount: 5) == 5)
        #expect(EnvironmentPickerMetrics.columns(forEnvironmentCount: 6) == 5)
        #expect(EnvironmentPickerMetrics.width(forEnvironmentCount: 2) < EnvironmentPickerMetrics.width(forEnvironmentCount: 5))
        #expect(EnvironmentPickerMetrics.width(forEnvironmentCount: 6) == EnvironmentPickerMetrics.width(forEnvironmentCount: 5))
    }

    @Test("vision environment control uses a separated leading scene ornament")
    func visionEnvironmentControlUsesSeparatedLeadingSceneOrnament() {
        #expect(VisionSidebarLayout.environmentControlPlacement == .leadingSceneOrnament)
    }

    @Test("vision environment control is centered on the sidebar axis below the menu")
    func visionEnvironmentControlIsCenteredBelowSidebarMenu() {
        #expect(VisionSidebarLayout.environmentControlTopPadding == 116)
        #expect(VisionSidebarLayout.environmentControlTrailingPadding == 116)
        #expect(VisionSidebarLayout.environmentControlDiameter == 56)
    }

    @Test("page content uses shared max width")
    func pageContentUsesSharedMaxWidth() {
        #expect(PageContentMetrics.maxWidth >= 1200)
    }

    @Test("video player relies on system close and options chrome")
    func videoPlayerReliesOnSystemCloseAndOptionsChrome() throws {
        let source = try sourceFile(named: "VideoPlayerView.swift", under: "Sources/Features/Player")

        #expect(!source.contains("Close Player"))
        #expect(!source.contains("Playback Options"))
        #expect(!source.contains("ellipsis.circle.fill"))
    }

    @Test("video player uses SharePlay instead of SyncPlay")
    func videoPlayerUsesSharePlayInsteadOfSyncPlay() throws {
        let playerSource = try sourceFile(named: "VideoPlayerView.swift", under: "Sources/Features/Player")
        let sessionsSocketSource = try sourceFile(named: "SessionsSocket.swift", under: "Sources/Services")
        let projectSource = try sourceFile(named: "project.yml", under: "")

        #expect(!playerSource.contains("SyncPlay"))
        #expect(!sessionsSocketSource.contains("SyncPlaySocket"))
        #expect(!projectSource.contains("SyncPlayStore.swift"))
        #expect(playerSource.contains("SharePlay"))
    }

    @Test("SharePlay uses GroupActivities and AV playback coordination")
    func sharePlayUsesGroupActivitiesAndPlaybackCoordination() throws {
        let source = try sourceFile(named: "SharePlayCoordinator.swift", under: "Sources/Features/Player")
        let sharedEntitlements = try sourceFile(named: "Gus-SharePlay.entitlements", under: "Config")

        #expect(source.contains("GroupActivity"))
        #expect(source.contains("sessions()"))
        #expect(source.contains("coordinateWithSession"))
        #expect(source.contains("com.apple.developer.group-session"))
        #expect(sharedEntitlements.contains("com.apple.developer.group-session"))
    }

    @Test("SharePlay eligibility is limited to playable and readable media")
    func sharePlayEligibilityIsLimitedToPlayableAndReadableMedia() {
        #expect(SharePlayCoordinator.canShare(MediaItem(id: "movie", type: .movie)))
        #expect(SharePlayCoordinator.canShare(MediaItem(id: "audio", type: .audio)))
        #expect(SharePlayCoordinator.canShare(MediaItem(id: "book", type: .book)))
        #expect(SharePlayCoordinator.canShare(MediaItem(id: "recording", type: .recording)))

        #expect(!SharePlayCoordinator.canShare(MediaItem(id: "series", type: .series)))
        #expect(!SharePlayCoordinator.canShare(MediaItem(id: "folder", type: .folder)))
        #expect(!SharePlayCoordinator.canShare(MediaItem(id: "photo", type: .photo)))
        #expect(!SharePlayCoordinator.canShare(MediaItem(id: "live", type: .liveChannel)))
        #expect(!SharePlayCoordinator.canShare(MediaItem(type: .movie)))
    }

    @Test("SharePlay launch uses native sharing controller outside video player")
    func sharePlayLaunchUsesNativeSharingControllerOutsideVideoPlayer() throws {
        let bridgeSource = try sourceFile(named: "SharePlaySharingController.swift", under: "Sources/Platform")
        let itemDetailSource = try sourceFile(named: "ItemDetailView.swift", under: "Sources/Features/Item")
        let playerSource = try sourceFile(named: "VideoPlayerView.swift", under: "Sources/Features/Player")

        #expect(bridgeSource.contains("GroupActivitySharingController"))
        #expect(bridgeSource.contains("_GroupActivities_UIKit"))
        #expect(bridgeSource.contains("_GroupActivities_AppKit"))
        #expect(itemDetailSource.contains("SharePlay"))
        #expect(itemDetailSource.contains("shareplay"))
        #expect(!playerSource.contains("GroupActivitySharingController"))
    }

    @Test("tvOS does not expose unavailable SharePlay sharing controller")
    func tvOSDoesNotExposeUnavailableSharePlaySharingController() throws {
        let bridgeSource = try sourceFile(named: "SharePlaySharingController.swift", under: "Sources/Platform")

        #expect(bridgeSource.contains("#if !os(tvOS)"))
        #expect(bridgeSource.contains("#if os(iOS) || os(visionOS)"))
        #expect(!bridgeSource.contains("TVPlayerSurface"))
    }

    private func sourceFile(named fileName: String, under relativePath: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: relativePath.isEmpty ? "." : relativePath)
            .appending(path: fileName)

        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
