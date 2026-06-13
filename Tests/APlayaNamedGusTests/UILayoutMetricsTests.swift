import CryptoKit
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

    @Test("navigation appearance row uses aligned list icon")
    func navigationAppearanceRowUsesAlignedListIcon() throws {
        let settingsSource = try sourceFile(named: "SettingsView.swift", under: "Sources/Features/Settings")

        #expect(settingsSource.contains("Label(\"Navigation\", systemImage: \"list.bullet\")"))
        #expect(!settingsSource.contains("list.bullet.indent"))
    }

    @Test("navigation editor uses native edit, reorder, and delete list behavior")
    func navigationEditorUsesNativeEditReorderAndDeleteListBehavior() throws {
        let source = try sourceFile(named: "NavigationSettingsView.swift", under: "Sources/Features/Settings")
        let settingsSource = try sourceFile(named: "SettingsView.swift", under: "Sources/Features/Settings")

        #expect(source.contains("EditButton()"))
        #expect(source.contains(".onMove"))
        #expect(source.contains(".onDelete"))
        #expect(source.contains(".draggable(section.id)"))
        #expect(source.contains(".dropDestination(for: String.self)"))
        #expect(source.contains("moveDraggedSection"))
        #expect(source.contains("#if os(tvOS)"))
        #expect(source.contains(".moveDisabled"))
        #expect(source.contains(".deleteDisabled"))
        #expect(source.contains("Section(\"Hidden\")"))
        #expect(source.contains("#if !os(macOS)"))
        #expect(source.contains("@Environment(\\.editMode)"))
        #expect(source.contains("@State private var isMacEditing = false"))
        #expect(source.contains("private var isEditing"))
        #expect(source.contains("if isEditing"))
        #expect(source.contains(".id(navigationPreferences.revision)"))
        #expect(settingsSource.contains("@State private var isShowingNavigationSettings = false"))
        #expect(settingsSource.contains("NavigationLink(value: SettingsDestination.navigation)"))
        #expect(settingsSource.contains(".navigationDestination(for: SettingsDestination.self)"))
        #expect(settingsSource.contains(".navigationBarBackButtonHidden(isShowingNavigationSettings)"))
        #expect(!source.contains("Home is always first."))
        #expect(!source.contains("Settings is always last."))
    }

    @Test("warning cleanup removes deprecated and ignored-result call sites")
    func warningCleanupRemovesDeprecatedAndIgnoredResultCallSites() throws {
        let bookSource = try sourceFile(named: "BookReaderView.swift", under: "Sources/Features/Books")
        let carPlaySource = try sourceFile(named: "CarPlaySceneDelegate.swift", under: "Sources/CarPlay")
        let streamTestsSource = try sourceFile(named: "StreamURLBuilderTests.swift", under: "Tests/APlayaNamedGusTests")

        #expect(!bookSource.contains("ReadiumAdapterGCDWebServer"))
        #expect(!bookSource.contains("GCDHTTPServer"))
        #expect(!bookSource.contains("httpServer:"))
        #expect(carPlaySource.contains("Logger(category: .carPlay)"))
        #expect(carPlaySource.contains("performTemplateOperation"))
        #expect(!carPlaySource.contains("try? await interfaceController?.setRootTemplate"))
        #expect(!carPlaySource.contains("try? await interfaceController?.pushTemplate"))
        #expect(!streamTestsSource.contains("try StreamURLBuilder("))
    }

    @Test("video player relies on system close and options chrome")
    func videoPlayerReliesOnSystemCloseAndOptionsChrome() throws {
        let source = try sourceFile(named: "VideoPlayerView.swift", under: "Sources/Features/Player")

        #expect(!source.contains("Close Player"))
        #expect(!source.contains("chevron.backward"))
        #expect(!source.contains(".cancellationAction"))
        #expect(!source.contains("Playback Options"))
        #expect(!source.contains("ellipsis.circle.fill"))
    }

    @Test("Jellyfin mutation send responses are explicitly discarded")
    func jellyfinMutationSendResponsesAreExplicitlyDiscarded() throws {
        let source = try sourceFile(named: "JellyfinMediaProviderSession.swift", under: "Sources/Providers/Jellyfin")

        let expectedDiscardedSends = [
            "_ = try await client.send(Paths.cancelTimer(timerID: id))",
            "_ = try await client.send(Paths.markUnplayedItem(itemID: itemID, userID: userID))",
            "_ = try await client.send(Paths.markPlayedItem(itemID: itemID, userID: userID))",
            "_ = try await client.send(Paths.unmarkFavoriteItem(itemID: itemID, userID: userID))",
            "_ = try await client.send(Paths.markFavoriteItem(itemID: itemID, userID: userID))",
            "func reportPlaybackStart(context: PlaybackReportContext, positionTicks: Int, isPaused: Bool) async throws {\n        _ = try await client.send(",
            "func reportPlaybackProgress(context: PlaybackReportContext, positionTicks: Int, isPaused: Bool) async throws {\n        _ = try await client.send(",
            "func reportPlaybackStopped(context: PlaybackReportContext, positionTicks: Int) async throws {\n        _ = try await client.send(",
            "func reportBookProgress(itemID: String, fraction: Double) async throws {\n        _ = try await client.send(",
        ]

        for expected in expectedDiscardedSends {
            #expect(source.contains(expected))
        }
    }

    @Test("visionOS video player uses native AVKit experience chrome")
    func visionOSVideoPlayerUsesNativeAVKitExperienceChrome() throws {
        let playerSource = try sourceFile(named: "VideoPlayerView.swift", under: "Sources/Features/Player")
        let platformSource = try sourceFile(named: "PlayerSurface.swift", under: "Sources/Platform")

        #expect(!playerSource.contains("VideoPlayer(player: player)"))
        #expect(playerSource.contains("VisionPlayerSurface(player: player)"))
        #expect(platformSource.contains("#elseif os(visionOS)"))
        #expect(platformSource.contains("struct VisionPlayerSurface: UIViewControllerRepresentable"))
        #expect(platformSource.contains("AVPlayerViewController"))
        #expect(platformSource.contains("experienceController"))
        #expect(platformSource.contains("allowedExperiences"))
        #expect(platformSource.contains(".immersive"))
    }

    @Test("platform app icons use the current primary artwork")
    func platformAppIconsUseCurrentPrimaryArtwork() throws {
        let primaryIcon = try resourceData("Resources/Assets.xcassets/AppIcon.appiconset/icon-ios-1024.png")
        let watchIcon = try resourceData("Resources/Watch/Assets.xcassets/AppIcon.appiconset/icon-watch-1024.png")
        let visionMiddle = try resourceData("Resources/Assets.xcassets/AppIcon.solidimagestack/Middle.solidimagestacklayer/Content.imageset/middle.png")

        #expect(watchIcon == primaryIcon)
        #expect(visionMiddle == primaryIcon)

        let staleIconHashes: Set<String> = [
            "a20498f1e9e809ce53de5d761733c7abb43bb1e1f9e70c4d20d09c59902d01e6",
            "2fedf21eaa9c31ff85659558396ec9adb0d59931774839dd9587ebb5ac4dfe51",
            "b83b1ef220591aa81e41ce633299f08aac2a645c591b8bb3ff4decdfdff6da14",
            "d863900948112a00bd8006b9116a4ff8f5bbd749916981e39970772ae673f8db",
            "26a9fde78f7b0649dca8628c15ac50118ccb0a42995542da450633a125dd9ba4",
            "c23cb3bbf8c2c81ecbadcb944e8d996929ab7b198a10968229cc7e0fafc91883",
            "f6d86df071128e05dfc75e1c792e59cab3760ea80e2fba5488f51ef31be0527e",
            "9bd96f729525ed0694eba0d7c94f98f68ae3df316e2833fa63be957d60d8a7bc",
            "ecf6df7866a807e31d0f32879430fcfcb0ee50d6dff767706e998c2bf574891f",
        ]
        let platformIconPaths = [
            "Resources/Assets.xcassets/AppIcon.solidimagestack/Front.solidimagestacklayer/Content.imageset/front.png",
            "Resources/Assets.xcassets/AppIcon.solidimagestack/Middle.solidimagestacklayer/Content.imageset/middle.png",
            "Resources/Assets.xcassets/AppIcon.solidimagestack/Back.solidimagestacklayer/Content.imageset/back.png",
            "Resources/Assets.xcassets/AppIcon.brandassets/App Icon.imagestack/Front.imagestacklayer/Content.imageset/front-400.png",
            "Resources/Assets.xcassets/AppIcon.brandassets/App Icon.imagestack/Front.imagestacklayer/Content.imageset/front-800.png",
            "Resources/Assets.xcassets/AppIcon.brandassets/App Icon.imagestack/Back.imagestacklayer/Content.imageset/back-400.png",
            "Resources/Assets.xcassets/AppIcon.brandassets/App Icon.imagestack/Back.imagestacklayer/Content.imageset/back-800.png",
            "Resources/Assets.xcassets/AppIcon.brandassets/App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/store-front-1280.png",
            "Resources/Assets.xcassets/AppIcon.brandassets/App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/store-back-1280.png",
        ]

        for path in platformIconPaths {
            #expect(try !staleIconHashes.contains(sha256Hex(resourceData(path))))
        }
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
        let iOSEntitlements = try sourceFile(named: "Gus-iOS.entitlements", under: "Config")

        #expect(source.contains("GroupActivity"))
        #expect(source.contains("sessions()"))
        #expect(source.contains("coordinateWithSession"))
        #expect(source.contains("com.apple.developer.group-session"))
        #expect(iOSEntitlements.contains("com.apple.developer.group-session"))
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

    @Test("Shared with You uses Universal Links and Apple framework bridges")
    func sharedWithYouUsesUniversalLinksAndFrameworkBridges() throws {
        let bridgeSource = try sourceFile(named: "SharedWithYouSupport.swift", under: "Sources/Platform")
        let homeSource = try sourceFile(named: "HomeView.swift", under: "Sources/Features/Home")
        let detailSource = try sourceFile(named: "ItemDetailView.swift", under: "Sources/Features/Item")
        let projectSource = try sourceFile(named: "project.yml", under: "")

        #expect(bridgeSource.contains("SWHighlightCenter"))
        #expect(bridgeSource.contains("SWAttributionView"))
        #expect(bridgeSource.contains("ContentLink(url: highlight.url)"))
        #expect(bridgeSource.contains("#if canImport(SharedWithYou) && (os(iOS) || os(tvOS) || os(macOS))"))
        #expect(homeSource.contains("sharedWithYouItems"))
        #expect(homeSource.contains("SharedWithYouStore"))
        #expect(detailSource.contains("SharedWithYouAttributionView"))
        #expect(projectSource.contains("SharedWithYou.framework"))
        #expect(projectSource.contains("destinationFilters: [iOS, tvOS, macOS]"))
    }

    @Test("Universal Links are wired through entitlements and AASA documentation")
    func universalLinksAreWiredThroughEntitlementsAndAASADocumentation() throws {
        let contentLinkSource = try sourceFile(named: "ContentLink.swift", under: "Sources/Models")
        let appSource = try sourceFile(named: "GusApp.swift", under: "Sources/App")
        let iOSEntitlements = try sourceFile(named: "Gus-iOS.entitlements", under: "Config")
        let macEntitlements = try sourceFile(named: "Gus.entitlements", under: "Config")
        let tvOSEntitlements = try sourceFile(named: "Gus-tvOS.entitlements", under: "Config")
        let visionEntitlements = try sourceFile(named: "Gus-SharePlay.entitlements", under: "Config")
        let aasa = try sourceFile(named: "apple-app-site-association.json", under: "Documentation/AppStore")

        #expect(contentLinkSource.contains("gus.ericslutz.dev"))
        #expect(contentLinkSource.contains("universalURL"))
        #expect(appSource.contains("NSUserActivityTypeBrowsingWeb"))
        #expect(appSource.contains("activity.webpageURL"))
        #expect(iOSEntitlements.contains("applinks:gus.ericslutz.dev"))
        #expect(macEntitlements.contains("applinks:gus.ericslutz.dev"))
        #expect(tvOSEntitlements.contains("applinks:gus.ericslutz.dev"))
        #expect(visionEntitlements.contains("applinks:gus.ericslutz.dev"))
        #expect(aasa.contains("QS3GC3CT43.dev.ericslutz.gus"))
        #expect(aasa.contains("\"/item/*\""))
        #expect(aasa.contains("\"/play/*\""))
    }

    @Test("Declared Age Range is wired only for iOS and macOS app entitlements")
    func declaredAgeRangeIsWiredOnlyForIOSAndMacOSEntitlements() throws {
        let sharedConfig = try sourceFile(named: "Shared.xcconfig", under: "Config")
        let iOSEntitlements = try sourceFile(named: "Gus-iOS.entitlements", under: "Config")
        let macEntitlements = try sourceFile(named: "Gus.entitlements", under: "Config")
        let tvOSEntitlements = try sourceFile(named: "Gus-tvOS.entitlements", under: "Config")
        let visionEntitlements = try sourceFile(named: "Gus-SharePlay.entitlements", under: "Config")

        #expect(sharedConfig.contains("CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*] = Config/Gus-iOS.entitlements"))
        #expect(sharedConfig.contains("CODE_SIGN_ENTITLEMENTS[sdk=macosx*] = Config/Gus.entitlements"))
        #expect(iOSEntitlements.contains("com.apple.developer.declared-age-range"))
        #expect(macEntitlements.contains("com.apple.developer.declared-age-range"))
        #expect(!tvOSEntitlements.contains("com.apple.developer.declared-age-range"))
        #expect(!visionEntitlements.contains("com.apple.developer.declared-age-range"))
    }

    @Test("tvOS App Group and Top Shelf entitlement wiring are restored")
    func tvOSAppGroupAndTopShelfEntitlementWiringAreRestored() throws {
        let tvOSEntitlements = try sourceFile(named: "Gus-tvOS.entitlements", under: "Config")
        let topShelfEntitlements = try sourceFile(named: "GusTopShelf.entitlements", under: "Config")
        let projectSource = try sourceFile(named: "project.yml", under: "")
        let snapshotSource = try sourceFile(named: "TopShelfSnapshot.swift", under: "Sources/Models")
        let homeStoreSource = try sourceFile(named: "HomeStore.swift", under: "Sources/Stores")

        #expect(tvOSEntitlements.contains("com.apple.security.application-groups"))
        #expect(tvOSEntitlements.contains("group.dev.ericslutz.gus"))
        #expect(topShelfEntitlements.contains("com.apple.security.application-groups"))
        #expect(topShelfEntitlements.contains("group.dev.ericslutz.gus"))
        #expect(!topShelfEntitlements.contains("com.apple.developer.group-session"))
        #expect(!topShelfEntitlements.contains("com.apple.developer.associated-domains"))
        #expect(projectSource.contains("CODE_SIGN_ENTITLEMENTS: Config/GusTopShelf.entitlements"))
        #expect(snapshotSource.contains("containerURL(forSecurityApplicationGroupIdentifier"))
        #expect(homeStoreSource.contains("TopShelfSnapshot(items: Array(shelfItems)).save()"))
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

    private func resourceData(_ relativePath: String) throws -> Data {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: relativePath)

        return try Data(contentsOf: sourceURL)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
