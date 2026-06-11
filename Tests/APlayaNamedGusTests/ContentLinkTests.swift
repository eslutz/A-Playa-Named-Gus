import Foundation
@testable import Gus
import Testing

@Suite("Content links")
struct ContentLinkTests {
    @Test("item and play URLs round-trip")
    func urlRoundTrip() {
        let item = ContentLink.item(id: "778975ecc43b55232b4330c87917f4eb")
        let play = ContentLink.play(id: "abc123")

        #expect(item.url.absoluteString == "gus://item/778975ecc43b55232b4330c87917f4eb")
        #expect(play.url.absoluteString == "gus://play/abc123")
        #expect(ContentLink(url: item.url) == item)
        #expect(ContentLink(url: play.url) == play)
    }

    @Test("rejects non-content URLs")
    func rejectsNonContentURLs() throws {
        #expect(try ContentLink(url: #require(URL(string: "gus://home"))) == nil)
        #expect(try ContentLink(url: #require(URL(string: "gus://item"))) == nil)
        #expect(try ContentLink(url: #require(URL(string: "https://item/abc"))) == nil)
        #expect(try ContentLink(url: #require(URL(string: "gus://unknown/abc"))) == nil)
    }

    @Test("Spotlight identifiers round-trip and refuse other accounts")
    func spotlightIdentifiers() {
        let id = SpotlightIndexer.Identifier.encode(serverID: "s1", userID: "u1", itemID: "item-1")
        #expect(SpotlightIndexer.Identifier.decode(id)?.itemID == "item-1")
        #expect(SpotlightIndexer.Identifier.decode("garbage") == nil)

        #expect(SpotlightIndexer.contentLink(
            forSearchableItemIdentifier: id, currentServerID: "s1", currentUserID: "u1"
        ) == .item(id: "item-1"))
        // A result donated by another account is refused.
        #expect(SpotlightIndexer.contentLink(
            forSearchableItemIdentifier: id, currentServerID: "s2", currentUserID: "u1"
        ) == nil)
        // Signed out: the link is allowed through and resolves (or soft-fails) later.
        #expect(SpotlightIndexer.contentLink(
            forSearchableItemIdentifier: id, currentServerID: nil, currentUserID: nil
        ) == .item(id: "item-1"))
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
