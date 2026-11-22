import Foundation
@testable import Gus
import Testing
#if os(iOS) || os(tvOS)
    import UIKit
#endif

struct ThemeAndLatestMediaTests {
    @Test func opaqueAccentStorageRejectsMalformedValues() {
        #expect(ThemeAccent(hex: "ff7F00")?.hex == "FF7F00")
        for input in ["", "#123456", "12345", "12345678", "zzzzzz", "１２３４５６"] {
            #expect(ThemeAccent(hex: input) == nil)
        }
        #expect(ThemeAccent(red: .nan, green: 2, blue: -1).hex == "00FF00")
        #expect(ThemePreference(rawValue: "unknown") == nil)
    }

    @Test func customAccentsRetainReadableForegroundsAndTint() throws {
        for hex in ["FFFFFF", "FFFF00", "000000", "4F7C82", "800080", "FF0000"] {
            let accent = try #require(ThemeAccent(hex: hex))
            let foregroundContrast = accent.usesBlackForeground ? (accent.luminance + 0.05) / 0.05 : 1.05 / (accent.luminance + 0.05)
            #expect(foregroundContrast >= 4.5)
            #expect(1.05 / (accent.readable(onDark: false).luminance + 0.05) >= 4.5)
            #expect((accent.readable(onDark: true).luminance + 0.05) / 0.05 >= 4.5)
        }
    }

    #if os(iOS) || os(tvOS)
        @Test @MainActor func appleProminentLabelContrastTracksSystemBlue() throws {
            for appearance in [UIUserInterfaceStyle.light, .dark] {
                for contrast in [UIAccessibilityContrast.normal, .high] {
                    let traits = UITraitCollection {
                        $0.userInterfaceStyle = appearance
                        $0.accessibilityContrast = contrast
                    }
                    let fill = UIColor.systemBlue.resolvedColor(with: traits)
                    let label = ThemeAccent.appleActionForeground.resolvedColor(with: traits)
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                    try #require(fill.getRed(&r, green: &g, blue: &b, alpha: nil))
                    let luminance = ThemeAccent(red: Double(r), green: Double(g), blue: Double(b)).luminance
                    let whiteContrast = 1.05 / (luminance + 0.05)
                    #expect(label.isEqual(whiteContrast >= 4.5 ? UIColor.white : UIColor.black))
                    #expect((label.isEqual(UIColor.white) ? whiteContrast : (luminance + 0.05) / 0.05) >= 4.5)
                }
            }
        }
    #endif

    @Test func switchTracksContrastWithThumbAndCanvas() throws {
        for hex in ["000000", "FFFFFF", "FFFF00", "FF0000", "4F7C82", "112244"] {
            let accent = try #require(ThemeAccent(hex: hex))
            for dark in [false, true] {
                let track = accent.switchTrack(onDark: dark).luminance
                let canvas = dark ? 0.024 : 0.90
                #expect((max(canvas, track) + 0.05) / (min(canvas, track) + 0.05) >= 3)
                #expect(1.05 / (track + 0.05) >= 3)
            }
        }
        #expect(ThemeAccent.gus.switchTrack(onDark: true) == .gus)
    }

    @Test func seriesCardProgressUsesSeriesDataAndPreference() {
        let progress = MediaUserData(playedPercentage: 35)
        let series = MediaItem(name: "Series", type: .series, userData: progress)
        let episode = MediaItem(indexNumber: 2, name: "Series", seriesID: "s", seriesName: "Series", type: .episode, userData: progress)
        #expect(series.cardProgress(showSeriesProgress: false) == nil)
        #expect(series.cardProgress(showSeriesProgress: true) == 0.35)
        #expect(episode.cardProgress(showSeriesProgress: false) == 0.35)
        #expect(episode.latestTVDisplayItem.cardProgress(showSeriesProgress: true) == nil)
        #expect(episode.displayTitle == "Episode 2")
        #expect(series.mediaAccessibility(showSeriesProgress: false).value != series.mediaAccessibility(showSeriesProgress: true).value)
    }

    @Test func televisionAccentInputPreservesStorageRules() {
        #expect(ThemeAccent.userInput("  #ff7f00\n")?.hex == "FF7F00")
        #expect(ThemeAccent.userInput("4f7c82") == .gus)
        for input in ["#FFF", "##123456", "12345678", "１２３４５６", "12345G", ""] {
            #expect(ThemeAccent.userInput(input) == nil)
        }
        #expect(Set(ThemeAccentPreset.allCases.map(\.rawValue)).count == 8)
        for preset in ThemeAccentPreset.allCases {
            #expect(ThemeAccent(hex: preset.rawValue)?.hex == preset.rawValue)
        }
    }

    @Test @MainActor func latestFeedSpansLibrariesAndPromotesShowsAcrossPages() async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var captured: MediaItemQuery?
        provider.itemsHandler = { query in
            captured = query
            return MediaItemPage(items: [], totalRecordCount: 0)
        }
        _ = try await provider.latestMedia(kind: .movies, startIndex: 60, limit: 60)
        #expect(captured?.parentID == nil)
        #expect(captured?.includeTypes == [.movie])
        #expect(captured?.sort == .recentlyAdded)
        #expect(captured?.startIndex == 60)
        #expect(captured?.isRecursive == true)
        let shows = LatestMediaKind.shows.displayItems([
            MediaItem(id: "e1", seriesID: "s1", seriesName: "First Show", type: .episode),
            MediaItem(id: "s1", type: .series),
            MediaItem(id: "e2", seriesID: "s2", seriesName: "Second Show", type: .episode),
        ])
        #expect(shows.compactMap(\.id) == ["s1", "s2"])
        #expect(shows.allSatisfy { $0.type == .series })
        #expect(LatestMediaKind.music.includeTypes == [.musicAlbum])
    }
}
