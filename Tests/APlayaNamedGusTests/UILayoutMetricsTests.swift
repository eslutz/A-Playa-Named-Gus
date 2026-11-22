import CoreGraphics
import CryptoKit
import Foundation
@testable import Gus
import ImageIO
import SwiftUI
import Testing
#if os(iOS)
    import UIKit
#endif

@Suite("UI layout metrics")
struct UILayoutMetricsTests {
    #if os(iOS)
        @MainActor
        private func layoutSession(_ provider: FakeMediaProviderSession? = nil) throws -> SessionStore {
            let url = try #require(URL(string: "https://example.invalid"))
            return SessionStore(
                client: JellyfinClientFactory.makeClient(url: url),
                user: .init(id: "layout-user", name: "User", serverID: "layout"),
                server: .init(id: "layout", name: "Server", url: url),
                mediaProvider: provider ?? FakeMediaProviderSession(capabilities: ProviderCapabilities())
            )
        }

        @MainActor
        @Test("Later cast credits grow the rail and accessibility sizes reflow the credits vertically")
        func castCreditWrapping() throws {
            let session = try layoutSession()
            let navigation = RootNavigationState(searchHistory: session.searchHistory)
            let brief = (0 ..< 7).map { MediaPerson(id: String($0), name: "Person", role: "Actor") }
            let long = MediaPerson(id: "long", name: "A Performer with a Longer Name", role: "Featured performer and assistant to the director of photography")
            func height(_ credits: [MediaPerson], _ size: DynamicTypeSize) -> CGFloat {
                let item = MediaItem(id: "film", people: credits, type: .movie)
                let rail = CastRail(item: item)
                    .environment(session).environment(navigation)
                    .environment(\.dynamicTypeSize, size)
                    .frame(width: 360)
                    .fixedSize(horizontal: false, vertical: true)
                return UIHostingController(rootView: rail).sizeThatFits(in: CGSize(width: 360, height: 2000)).height
            }
            #expect(height(brief + [long], .large) > height(brief, .large) + 20)
            #expect(height(Array(brief.prefix(2)), .accessibility3) > height([brief[0]], .accessibility3) + 44)
        }

        @MainActor
        @Test("Episode cards grow from one to three lines with no empty watched row")
        func episodeCaptionWrapping() throws {
            let session = try layoutSession()
            func height(_ lines: Int, _ size: DynamicTypeSize, watched: Bool = false) -> CGFloat {
                let title = Array(repeating: "Episode", count: lines).joined(separator: "\n")
                let item = MediaItem(id: "episode", name: title, type: .episode, userData: .init(isWatched: watched))
                let card = EpisodeCard(episode: item).environment(session)
                    .environment(\.dynamicTypeSize, size)
                    .frame(width: 256)
                    .fixedSize(horizontal: false, vertical: true)
                return UIHostingController(rootView: card).sizeThatFits(in: CGSize(width: 256, height: 2000)).height
            }
            let headline = Text("Episode").font(.headline).environment(\.dynamicTypeSize, .large)
            let line = UIHostingController(rootView: headline).sizeThatFits(in: CGSize(width: 256, height: 200)).height
            let short = height(1, .large)
            #expect(abs(short - (144 + ContentSpacing.group + line)) <= 2)
            #expect(height(1, .large, watched: true) == short)
            #expect(height(2, .large) > short + line / 2)
            #expect(height(3, .large) > height(2, .large) + line / 2)
            #expect(height(4, .large) == height(3, .large))
            #expect(height(4, .accessibility3) > height(3, .accessibility3) + line / 2)
        }

