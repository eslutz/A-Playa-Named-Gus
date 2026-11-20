import Foundation
@testable import Gus
import Testing

@Suite("Library intelligence grounding")
struct GusLibraryIntelligenceTests {
    private static let fixture: [MediaItem] = [
        .init(genres: ["Science Fiction"], id: "film", name: "Orbit", overview: "A lunar expedition", people: [.init(name: "Jan Reyes", role: "Commander / Pilot"), .init(name: "Ana Lim", role: "Engineer")], productionYear: 2015, runTimeTicks: 51_000_000_000, type: .movie),
        .init(genres: ["Science Fiction"], id: "series", name: "Colony", people: [.init(name: "Ana Lim", role: "Pilot")], type: .series),
        .init(id: "episode", name: "First Light", seriesName: "Colony", type: .episode),
        .init(genres: ["Mystery"], id: "book", name: "The Tides", people: [.init(name: "Jules Moss", creditType: "Author")], type: .book),
        .init(genres: ["Mystery"], id: "audiobook", name: "Coastal Nights", people: [.init(name: "Eli Snow", creditType: "Narrator")], type: .audioBook),
        .init(albumArtist: "Horizon", id: "album", name: "Static", type: .musicAlbum),
        .init(album: "Static", artists: ["Horizon"], id: "song", name: "Current", type: .audio),
    ]

    @Test func exactConstraintsRequireMetadataOnTheSameItem() {
        let both = GusSearchIntent(mediaTypes: [.movie], genres: ["sci-fi"], people: ["Jan Reyes"], characters: ["Pilot", "Engineer"], minimumYear: 2010, maximumMinutes: 90)
        #expect(Self.fixture.filter { GusLibraryMatching.accepts($0, intent: both) }.map(\.id) == ["film"])
        #expect(CatalogNameMatching.role("Arthur Fleck / The Joker (voice)", matches: "Joker"))
        #expect(!CatalogNameMatching.role("Joker’s henchman", matches: "Joker"))
        #expect(!GusLibraryMatching.accepts(Self.fixture[0], intent: .init(keywords: ["expedition"])))
        var narrated = GusSearchIntent(mediaTypes: [.audioBook])
        narrated.credits = [.init(name: "Eli Snow", role: "narrator")]
        #expect(GusLibraryMatching.accepts(Self.fixture[4], intent: narrated))
        var book = Self.fixture[4]
        book.people = [.init(name: "Eli Snow", role: "Narrator")]
        #expect(GusLibraryMatching.accepts(book, intent: narrated))
        book.people = [.init(name: "Eli Snow", creditType: "Writer")]
        #expect(!GusLibraryMatching.accepts(book, intent: narrated))
        var artist = GusSearchIntent(mediaTypes: [.musicAlbum])
        artist.credits = [.init(name: "Horizon", role: "artist")]
        #expect(GusLibraryMatching.accepts(Self.fixture[5], intent: artist))
        var impossible = both
        impossible.characters.append("Navigator")
        #expect(Self.fixture.allSatisfy { !GusLibraryMatching.accepts($0, intent: impossible) })
        #expect(!GusLibraryMatching.accepts(Self.fixture[1], intent: .init(minimumYear: 1990)))
        #expect(!GusLibraryMatching.accepts(Self.fixture[0], intent: .init(unsupported: ["camera lens"])))
        #expect(!GusLibraryMatching.accepts(Self.fixture[0], intent: .init(status: .unplayed)))
    }

