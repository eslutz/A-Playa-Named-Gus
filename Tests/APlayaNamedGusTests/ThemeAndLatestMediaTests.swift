import Foundation
@testable import Gus
import Testing

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
