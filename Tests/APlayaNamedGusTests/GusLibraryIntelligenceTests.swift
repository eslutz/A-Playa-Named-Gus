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

    #if os(iOS) || os(tvOS)
        @Test func syncedRecommendationPayloadPreservesBoundedRankAndExpires() throws {
            let createdAt = Date(timeIntervalSince1970: 1000)
            let ranked = (0 ..< 15).map { "item-\($0)" }
            let snapshot = ForYouSnapshot(
                itemIDs: ["", "selection with spaces", String(repeating: "x", count: 129), ranked[0]] + ranked,
                createdAt: createdAt
            )
            #expect(snapshot.itemIDs == Array(ranked.prefix(ForYouSnapshot.maximumPicks)))
            let roundTrip = try JSONDecoder().decode(ForYouSnapshot.self, from: JSONEncoder().encode(snapshot))
            #expect(roundTrip == snapshot)
            #expect(roundTrip.isFresh(at: createdAt.addingTimeInterval(ForYouSnapshot.lifetime - 1)))
            #expect(!roundTrip.isFresh(at: createdAt.addingTimeInterval(ForYouSnapshot.lifetime)))
            #expect(!roundTrip.isFresh(at: createdAt.addingTimeInterval(-3600)))
            #expect(!ForYouSnapshot(itemIDs: [], createdAt: createdAt).isFresh(at: createdAt))
        }

        @Test @MainActor func syncedRecommendationsUseLiveAccessibleTVItemsInPhoneOrder() {
            let createdAt = Date(timeIntervalSince1970: 1000)
            let snapshot = ForYouSnapshot(itemIDs: ["first", "missing", "episode", "restricted", "book", "second"], createdAt: createdAt)
            let currentItems: [MediaItem] = [
                .init(id: "second", name: "Current second title", officialRating: "G", type: .series),
                .init(id: "episode", name: "Old synced episode", officialRating: "G", seriesID: "second", type: .episode),
                .init(id: "restricted", name: "Restricted title", officialRating: "R", type: .movie),
                .init(id: "unrequested", name: "Unsolicited server result", officialRating: "G", type: .movie),
                .init(id: "book", name: "Print only", officialRating: "G", type: .book),
                .init(id: "first", name: "Current first title", officialRating: "G", type: .movie),
            ]
            let admits: (MediaItem) -> Bool = { ContentRatingGate.admits($0, limit: .general, hideUnrated: true) }
            let picks = ForYouShelfState.syncedPicks(snapshot, from: currentItems, now: createdAt, admits: admits)
            #expect(picks.compactMap(\.id) == ["first", "second"])
            #expect(picks.compactMap(\.item.name) == ["Current first title", "Current second title"])
            #expect(picks.allSatisfy { $0.reason.isEmpty })
            let expired = createdAt.addingTimeInterval(ForYouSnapshot.lifetime)
            #expect(ForYouShelfState.syncedPicks(snapshot, from: currentItems, now: expired, admits: admits).isEmpty)
        }
    #endif

    @Test func exactConstraintsRequireMetadataOnTheSameItem() {
        let both = GusSearchIntent(mediaTypes: [.movie], genres: ["sci-fi"], people: ["Jan Reyes"], characters: ["Pilot", "Engineer"], minimumYear: 2010, maximumMinutes: 90)
        #expect(Self.fixture.filter { GusLibraryMatching.accepts($0, intent: both) }.map(\.id) == ["film"])
        #expect(CatalogNameMatching.role("Arthur Fleck / The Joker (voice)", matches: "Joker"))
        #expect(CatalogNameMatching.role("Arthur Fleck / Joker", matches: "the Joker"))
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
            ("film", .init(concepts: [.init("expedition")])),
            ("series", .init(mediaTypes: [.series], people: ["Ana Lim"])),
            ("episode", .init(mediaTypes: [.episode], keywords: ["Colony"])),
            ("book", .init(mediaTypes: [.book], people: ["Jules Moss"])),
            ("audiobook", .init(mediaTypes: [.audioBook], people: ["Eli Snow"])),
            ("album", .init(mediaTypes: [.musicAlbum], people: ["Horizon"])),
            ("song", .init(mediaTypes: [.audio], keywords: ["Current"])),
        ]
        for (id, intent) in requirements {
            let hits = try await catalog.collect(terms: intent.keywords + intent.concepts.map(\.phrase), batchSize: 5, limit: 5, accepts: {
                GusLibraryMatching.accepts($0, intent: intent)
            }, verify: { $0 }, identity: { $0.id })
            #expect(hits.contains { $0.id == id })
        }
    }

    @MainActor private func makeSession(_ provider: FakeMediaProviderSession, now: @escaping () -> Date = Date.init) throws -> SessionStore {
        let url = try #require(URL(string: "https://example.com"))
        let server = UUID().uuidString
        return SessionStore(
            client: JellyfinClientFactory.makeClient(url: url),
            user: .init(id: "user", name: "User", serverID: server),
            server: .init(id: server, name: "Server", url: url),
            mediaProvider: provider,
            browseCache: BrowseSnapshotCache(scope: AccountScope(serverID: server, userID: "user"), now: now)
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

    @Test @MainActor func switchingAccountsDuringGroundedSearchDoesNotReturnThePreviousAccountsRows() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let session = try makeSession(provider)
        defer { GusLibraryIntelligence.deleteCatalog(scope: session.references.scope) }
        let row = MediaItem(genres: ["Horror"], id: "row", name: "Shift", officialRating: "G", tags: ["robot"], type: .movie)
        var verifying = false
        provider.itemsHandler = { query in
            if query.itemIDs != nil {
                verifying = true
                session.invalidate()
            }
            return .init(items: [row], totalRecordCount: 1)
        }
        await #expect(throws: GusError.cancelled) {
            try await session.libraryIntelligence.search(.init(concepts: [.init("scary"), .init("robots")]))
        }
        #expect(verifying)
    }

    @Test @MainActor func compoundConceptsRequireLiveEvidenceAndPreferDistinctTitles() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let session = try makeSession(provider)
        defer { GusLibraryIntelligence.deleteCatalog(scope: session.references.scope) }
        let film = MediaItem(
            genres: ["Horror"],
            id: "film",
            name: "Night Shift",
            officialRating: "G",
            productionYear: 2021,
            tags: ["animatronics"],
            type: .movie
        )
        let series = MediaItem(
            id: "series",
            name: "Uncanny Valley",
            officialRating: "G",
            overview: "An eerie android slips away.",
            type: .series
        )
        let episodes = (1 ... 65).map {
            MediaItem(
                genres: ["Horror"],
                id: "episode-\($0)",
                name: "Chapter \($0)",
                officialRating: "G",
                seriesID: "other-series",
                tags: ["robot"],
                type: .episode
            )
        }
        let titleOnly = MediaItem(id: "title", name: "Scary Robots", officialRating: "G", type: .movie)
        let comedy = MediaItem(
            genres: ["Comedy"],
            id: "comedy",
            name: "The Scary Larry Show",
            officialRating: "G",
            overview: "An android competes in a talent show.",
            type: .series
        )
        let unrelated = MediaItem(genres: ["Horror"], id: "unrelated", name: "Friendly Fire", officialRating: "G", type: .movie)
        var changed = film
        changed.id = "changed"
        var revoked = film
        revoked.id = "revoked"
        var represented = episodes[0]
        represented.id = "already-represented"
        represented.seriesID = series.id
        let saved = episodes + [series, film, represented, titleOnly, comedy, unrelated, changed, revoked]
        changed.tags = []
        let live = episodes + [series, film, represented, titleOnly, comedy, unrelated, changed]
        provider.itemsHandler = { query in
            let available = query.itemIDs.map { ids in live.filter { ids.contains($0.id ?? "") } } ?? saved
            return .init(items: Array(available.dropFirst(query.startIndex).prefix(query.limit)), totalRecordCount: available.count)
        }
        let intent = try #require(GusIntelligenceModel.toneAndSubject("I’m looking for something scary with robots"))
        #expect(GusIntelligenceModel.toneAndSubject("Something scary with robots from 1997") == nil)
        #expect(GusIntelligenceModel.toneAndSubject("Something scary without robots") == nil)
        let hits = try await session.libraryIntelligence.search(intent)
        #expect(hits.prefix(2).compactMap(\.id) == ["film", "series"])
        #expect(hits.count == 3 && hits.last?.type == .episode)
        var requestedEpisodes = intent
        requestedEpisodes.mediaTypes = [.episode]
        let episodeHits = try await session.libraryIntelligence.search(requestedEpisodes)
        #expect(episodeHits.count == 60 && episodeHits.allSatisfy { $0.type == .episode })

        var constrained = intent
        constrained.mediaTypes = [.movie]
        constrained.minimumYear = 2022
        #expect(try await session.libraryIntelligence.search(constrained).isEmpty)
        #expect(Set(constrained.relaxations.map(\.id)) == ["scary", "robots"])
        let onlyRobots = try #require(constrained.removingConcept("scary"))
        #expect(onlyRobots == GusSearchIntent(mediaTypes: [.movie], concepts: [.init("robots")], minimumYear: 2022))
        #expect(try await session.libraryIntelligence.search(onlyRobots).isEmpty)
        let onlyHorror = try #require(intent.removingConcept("robots"))
        let horrorHits = try await session.libraryIntelligence.search(onlyHorror)
        #expect(horrorHits.contains { $0.id == "unrelated" })
        #expect(!horrorHits.contains { $0.id == "comedy" })
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

    @Test @MainActor func episodeActivityCountsOnceAndOnlyVerifiedSeriesCanFillRecommendations() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let session = try makeSession(provider)
        session.intelligencePreferences.recommendationsEnabled = true
        defer {
            GusLibraryIntelligence.deleteCatalog(scope: session.references.scope)
            GusIntelligencePreferences.delete(scope: session.references.scope, defaults: .standard)
        }
        let watchedSeries = MediaItem(genres: ["Adventure"], id: "watched-show", name: "Watched show", officialRating: "G", type: .series)
        let recentEpisodes = (0 ..< 20).map { index in
            MediaItem(
                id: "recent-\(index)",
                officialRating: "G",
                seriesID: "watched-show",
                type: .episode,
                userData: .init(isFavorite: index == 0, lastPlayedAt: .now)
            )
        }
        let taste = GusLibraryMatching.Taste(seeds: recentEpisodes, seriesByID: ["watched-show": watchedSeries])
        #expect(taste.weights["genre:adventure"] == 3)
        #expect(!taste.isCandidate(watchedSeries))

        let series = MediaItem(genres: ["Adventure"], id: "new-show", name: "A different show", officialRating: "G", type: .series)
        var missing = series
        missing.id = "gone-show"
        let episodes = (0 ..< 100).map { index in
            MediaItem(genres: ["Adventure"], id: "episode-\(index)", officialRating: "G", seriesID: series.id, type: .episode)
        }
        #expect(taste.ranked(episodes + [series, series]).compactMap(\.id) == ["new-show"])
        provider.itemsHandler = { query in
            if query.favoritesOnly {
                return .init(items: [], totalRecordCount: 0)
            }
            if query.mostRecentlyPlayedFirst {
                return .init(items: recentEpisodes, totalRecordCount: recentEpisodes.count)
            }
            if let ids = query.itemIDs {
                #expect(ids.allSatisfy { ["watched-show", "new-show", "gone-show"].contains($0) })
                let live = [watchedSeries, series].filter { ids.contains($0.id ?? "") }
                return .init(items: live, totalRecordCount: live.count)
            }
            let catalog = episodes + [watchedSeries, missing, series]
            return .init(items: catalog, totalRecordCount: catalog.count)
        }
        let picks = try await session.libraryIntelligence.recommendations()
        #expect(picks.compactMap(\.id) == ["new-show"])
        #expect(picks.first?.item.type == .series)
    }

    #if !os(tvOS)
        @Test @MainActor func leavingAViewDuringShelfRefreshKeepsTheSharedResult() async throws {
            let provider = FakeMediaProviderSession(capabilities: .init())
            let session = try makeSession(provider)
            session.intelligencePreferences.recommendationsEnabled = true
            defer {
                BrowseSnapshotCache.delete(scope: session.references.scope)
                GusIntelligencePreferences.delete(scope: session.references.scope, defaults: .standard)
            }
            let context = ForYouShelfState.Context(
                cloudEnabled: false, recommendationsEnabled: true, limit: ContentRatingGate.storedLimit().rawValue,
                hideUnrated: UserDefaults.standard.bool(forKey: ContentRatingGate.hideUnratedDefaultsKey),
                activityRevision: 0, tasteRevision: 0
            )
            var waiting: CheckedContinuation<Void, Never>?
            var favoriteRequests = 0
            provider.itemsHandler = { query in
                if query.favoritesOnly {
                    favoriteRequests += 1
                    if favoriteRequests == 1 {
                        await withCheckedContinuation { waiting = $0 }
                    }
                }
                return .init(items: [], totalRecordCount: 0)
            }
            let shelf = session.forYouShelf
            let firstWindow = Task { await shelf.load(context, session: session) }
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while waiting == nil, ContinuousClock.now < deadline {
                await Task.yield()
            }
            let suspended = try #require(waiting)
            let secondWindow = Task { await shelf.load(context, session: session) }
            firstWindow.cancel()
            suspended.resume()
            await secondWindow.value
            await firstWindow.value
            #expect(favoriteRequests == 1)
            #expect(!shelf.needsPlaceholder(context, session: session))
            #expect(session.browseCache.read("for-you", as: [GusLibraryPick].self)?.value.isEmpty == true)
        }

        @Test @MainActor func shelfRestoresFreshPicksAndHandlesTransientFailureAndHardExpiry() async throws {
            let provider = FakeMediaProviderSession(capabilities: .init())
            let start = Date.now
            var now = start
            let session = try makeSession(provider, now: { now })
            session.intelligencePreferences.recommendationsEnabled = true
            defer {
                BrowseSnapshotCache.delete(scope: session.references.scope)
                GusIntelligencePreferences.delete(scope: session.references.scope, defaults: .standard)
            }
            let context = ForYouShelfState.Context(
                cloudEnabled: false, recommendationsEnabled: true, limit: ContentRatingGate.storedLimit().rawValue,
                hideUnrated: UserDefaults.standard.bool(forKey: ContentRatingGate.hideUnratedDefaultsKey),
                activityRevision: 0, tasteRevision: 0
            )
            let series = MediaItem(id: "show", name: "Cached series", officialRating: "G", type: .series)
            session.browseCache.write([GusLibraryPick(item: series, reason: "")], key: "for-you")
            let shelf = session.forYouShelf
            var requests = 0
            provider.itemsHandler = { _ in requests += 1; throw GusError.offline }
            #expect(shelf.picks.first?.id == "show")
            await shelf.load(context, session: session)
            #expect(requests == 0)
            now = start.addingTimeInterval(6 * 60 * 60)
            await shelf.load(context, session: session)
            #expect(requests == 1)
            #expect(shelf.picks.first?.id == "show")
            #expect(shelf.error == nil)
            now = start.addingTimeInterval(BrowseSnapshotCache.lifetime)
            #expect(shelf.needsPlaceholder(context, session: session))
            await shelf.load(context, session: session)
            #expect(shelf.picks.isEmpty)
            #expect(shelf.error != nil)
            #expect(!shelf.needsPlaceholder(context, session: session))
        }
    #endif

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
