import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("Media reference recovery")
struct MediaReferenceTests {
    let scope = AccountScope(serverID: "server", userID: "user")

    @Test("unique external identity repairs a missing ID")
    func repairsIdentity() async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        let old = MediaItem(id: "old", name: "Movie", productionYear: 1992, type: .movie)
        var saved = old
        saved.externalIDs = ["Imdb": "tt123"]
        var replacement = old
        replacement.id = "new"
        replacement.externalIDs = saved.externalIDs
        provider.itemHandler = { id in
            if id == "old" {
                throw GusError.notFound
            }
            return replacement
        }
        provider.itemsHandler = { _ in MediaItemPage(items: [replacement], totalRecordCount: 1) }
        let resolver = MediaReferenceResolver(provider: provider, scope: scope)
        let result = try await resolver.resolve(MediaReference(item: saved, scope: scope))
        guard case let .resolved(item) = result else { Issue.record("Expected recovery"); return }
        #expect(item.id == "new")
    }

    @Test("legacy title matches never reconnect automatically")
    func legacyRequiresSelection() async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in throw GusError.notFound }
        provider.itemsHandler = { _ in MediaItemPage(items: [MediaItem(id: "new", name: "Trespass", type: .movie)], totalRecordCount: 1) }
        let resolver = MediaReferenceResolver(provider: provider, scope: scope)
        let result = try await resolver.resolve(MediaReference(item: MediaItem(id: "old", name: "Trespass", type: .movie), scope: scope))
        guard case .requiresSelection = result else { Issue.record("Title cannot prove identity"); return }
    }

    @Test("duplicate editions never reconnect automatically")
    func ambiguousRequiresSelection() async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var old = MediaItem(id: "old", type: .movie)
        old.externalIDs = ["Tmdb": "123"]
        var a = old; a.id = "a"
        var b = old; b.id = "b"
        provider.itemHandler = { _ in throw GusError.notFound }
        provider.itemsHandler = { _ in MediaItemPage(items: [a, b], totalRecordCount: 2) }
        let result = try await MediaReferenceResolver(provider: provider, scope: scope).resolve(MediaReference(item: old, scope: scope))
        guard case let .requiresSelection(items) = result else { Issue.record("Duplicate editions need selection"); return }
        #expect(items.count == 2)
    }

    @Test("network failures do not become deletion")
    func offlineThrows() async {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in throw GusError.offline }
        do {
            _ = try await MediaReferenceResolver(provider: provider, scope: scope).resolve(MediaReference(item: MediaItem(id: "old"), scope: scope))
            Issue.record("Offline must remain retryable")
        } catch { #expect(GusError(from: error) == .offline) }
    }

    @Test("an incomplete catalog cannot authorize a unique replacement")
    func incompleteCatalog() async {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var saved = MediaItem(id: "old", type: .movie)
        saved.externalIDs = ["Imdb": "tt123"]
        var candidate = saved; candidate.id = "new"
        provider.itemHandler = { _ in throw GusError.notFound }
        provider.itemsHandler = { query in
            MediaItemPage(items: query.startIndex == 0 ? [candidate] : [], totalRecordCount: 2)
        }
        do {
            _ = try await MediaReferenceResolver(provider: provider, scope: scope).resolve(MediaReference(item: saved, scope: scope))
            Issue.record("Incomplete scan must throw, not bind")
        } catch { #expect(GusError(from: error) == .offline) }
    }

    @Test("conflicting IDs, wrong years, and wrong episodes cannot match")
    func conflictingIdentity() {
        var a = MediaItem(id: "old", productionYear: 1992, type: .movie)
        a.externalIDs = ["Imdb": "tt123", "Tmdb": "123"]
        var b = a; b.id = "new"; b.externalIDs["Tmdb"] = "456"
        #expect(!MediaReferenceResolver.matches(a, candidate: b))
        b = a; b.id = "new"; b.productionYear = 2011
        #expect(!MediaReferenceResolver.matches(a, candidate: b))
        a.type = .episode; a.seriesID = "series"; a.indexNumber = 1; a.parentIndexNumber = 1
        b = a; b.id = "new"; b.indexNumber = 2
        #expect(!MediaReferenceResolver.matches(a, candidate: b))
    }

    @Test("minimal ID caches cannot bypass saved external identity")
    func cacheIdentityIsolation() async throws {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        var actual = MediaItem(id: "same", type: .movie)
        actual.externalIDs = ["Imdb": "ttB"]
        var saved = actual; saved.externalIDs = ["Imdb": "ttA"]
        provider.itemHandler = { _ in actual }
        provider.itemsHandler = { _ in MediaItemPage(items: [actual], totalRecordCount: 1) }
        let resolver = MediaReferenceResolver(provider: provider, scope: scope)
        _ = try await resolver.currentItem(MediaItem(id: "same"))
        let result = try await resolver.resolve(MediaReference(item: saved, scope: scope))
        guard case .unavailable = result else { Issue.record("A cached locator cannot change the saved identity"); return }
    }

    @Test("remote replacement resume never adopts original progress")
    func replacementResume() {
        let current = MediaItem(id: "new", type: .movie, userData: MediaUserData(playbackPositionTicks: 30))
        #expect(MediaPlaybackIdentity.resumeTicks(requested: 900, originalID: "old", current: current) == 30)
        #expect(MediaPlaybackIdentity.resumeTicks(requested: 900, originalID: "new", current: current) == 900)
        #expect(MediaPlaybackIdentity.resumeTicks(requested: 0, originalID: "old", current: current) == 0)
        #expect(MediaPlaybackIdentity.resumeTicks(requested: 900, originalID: "old", current: MediaItem(id: "new")) == nil)
    }

    @Test("references from other accounts are rejected before network access")
    func refusesOtherAccount() async {
        let provider = FakeMediaProviderSession(capabilities: ProviderCapabilities())
        provider.itemHandler = { _ in Issue.record("Must not query another scope"); return MediaItem() }
        do {
            _ = try await MediaReferenceResolver(provider: provider, scope: scope).resolve(MediaReference(item: MediaItem(id: "item"), scope: AccountScope(serverID: "other", userID: "user")))
            Issue.record("Expected rejection")
        } catch { #expect(GusError(from: error) == .notFound) }
    }
}