        @MainActor
        @Test("A later episode sets the rail height without loading offscreen artwork or reserving missing synopses")
        func episodeRailHeightAndLazyArtwork() async throws {
            let provider = FakeMediaProviderSession(capabilities: .init())
            let session = try layoutSession(provider)
            let series = MediaItem(id: "series", type: .series)
            let navigation = RootNavigationState(searchHistory: session.searchHistory)
            func host(lastTitle: String, synopsis: String?) -> UIHostingController<some View> {
                let episodes = (0 ..< 12).map { number in
                    MediaItem(
                        id: "episode-\(number)",
                        name: number == 11 ? lastTitle : "Pilot",
                        officialRating: "G",
                        overview: number == 11 ? synopsis : nil,
                        type: .episode
                    )
                }
                let rail = SeriesEpisodeRail(episodes: episodes, series: series, seasonID: "season")
                    .environment(session).environment(navigation)
                    .environment(UpNextStore()).environment(PlaybackRefreshStore())
                    .environment(\.dynamicTypeSize, .large).frame(width: 360)
                    .fixedSize(horizontal: false, vertical: true)
                return UIHostingController(rootView: rail)
            }

            let proposal = CGSize(width: 360, height: 2000)
            let empty = host(lastTitle: "Pilot", synopsis: nil).sizeThatFits(in: proposal).height
            let one = host(lastTitle: "Pilot", synopsis: "A synopsis.").sizeThatFits(in: proposal).height
            let final = host(lastTitle: "First\nSecond\nThird", synopsis: "A synopsis.")
            let three = final.sizeThatFits(in: proposal).height
            #expect(one > empty + ContentSpacing.caption)
            #expect(three > one + 25)

            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.rootViewController = final
            window.isHidden = false
            defer { window.isHidden = true }
            for _ in 0 ..< 100 where !provider.backdropRequestIDs.contains("episode-0") {
                final.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(provider.backdropRequestIDs.contains("episode-0"))
            #expect(!provider.backdropRequestIDs.contains("episode-11"))
        }

        @MainActor
        @Test("For You preserves square artwork and aligns its lower edge with portrait artwork")
        func mixedArtworkBaseline() throws {
            func render(_ type: MediaItemType) throws -> (height: Int, artworkCenter: Double) {
                var card = PosterCard(item: .init(name: "Title", type: type), imageURL: nil, alignsMixedArtwork: true)
                card.placeholderSymbol = "square.fill"
                card.subtitle = nil
                let image = try #require(ImageRenderer(content: card.frame(width: 120)
                        .fixedSize(horizontal: false, vertical: true)
                        .environment(\.colorScheme, .light)
                        .environment(\.dynamicTypeSize, .large)
                        .background(.white)).cgImage)
                let context = try #require(CGContext(
                    data: nil,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                let pixels = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
                // Both placeholders use the same SF Symbol. Its center is the image
                // center, even if the system changes symbol padding or antialiasing.
                let ink = (0 ..< min(180, image.height)).filter { pixels[$0 * image.width + image.width / 2] < 165 }
                let first = try #require(ink.first), last = try #require(ink.last)
                return (image.height, Double(first + last) / 2)
            }
            let movie = try render(.movie), audiobook = try render(.audioBook)
            #expect(movie.height == audiobook.height)
            #expect(abs((audiobook.artworkCenter - movie.artworkCenter) - 30) < 2)
        }

        @MainActor
        @Test("The iPhone canvas retains its signed-in content across compact and regular widths")
        func canvasPreservesContentDuringRotation() async throws {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            var creations = 0
            var observed: UserInterfaceSizeClass?
            let probe = CanvasIdentityProbe(created: { creations += 1 }, updated: { observed = $0 })
            let host = UIHostingController(rootView: probe.gusIPhoneCanvas())
            host.traitOverrides.horizontalSizeClass = .compact
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }
            for expected in [UserInterfaceSizeClass.compact, .regular, .compact] {
                host.traitOverrides.horizontalSizeClass = expected == .compact ? .compact : .regular
                for _ in 0 ..< 100 where observed != expected {
                    host.view.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(20))
                }
                #expect(observed == expected)
                #expect(creations == 1)
            }
        }

        @MainActor
        @Test("Detail primary actions preserve the Play button dimensions for Gus and custom accents", arguments: [false, true])
        func primaryActionSize(customAccent: Bool) throws {
            let actions: [(LocalizedStringKey, String)] = [
                ("Play", "play.fill"), ("Resume", "play.fill"), ("Read", "book.fill"),
                ("Continue Reading", "book.fill"), ("Request", "plus.circle"), ("Request Seasons", "plus.circle"),
            ]
            let sizes = actions.map { title, symbol in
                let view = DetailPrimaryButton(title, systemImage: symbol) {}
                    .environment(\.gusThemeFill, customAccent ? .mint : .accentColor)
                    .environment(\.gusThemeForeground, customAccent ? .black : .gusProminentActionForeground)
                return UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 390, height: 200))
            }
            let play = try #require(sizes.first)
            #expect(play.width == DetailActionMetrics.maximumRowWidth)
            #expect(play.height >= 44)
            for (index, size) in sizes.enumerated() {
                #expect(size == play, "Primary action symbol: \(actions[index].1)")
            }
        }

        @Test("Foreground covers fit the available height without changing aspect ratio", arguments: [2.0 / 3.0, 1.0])
        @MainActor func foregroundCoverFitsShortViewport(ratio: Double) throws {
            let height = 220
            let header = DetailCoverHeader {
                Color.red.aspectRatio(ratio, contentMode: .fit)
            } summary: {
                Text("Title")
            }
            .frame(width: 700, height: CGFloat(height), alignment: .top)
            .clipped()
            .environment(\.detailArtworkViewportHeight, CGFloat(height))
            let image = try #require(ImageRenderer(content: header).cgImage)
            let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
            var horizontal = IndexSet()
            var vertical = IndexSet()
            for y in 0 ..< image.height {
                for x in 0 ..< image.width {
                    let index = (y * image.width + x) * 4
                    if pixels[index] > 220, pixels[index + 1] < 100, pixels[index + 2] < 100 {
                        horizontal.insert(x)
                        vertical.insert(y)
                    }
                }
            }
            #expect(vertical.first == 24)
            #expect(vertical.last == height - 1)
            #expect(abs(vertical.count - (height - 24)) <= 1)
            #expect(abs(Double(horizontal.count) - Double(vertical.count) * ratio) <= 1)
        }

        @Test("Backdrop art leaves system status text legible in either appearance", arguments: [false, true])
        @MainActor func backdropStatusContrast(dark: Bool) throws {
            let artwork: Color = dark ? .white : .black
            let header = DetailBackdropHeader { artwork } summary: { EmptyView() }
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.detailArtworkTopInset, 76)
                .frame(width: 320)
                .background(artwork)
            let image = try #require(ImageRenderer(content: header).cgImage)
            let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
            func channel(y: Int) -> Double {
                Double(pixels[(y * image.width + image.width / 2) * 4]) / 255
            }
            let value = channel(y: 30)
            let luminance = value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            let contrast = dark ? 1.05 / (luminance + 0.05) : (luminance + 0.05) / 0.05
            #expect(contrast >= 4.5)
            #expect(channel(y: 115) == (dark ? 1 : 0))
        }
    #endif

    @MainActor
    @Test("Secondary controls start at the leading edge on every line", arguments: [2, 3, 5], [false, true])
    func secondaryActionGaps(count: Int, rightToLeft: Bool) throws {
        #if os(tvOS)
            let gap = 24
        #elseif os(visionOS)
            let gap = 16
        #else
            let gap = 8
        #endif
        let step = 44 + gap
        for width in [360, 120] {
            let row = DetailActionLayout {
                ForEach(0 ..< count, id: \.self) { _ in
                    Color.black.frame(width: 44, height: 44)
                }
            }
            .frame(width: CGFloat(width))
            .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
            .background(.white)
            let image = try #require(ImageRenderer(content: row).cgImage)
            let context = try #require(CGContext(
                data: nil, width: width, height: image.height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: image.height))
            let pixels = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
            let perLine = min(count, (width + gap) / step)
            let lines = (count + perLine - 1) / perLine
            #expect(image.height == lines * 44 + (lines - 1) * gap)
            var measuredCount = 0
            for y in stride(from: 22, to: image.height, by: step) {
                let occupied = (0 ..< width).filter { leadingOffset in
                    let x = rightToLeft ? width - 1 - leadingOffset : leadingOffset
                    return pixels[y * width + x] < 128
                }
                let controls = occupied.count / 44
                measuredCount += controls
                #expect(controls > 0 && controls <= perLine)
                #expect(occupied == (0 ..< controls).flatMap { index in Array(index * step ..< index * step + 44) })
            }
            #expect(measuredCount == count)
        }
    }

    @MainActor
    @Test("Empty detail sections consume no inter-section space")
    func visibleDetailSectionSpacing() throws {
        let layout = DetailSectionLayout {
            Color.clear.frame(height: 0)
            Color.red.frame(height: 30)
            VStack { EmptyView() }.frame(height: 0)
            Color.blue.frame(height: 40)
            Color.clear.frame(height: 0)
        }
        let image = try #require(ImageRenderer(content: layout.frame(width: 375)).cgImage)
        #expect(image.height == 30 + Int(DetailPageMetrics.sectionSpacing) + 40)
    }

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

    @Test("video keeps native transport while supplementing source and semantic track choices")
    func videoPlayerReliesOnSystemCloseAndOptionsChrome() throws {
        let source = try sourceFile(named: "VideoPlayerView.swift", under: "Sources/Features/Player")

        #expect(!source.contains("Close Player"))
        #expect(!source.contains("chevron.backward"))
        #expect(!source.contains(".cancellationAction"))
        // Native Menu/confirmationDialog choices are now approved; a replacement timeline is not.
        #expect(!source.contains("Slider("))
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
        #expect(playerSource.contains("VisionPlayerSurface(player: player, controlsEnabled: controlsEnabled)"))
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
        #expect(watchIcon == primaryIcon)

        // Native depth layers deliberately differ from the flattened store icon.
        // Validate each full-bleed background and separate, nonempty foreground.
        let stacks: [(String, String, [(String, Int, Int)])] = [
            ("AppIcon.solidimagestack", "solidimagestacklayer", [("", 1024, 1024)]),
            ("AppIcon.brandassets/App Icon.imagestack", "imagestacklayer", [("-400", 400, 240), ("-800", 800, 480)]),
            ("AppIcon.brandassets/App Icon - App Store.imagestack", "imagestacklayer", [("-1280", 1280, 768)]),
        ]
        for (stack, layerExtension, sizes) in stacks {
            for (suffix, width, height) in sizes {
                var foregrounds: [[UInt8]] = []
                for layer in ["Back", "Middle", "Front"] {
                    let prefix = suffix == "-1280" ? "store-" : ""
                    let path = "Resources/Assets.xcassets/\(stack)/\(layer).\(layerExtension)/Content.imageset/\(prefix)\(layer.lowercased())\(suffix).png"
                    let pixels = try iconLayerPixels(resourceData(path), width: width, height: height)
                    let alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
                    if layer == "Back" {
                        #expect(alpha.allSatisfy { $0 == 255 })
                    } else {
                        #expect(alpha.contains { $0 > 0 })
                        #expect(alpha.contains { $0 == 0 })
                        foregrounds.append(pixels)
                    }
                }
                #expect(foregrounds[0] != foregrounds[1])
            }
        }

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
        #expect(homeStoreSource.contains("TopShelfSnapshot(items: Array(shelfItems), serverID: session.server.id, userID: session.user.id).save()"))
    }

    private func iconLayerPixels(_ data: Data, width: Int, height: Int) throws -> [UInt8] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == width && image.height == height)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(
                data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.clear(rect)
            context.draw(image, in: rect)
        }
        return pixels
    }

    private func sourceFile(named fileName: String, under relativePath: String) throws -> String {
        let path = relativePath.isEmpty ? fileName : "\(relativePath)/\(fileName)"
        return try String(contentsOf: RepositoryTestFixtures.url(for: path), encoding: .utf8)
    }

    private func resourceData(_ relativePath: String) throws -> Data {
        try Data(contentsOf: RepositoryTestFixtures.url(for: relativePath))
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

#if os(iOS)
    private struct CanvasIdentityProbe: UIViewRepresentable {
        @Environment(\.horizontalSizeClass) private var sizeClass
        let created: () -> Void
        let updated: (UserInterfaceSizeClass?) -> Void

        func makeUIView(context: Context) -> UIView {
            created()
            return UIView()
        }

        func updateUIView(_ view: UIView, context: Context) {
            updated(sizeClass)
        }
    }
#endif

#if os(iOS)
    @MainActor
    private final class ThemeControlRegions {
        weak var picker: UIView?
        weak var toggle: UIView?
    }

    /// Resolve UIKit coordinates after a system sheet has attached to its window.
    private struct ControlRegion: UIViewRepresentable {
        let install: (UIView) -> Void
        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.isUserInteractionEnabled = false
            install(view)
            return view
        }

        func updateUIView(_ view: UIView, context: Context) {}
    }

    private struct NativeThemeControls: View {
        let regions: ThemeControlRegions
        var body: some View {
            VStack {
                Picker("Quality", selection: .constant(1)) {
                    Text("Original").tag(1)
                    Text("High").tag(2)
                }
                .pickerStyle(.menu)
                .menuIndicator(.visible)
                .labelsHidden()
                .background { ControlRegion { regions.picker = $0 } }

                Toggle("Enabled", isOn: .constant(true))
                    .gusSwitchTint()
                    .background { ControlRegion { regions.toggle = $0 } }
            }
            .padding()
            .frame(width: 300)
        }
    }

    private struct PresentedThemeControls: View {
        let regions: ThemeControlRegions
        @State private var showing = false

        var body: some View {
            Color.clear.onAppear { showing = true }
                .sheet(isPresented: $showing) { NativeThemeControls(regions: regions) }
        }
    }

    @MainActor
    extension UILayoutMetricsTests {
        @Test("Open sheets update native menu pickers and switches when the custom theme changes")
        func nativeThemeInPresentedControls() async throws {
            let suite = "gus-theme-render-" + UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(ThemePreference.custom.rawValue, forKey: ThemePreference.defaultsKey)
            defaults.set("004F60", forKey: ThemePreference.customAccentKey)
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let regions = ThemeControlRegions()
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = UIHostingController(rootView: PresentedThemeControls(regions: regions)
                .gusTheme().defaultAppStorage(defaults))
            window.isHidden = false
            defer { window.isHidden = true }
            for _ in 0 ..< 100 where regions.toggle?.window == nil {
                try await Task.sleep(for: .milliseconds(25))
            }
            let toggle = try #require(regions.toggle), picker = try #require(regions.picker)
            try await Task.sleep(for: .milliseconds(500))

            func snapshot(of rect: CGRect, in window: UIWindow) -> UIImage {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                return UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
                    window.drawHierarchy(in: window.bounds.offsetBy(dx: -rect.minX, dy: -rect.minY), afterScreenUpdates: true)
                }
            }

            func controlPixels(in view: UIView) throws -> (bytes: [UInt8], width: Int, height: Int) {
                let window = try #require(view.window)
                let image = try #require(snapshot(of: view.convert(view.bounds, to: window).integral, in: window).cgImage)
                let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
                let buffer = try #require(CGContext(
                    data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                buffer.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                let bytes = try #require(buffer.data?.assumingMemoryBound(to: UInt8.self))
                return (Array(UnsafeBufferPointer(start: bytes, count: image.width * image.height * 4)), image.width, image.height)
            }

            func countAccentPixels(in view: UIView, accent: ThemeAccent) throws -> Int {
                let (bytes, _, _) = try controlPixels(in: view)
                let red = Int(accent.red * 255), green = Int(accent.green * 255), blue = Int(accent.blue * 255)
                return stride(from: 0, to: bytes.count, by: 4).count { i in
                    abs(Int(bytes[i]) - red) < 24 && abs(Int(bytes[i + 1]) - green) < 24 && abs(Int(bytes[i + 2]) - blue) < 24
                }
            }

            func switchContrast(in view: UIView) throws -> (thumb: Double, surface: Double) {
                let (bytes, width, height) = try controlPixels(in: view)
                var histogram: [Int: Int] = [:]
                // The native switch occupies the trailing edge of the labeled row.
                // Its middle band includes the opaque thumb, active track and canvas.
                for y in height / 3 ..< 2 * height / 3 {
                    for x in max(0, width - 90) ..< width {
                        let i = (y * width + x) * 4
                        let rgb = Int(bytes[i]) << 16 | Int(bytes[i + 1]) << 8 | Int(bytes[i + 2])
                        histogram[rgb, default: 0] += 1
                    }
                }
                let colors = histogram.sorted { $0.value > $1.value }.map { entry in
                    ThemeAccent(red: Double(entry.key >> 16) / 255, green: Double(entry.key >> 8 & 255) / 255, blue: Double(entry.key & 255) / 255)
                }
                let track = try #require(colors.first { max($0.red, $0.green, $0.blue) - min($0.red, $0.green, $0.blue) > 0.09 })
                let thumb = try #require(colors.first { $0.luminance > 0.8 })
                let surface = try #require(colors.first { $0.luminance < 0.05 })
                return ((thumb.luminance + 0.05) / (track.luminance + 0.05), (track.luminance + 0.05) / (surface.luminance + 0.05))
            }

            for hex in ["004F60", "600044"] {
                defaults.set(hex, forKey: ThemePreference.customAccentKey)
                let accent = try #require(ThemeAccent(hex: hex))
                let track = accent.switchTrack(onDark: true), tint = accent.readable(onDark: true)
                var trackCount = 0, tintCount = 0
                for _ in 0 ..< 20 {
                    trackCount = try countAccentPixels(in: toggle, accent: track)
                    tintCount = try countAccentPixels(in: picker, accent: tint)
                    if trackCount > 20, tintCount > 5 {
                        break
                    }
                    try await Task.sleep(for: .milliseconds(50))
                }
                let controlWindow = try #require(picker.window)
                let bounds = picker.convert(picker.bounds, to: controlWindow)
                    .union(toggle.convert(toggle.bounds, to: controlWindow)).insetBy(dx: -8, dy: -8).integral
                let data = try #require(snapshot(of: bounds, in: controlWindow).pngData())
                Attachment.record(Array(data), named: "Native-dark-controls-\(hex).png")
                let contrast = try switchContrast(in: toggle)
                #expect(contrast.thumb >= 3)
                #expect(contrast.surface >= 3)
                #expect(trackCount > 20, "Native switch uses its contrast-adjusted track for \(hex)")
                #expect(tintCount > 5, "Native menu picker uses the readable text color for \(hex)")
            }
        }
    }
#endif