    @Test func allMediaFamiliesHaveGroundedHitsInTheFirstFive() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let catalog = GusLibraryCatalog(directory: directory)
        try await catalog.prepare(catalog.snapshot, restriction: "general")
        try await catalog.append(Self.fixture, to: catalog.snapshot)
        #expect(await catalog.isFresh(restriction: "general"))
        #expect(!(await catalog.isFresh(restriction: "teen")))
        let requirements: [(String, GusSearchIntent)] = [
            ("film", .init(themes: ["expedition"])),
            ("series", .init(mediaTypes: [.series], people: ["Ana Lim"])),
            ("episode", .init(mediaTypes: [.episode], keywords: ["Colony"])),
            ("book", .init(mediaTypes: [.book], people: ["Jules Moss"])),
            ("audiobook", .init(mediaTypes: [.audioBook], people: ["Eli Snow"])),
            ("album", .init(mediaTypes: [.musicAlbum], people: ["Horizon"])),
            ("song", .init(mediaTypes: [.audio], keywords: ["Current"])),
        ]
        for (id, intent) in requirements {
            let hits = try await catalog.collect(terms: intent.keywords + intent.themes, batchSize: 5, limit: 5, accepts: {
                GusLibraryMatching.accepts($0, intent: intent)
            }, verify: { $0 }, identity: { $0.id })
            #expect(hits.contains { $0.id == id })
        }
    }

    @MainActor private func makeSession(_ provider: FakeMediaProviderSession) throws -> SessionStore {
        let url = try #require(URL(string: "https://example.com"))
        let server = UUID().uuidString
        return SessionStore(
            client: JellyfinClientFactory.makeClient(url: url),
            user: .init(id: "user", name: "User", serverID: server),
            server: .init(id: server, name: "Server", url: url),
            mediaProvider: provider
        )
    }

    @Test @MainActor func snapshotMatchesAreRecheckedAndNewFavoritesUseLiveState() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let session = try makeSession(provider)
        defer { GusLibraryIntelligence.deleteCatalog(scope: session.references.scope) }
        let removed = MediaItem(id: "removed", name: "Harbor Lights", officialRating: "G", type: .movie)
        var renamed = MediaItem(id: "renamed", name: "Harbor Road", officialRating: "G", type: .movie)
        var newFavorite = MediaItem(id: "favorite", name: "Tide", officialRating: "G", type: .movie)
        newFavorite.userData = .init(isFavorite: true)
        var verifying = false
        provider.itemsHandler = { query in
            #expect(query.metadataOnly)
            if query.favoritesOnly {
                return .init(items: [newFavorite], totalRecordCount: 1)
            }
            if let ids = query.itemIDs {
                verifying = true
                #expect(Set(ids) == ["removed", "renamed"])
                renamed.name = "Mountain Road"
                return .init(items: [renamed], totalRecordCount: 1)
            }
            return .init(items: [removed, renamed], totalRecordCount: 2)
        }
        let hits = try await session.libraryIntelligence.search(.init(keywords: ["Harbor"]))
        #expect(verifying && hits.isEmpty)
        let favorites = try await session.libraryIntelligence.search(.init(favoritesOnly: true))
        #expect(favorites.compactMap(\.id) == ["favorite"])
        provider.itemsHandler = { _ in throw GusError.offline }
        await #expect(throws: GusError.offline) { try await session.libraryIntelligence.search(.init(keywords: ["Harbor"])) }
    }

    @Test @MainActor func searchAndCompletionsContinuePastRevokedBatches() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let session = try makeSession(provider)
        defer { GusLibraryIntelligence.deleteCatalog(scope: session.references.scope) }
        let rows = (0 ..< 65).map { MediaItem(id: "row-\($0)", name: "Harbor \($0)", officialRating: "G", type: .movie) }
        var requested = Set<String>()
        provider.itemsHandler = { query in
            guard let batch = query.itemIDs else { return .init(items: rows, totalRecordCount: rows.count) }
            let firstBatch = requested.isEmpty
            #expect(requested.isDisjoint(with: batch))
            requested.formUnion(batch)
            let live = firstBatch ? [] : rows.filter { batch.contains($0.id ?? "") }
            return .init(items: live, totalRecordCount: live.count)
        }
        let hits = try await session.libraryIntelligence.search(.init(keywords: ["Harbor"]))
        #expect(hits.count == 5)
        #expect(requested.count == 65)
        requested.removeAll()
        let suggestions = try await session.libraryIntelligence.suggestions(prefix: "har")
        #expect(suggestions.count == 6)
        #expect(requested.count == 16)
    }

    @Test @MainActor func shelfRequiresExactAffinityAndReplacesARevokedCachedPick() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let session = try makeSession(provider)
        session.intelligencePreferences.recommendationsEnabled = true
        defer {
            GusLibraryIntelligence.deleteCatalog(scope: session.references.scope)
            GusIntelligencePreferences.delete(scope: session.references.scope, defaults: .standard)
        }
        let seed = MediaItem(genres: ["Mystery"], id: "seed", officialRating: "G", type: .book, userData: .init(isFavorite: true))
        let candidates = ["a", "b"].map { MediaItem(genres: ["Mystery"], id: $0, name: "Coast", officialRating: "G", type: .book) }
        let incidental = (0 ..< 100).map { MediaItem(id: "distractor-\($0)", name: "Mystery", officialRating: "G", type: .movie) }
        var available = candidates[0]
        provider.itemsHandler = { query in
            if query.favoritesOnly {
                return .init(items: [seed], totalRecordCount: 1)
            }
            if query.mostRecentlyPlayedFirst {
                return .init(items: [], totalRecordCount: 0)
            }
            if let ids = query.itemIDs {
                #expect(ids.allSatisfy { $0 == "a" || $0 == "b" })
                let live = ids.contains(available.id ?? "") ? [available] : []
                return .init(items: live, totalRecordCount: live.count)
            }
            let rows = incidental + candidates
            return .init(items: rows, totalRecordCount: rows.count)
        }
        let first = try await session.libraryIntelligence.recommendations()
        #expect(first.compactMap(\.id) == ["a"])
        available = candidates[1]
        let replacement = try await session.libraryIntelligence.recommendations()
        #expect(replacement.compactMap(\.id) == ["b"])
    }

    @Test func abandonedStageCleanupPreservesActiveWritersAndPublishedSnapshot() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stale = directory.appending(path: UUID().uuidString)
        let lease = stale.appendingPathExtension("lease"), orphan = stale.appendingPathExtension("sqlite")
        let snapshot = directory.appending(path: "catalog.sqlite")
        let current = try GusCatalogStage(in: directory)
        defer { current.discard() }
        for file in [lease, orphan, snapshot, current.file] {
            try Data().write(to: file)
        }
        GusCatalogStage.removeAbandoned(in: directory)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(!FileManager.default.fileExists(atPath: lease.path))
        #expect(FileManager.default.fileExists(atPath: current.file.path))
        #expect(FileManager.default.fileExists(atPath: snapshot.path))
    }

    @Test func incompleteAndRepeatedPagesCannotPublishASnapshot() throws {
        var cursor = GusCatalogPaging()
        let first = MediaItemPage(items: [Self.fixture[0]], totalRecordCount: 2)
        #expect(try !cursor.advance(first, requested: 1))
        #expect(throws: GusError.self) { try cursor.advance(MediaItemPage(items: [], totalRecordCount: nil), requested: 1) }
        #expect(throws: GusError.self) { try cursor.advance(first, requested: 1) }
        #expect(try cursor.advance(.init(items: [Self.fixture[1]], totalRecordCount: nil), requested: 1))
    }

    @Test func tasteRequiresEvidenceAndExcludesPlayedAndResumableItems() {
        let liked = MediaItem(genres: ["Mystery"], id: "seed", type: .book, userData: .init(isFavorite: true))
        var read = Self.fixture[3]
        read.userData = .init(isWatched: true)
        var started = Self.fixture[4]
        started.userData = .init(playedPercentage: 20)
        let taste = GusLibraryMatching.Taste(seeds: [liked])
        #expect(taste.ranked([liked, read, started]).isEmpty)
        #expect(Set(taste.ranked(Self.fixture).compactMap(\.id)) == ["book", "audiobook"])
        #expect(GusLibraryMatching.Taste(seeds: []).ranked(Self.fixture).isEmpty)
        let other = GusLibraryMatching.Taste(seeds: [.init(artists: ["Horizon"], id: "another", type: .audio, userData: .init(isFavorite: true))])
        #expect(Set(other.ranked(Self.fixture).compactMap(\.id)) == ["album", "song"])
    }

    @Test func suggestionsDeduplicateAndScopesCannotAlias() {
        #expect(GusLibraryMatching.completions(in: Self.fixture, prefix: "hori") == ["Horizon"])
        let first = AccountScope(serverID: "a/b", userID: "z"), second = AccountScope(serverID: "a_b", userID: "z")
        #expect(GusLibraryCatalog.directory(for: first) != GusLibraryCatalog.directory(for: second))
    }
}
