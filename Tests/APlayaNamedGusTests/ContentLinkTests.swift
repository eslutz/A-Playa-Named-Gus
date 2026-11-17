import Foundation
@testable import Gus
import Testing

@Suite("Content links")
struct ContentLinkTests {
    @Test("source, semantic tracks and explicit start survive shared links without media paths")
    func playbackIntentRoundTrip() throws {
        var item = MediaItem(id: "episode", type: .episode)
        item.mediaSources = [MediaSource(id: "cut", transcodingURL: "https://private.invalid/video?api_key=secret")]
        let request = PlaybackRequest(
            item: item,
            streamSelection: PlaybackStreamSelection(audioStreamIndex: 3, subtitleStreamIndex: -1, mediaSourceID: "cut"),
            audioTrack: MediaStreamInfo(index: 3, language: "en", type: .audio),
            startPositionTicks: 123_000_000
        )
        let link = ContentLink.play(id: "episode", serverID: "server", provider: .jellyfin, request: request)
        for url in [link.url, link.universalURL] {
            let parsed = try #require(ContentLink(url: url))
            #expect(parsed.playbackRequest == request.sharingIntent)
            #expect(parsed.playbackRequest?.item.mediaSources.isEmpty == true)
            #expect(parsed.playbackRequest?.subtitleIntent == .off)
            #expect(parsed.playbackRequest?.requestedStartTicks == 123_000_000)
            let payload = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "playback" }?.value)
            let decoded = try String(decoding: #require(Data(base64Encoded: payload)), as: UTF8.self)
            #expect(!decoded.contains("private.invalid"))
            #expect(!decoded.contains("secret"))
        }
        let mismatched = ContentLink.play(id: "another", request: request)
        #expect(ContentLink(url: mismatched.url) == nil)
        #expect(try ContentLink(url: #require(URL(string: "gus://play/episode?playback=invalid"))) == nil)
        #expect(try ContentLink(url: #require(URL(string: "gus://play/episode?server=a&server=b&provider=jellyfin"))) == nil)
    }

    @Test("item and play URLs round-trip")
    func urlRoundTrip() {
        let item = ContentLink.item(id: "778975ecc43b55232b4330c87917f4eb")
        let play = ContentLink.play(id: "abc123")

        #expect(item.url.absoluteString == "gus://item/778975ecc43b55232b4330c87917f4eb")
        #expect(play.url.absoluteString == "gus://play/abc123")
        #expect(ContentLink(url: item.url) == item)
        #expect(ContentLink(url: play.url) == play)
    }

    @Test("universal link URLs round-trip")
    func universalURLRoundTrip() throws {
        let item = ContentLink.item(id: "778975ecc43b55232b4330c87917f4eb")
        let play = ContentLink.play(id: "abc123")

        #expect(item.universalURL.absoluteString == "https://gus.ericslutz.dev/item/778975ecc43b55232b4330c87917f4eb")
        #expect(play.universalURL.absoluteString == "https://gus.ericslutz.dev/play/abc123")
        #expect(ContentLink(url: item.universalURL) == item)
        #expect(ContentLink(url: play.universalURL) == play)

        #expect(try ContentLink(url: #require(URL(string: "https://gus.ericslutz.dev/item/item-1?source=messages"))) == .item(id: "item-1"))
    }

    @Test("rejects non-content URLs")
    func rejectsNonContentURLs() throws {
        #expect(try ContentLink(url: #require(URL(string: "gus://home"))) == nil)
        #expect(try ContentLink(url: #require(URL(string: "gus://item"))) == nil)
        #expect(try ContentLink(url: #require(URL(string: "https://item/abc"))) == nil)
        #expect(try ContentLink(url: #require(URL(string: "https://example.com/item/abc"))) == nil)
        #expect(try ContentLink(url: #require(URL(string: "https://gus.ericslutz.dev/library/abc"))) == nil)
        #expect(try ContentLink(url: #require(URL(string: "http://gus.ericslutz.dev/item/abc"))) == nil)
        #expect(try ContentLink(url: #require(URL(string: "gus://unknown/abc"))) == nil)
    }

    @Test("Spotlight identifiers round-trip and refuse other accounts")
    func spotlightIdentifiers() {
        let id = SpotlightIndexer.Identifier.encode(serverID: "s1", userID: "u1", itemID: "item-1")
        #expect(SpotlightIndexer.Identifier.decode(id)?.itemID == "item-1")
        #expect(SpotlightIndexer.Identifier.decode("garbage") == nil)

        #expect(SpotlightIndexer.contentLink(
            forSearchableItemIdentifier: id, currentServerID: "s1", currentUserID: "u1"
        ) == .item(id: "item-1", serverID: "s1", provider: .jellyfin))
        // A result donated by another account is refused.
        #expect(SpotlightIndexer.contentLink(
            forSearchableItemIdentifier: id, currentServerID: "s2", currentUserID: "u1"
        ) == nil)
        // Signed out: the link is allowed through and resolves (or soft-fails) later.
        #expect(SpotlightIndexer.contentLink(
            forSearchableItemIdentifier: id, currentServerID: nil, currentUserID: nil
        ) == .item(id: "item-1", serverID: "s1", provider: .jellyfin))
    }

    @Test("navigation model stores, fires, and consumes content links once")
    @MainActor
    func navigationModelConsumeOnce() throws {
        let navigation = AppNavigationModel()

        #expect(navigation.contentLinkRequest == 0)
        try navigation.open(url: #require(URL(string: "gus://play/abc")))
        #expect(navigation.contentLinkRequest == 1)
        #expect(navigation.consumeContentLink() == .play(id: "abc"))
        #expect(navigation.consumeContentLink() == nil)

        // Re-opening the same link fires a new request.
        try navigation.open(url: #require(URL(string: "gus://play/abc")))
        #expect(navigation.contentLinkRequest == 2)

        // Fixed routes still work and don't disturb pending content links.
        try navigation.open(url: #require(URL(string: "gus://settings")))
        #expect(navigation.route == .settings)
        #expect(navigation.consumeContentLink() == .play(id: "abc"))
    }
}
