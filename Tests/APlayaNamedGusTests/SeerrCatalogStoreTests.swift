import Foundation
@testable import Gus
import os
import Testing

@MainActor
@Suite("Seerr catalog state and isolation", .timeLimit(.minutes(1)))
struct SeerrCatalogStoreTests {
    @Test("poster and profile artwork request TMDB sizes valid for that image type")
    func artworkSizes() {
        let movie = SeerrTitle(id: 1, mediaType: .movie, posterPath: "/poster.jpg")
        let person = SeerrTitle(id: 2, mediaType: .person, profilePath: "/portrait.jpg")
        let detail = SeerrPerson(id: 2, name: "Actor", profilePath: "/portrait.jpg")
        #expect(movie.imageURL()?.path == "/t/p/w500/poster.jpg")
        #expect(person.imageURL()?.path == "/t/p/w185/portrait.jpg")
        #expect(detail.imageURL()?.path == "/t/p/h632/portrait.jpg")
    }

    @Test("daily featured titles stay stable across reloads and backfill only missing titles")
    func dailyTrendingSelection() throws {
        let today = Date(timeIntervalSince1970: 1_797_004_800)
        let tomorrow = today.addingTimeInterval(86400)
        let candidates = (1 ... 30).map { "movie:\($0)" } + ["tv:1", "movie:1"]
        let first = DailyTrendingSelection(day: today, candidates: candidates, previous: nil)
        #expect(first.ids.count == 8)
        #expect(Set(first.ids).count == 8)
        #expect(first == DailyTrendingSelection(day: today, candidates: candidates.reversed(), previous: nil))

        let restored = try JSONDecoder().decode(DailyTrendingSelection.self, from: JSONEncoder().encode(first))
        #expect(first == DailyTrendingSelection(day: today, candidates: candidates + ["tv:42"], previous: restored))
        let removed = try #require(first.ids.first)
        let remaining = candidates.filter { $0 != removed }
        let updated = DailyTrendingSelection(day: today, candidates: remaining, previous: restored)
        #expect(updated.ids.count == 8)
        #expect(Array(updated.ids.prefix(7)) == Array(first.ids.dropFirst()))
        #expect(!updated.ids.contains(removed))

        let next = DailyTrendingSelection(day: tomorrow, candidates: candidates, previous: restored)
        #expect(first.ids != next.ids)
        #expect(next == DailyTrendingSelection(day: tomorrow, candidates: candidates, previous: nil))
        #expect(Set(DailyTrendingSelection(day: today, candidates: ["movie:1", "tv:1", "movie:1"], previous: restored).ids) == ["movie:1", "tv:1"])
        #expect(DailyTrendingSelection(day: today, candidates: [], previous: restored).ids.isEmpty)
    }

    @Test("failed next page retains prior titles, retries that page and deduplicates identities")
    func failedPageRetainsContent() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, totalPages: 2, titles: #"{"id":1,"mediaType":"movie","title":"First"}"#)),
            .init(json: "{}", status: 503),
            .init(json: Self.page(2, totalPages: 2, titles: #"{"id":1,"mediaType":"movie","title":"First"},{"id":2,"mediaType":"tv","name":"Second"}"#)),
        ])
        defer { fixture.cleanUp() }
        let catalog = SeerrCatalogStore(source: .feed(.trending))
        await catalog.load(store: fixture.store)
        await catalog.loadMore(store: fixture.store)
        #expect(catalog.items.map(\.id) == [1])
        #expect(catalog.state == .loaded)
        #expect(catalog.hasMore)
        #expect(catalog.failedPage == 2)
        #expect(catalog.errorMessage != nil)
        #expect(!catalog.isLoadingMore)

        await catalog.loadMore(store: fixture.store)
        #expect(catalog.items.map(\.id) == [1, 2])
        #expect(!catalog.hasMore)
        #expect(catalog.errorMessage == nil)
        #expect(fixture.http.requests.map { Self.query($0, key: "page") } == ["1", "2", "2"])
    }

    @Test("Movie and series detail links page the matching related catalog", arguments: [SeerrMediaType.movie, .tv])
    func relatedCatalogs(type: SeerrMediaType) async throws {
        let item = #"{"id":5,"mediaType":"\#(type.rawValue)","title":"First"}"#
        let next = #"{"id":6,"mediaType":"\#(type.rawValue)","title":"Next"}"#
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, titles: item)), .init(json: Self.page(1, totalPages: 2, titles: item)), .init(json: Self.page(2, totalPages: 2, titles: next)),
        ])
        defer { fixture.cleanUp() }
        let recommendations = SeerrCatalogStore(source: .recommendations(type, 7))
        let similar = SeerrCatalogStore(source: .similar(type, 7))
        await recommendations.load(store: fixture.store)
        await similar.load(store: fixture.store)
        await similar.loadMore(store: fixture.store)
        #expect(recommendations.items.map(\.id) == [5])
        #expect(similar.items.map(\.id) == [5, 6])
        #expect(fixture.http.requests.compactMap(\.url?.lastPathComponent) == ["recommendations", "similar", "similar"])
        #expect(fixture.http.requests.allSatisfy { $0.url?.path.contains("/\(type.rawValue)/7/") == true })
        #expect(fixture.http.requests.map { Self.query($0, key: "page") } == ["1", "1", "2"])
    }

    @Test("A movie collection keeps Seerr's member order and omits blocked parts")
    func collectionParts() async throws {
        let fixture = try await CatalogStoreFixture(replies: [.init(json: """
        {"id":7,"name":"Collection","parts":[
            {"id":3,"mediaType":"movie","title":"Earlier"},
            {"id":1,"mediaType":"movie","title":"Blocked","mediaInfo":{"id":1,"status":6}},
            {"id":2,"mediaType":"movie","title":"Later"}
        ]}
        """)])
        defer { fixture.cleanUp() }
        let collection = SeerrCatalogStore(source: .collection(7))
        await collection.load(store: fixture.store)
        #expect(collection.items.map(\.id) == [3, 2])
        #expect(!collection.hasMore)
        #expect(fixture.http.requests.first?.url?.path.hasSuffix("/collection/7") == true)
    }

    @Test("a delayed previous-account response cannot replace the new connection's catalog", arguments: [
        SeerrCatalogSource.feed(.trending),
        .natural(SeerrSearchIntent(mediaType: "movie", keywords: ["account"])),
    ])
    func accountChangeRejectsLateResponse(source: SeerrCatalogSource) async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, titles: #"{"id":1,"mediaType":"movie","title":"Previous account"}"#), paused: true),
        ])
        defer { fixture.cleanUp() }
        let catalog = SeerrCatalogStore(source: source)
        let previousLoad = Task { await catalog.load(store: fixture.store) }
        await fixture.http.waitForStarted(1)

        let replacement = CatalogHTTPFixture(replies: [
            .init(json: Self.page(1, titles: #"{"id":2,"mediaType":"movie","title":"Current account"}"#)),
        ])
        try await fixture.store.connect(client: replacement.client(), user: SeerrUser(id: 88, permissions: .request))
        #expect(!catalog.isValid(for: fixture.store))
        await catalog.load(store: fixture.store)
        fixture.http.releasePausedResponses()
        await previousLoad.value

        #expect(catalog.items.map(\.id) == [2])
        #expect(catalog.state == .loaded)
        #expect(catalog.isValid(for: fixture.store))
    }

    @Test("a new applied filter rejects the delayed prior-query page")
    func filterGenerationRejectsLateResponse() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, titles: #"{"id":1,"mediaType":"tv","name":"Old filter"}"#), paused: true),
            .init(json: Self.page(1, titles: #"{"id":2,"mediaType":"movie","title":"New filter"}"#)),
        ])
        defer { fixture.cleanUp() }
        let catalog = SeerrCatalogStore(source: .feed(.trending))
        let previousLoad = Task { await catalog.load(store: fixture.store) }
        await fixture.http.waitForStarted(1)
        await catalog.applyFilters(SeerrCatalogFilters(mediaType: "movie", language: "en"), store: fixture.store)
        fixture.http.releasePausedResponses()
        await previousLoad.value

        #expect(catalog.items.map(\.id) == [2])
        #expect(catalog.filters.mediaType == "movie")
        #expect(try Self.query(#require(fixture.http.requests.last), key: "mediaType") == "movie")
        #expect(try Self.query(#require(fixture.http.requests.last), key: "language") == "en")
    }

    @Test("canceling a first-page read leaves it reloadable when the view returns")
    func canceledReadCanReload() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, titles: #"{"id":1,"mediaType":"movie","title":"Canceled"}"#), paused: true),
            .init(json: Self.page(1, titles: #"{"id":2,"mediaType":"movie","title":"Returned"}"#)),
        ])
        defer { fixture.cleanUp() }
        let catalog = SeerrCatalogStore(source: .feed(.trending))
        let load = Task { await catalog.load(store: fixture.store) }
        await fixture.http.waitForStarted(1)
        load.cancel()
        await load.value
        #expect(catalog.state == .idle)
        await catalog.load(store: fixture.store)
        #expect(catalog.items.map(\.id) == [2])
        #expect(catalog.state == .loaded)
    }

    @Test("restricted catalogs hydrate missing ratings and omit restricted, unrated and blocked titles")
    func restrictionsHydrateBeforePresentation() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, titles: #"{"id":1,"mediaType":"movie","title":"Restricted"},{"id":2,"mediaType":"movie","title":"Allowed"},{"id":3,"mediaType":"movie","title":"Blocked"},{"id":4,"mediaType":"movie","title":"Unrated"},{"id":9,"mediaType":"person","name":"A Person"}"#)),
            .init(json: Self.movie(1, title: "Restricted", rating: "R")),
            .init(json: Self.movie(2, title: "Allowed", rating: "G")),
            .init(json: Self.movie(3, title: "Blocked", rating: "G", status: 6)),
            .init(json: #"{"id":4,"title":"Unrated"}"#),
        ])
        defer { fixture.cleanUp() }
        fixture.defaults.set(ContentRatingGate.Limit.general.rawValue, forKey: ContentRatingGate.limitDefaultsKey)
        fixture.defaults.set(true, forKey: ContentRatingGate.hideUnratedDefaultsKey)
        let catalog = SeerrCatalogStore(source: .feed(.trending))
        await catalog.load(store: fixture.store)

        #expect(catalog.items.map(\.id) == [2, 9])
        #expect(catalog.items.first?.certification == "G")
        #expect(catalog.items.allSatisfy { fixture.store.admits($0) })
        #expect(fixture.http.requests.compactMap(\.url?.lastPathComponent) == ["trending", "1", "2", "3", "4"])

        fixture.defaults.set(ContentRatingGate.Limit.off.rawValue, forKey: ContentRatingGate.limitDefaultsKey)
        #expect(!catalog.isValid(for: fixture.store))
    }

    @Test("an empty restricted page still permits reading later pages")
    func restrictedFirstPageIsNotEnd() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, totalPages: 2, titles: #"{"id":1,"mediaType":"movie","title":"Restricted"}"#)),
            .init(json: Self.movie(1, title: "Restricted", rating: "R")),
            .init(json: Self.page(2, totalPages: 2, titles: #"{"id":2,"mediaType":"movie","title":"Allowed"}"#)),
            .init(json: Self.movie(2, title: "Allowed", rating: "G")),
        ])
        defer { fixture.cleanUp() }
        fixture.defaults.set(ContentRatingGate.Limit.general.rawValue, forKey: ContentRatingGate.limitDefaultsKey)
        let catalog = SeerrCatalogStore(source: .feed(.trending))
        await catalog.load(store: fixture.store)
        #expect(catalog.items.isEmpty)
        #expect(catalog.hasMore)
        await catalog.loadMore(store: fixture.store)
        #expect(catalog.items.map(\.id) == [2])
        #expect(!catalog.hasMore)
    }

    @Test("a new trending day fetches fresh candidates, while a failed refresh retains yesterday's date and manual choices")
    func trendingDayRefreshes() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, titles: #"{"id":1,"mediaType":"movie","title":"Yesterday"}"#)),
            .init(json: "{}", status: 503),
            .init(json: Self.page(1, titles: #"{"id":2,"mediaType":"movie","title":"Today"}"#)),
        ])
        defer { fixture.cleanUp() }
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let catalog = SeerrCatalogStore(source: .feed(.trending))
        await catalog.loadTrending(for: yesterday, calendar: calendar, store: fixture.store)
        await catalog.loadTrending(for: yesterday, calendar: calendar, store: fixture.store)
        #expect(fixture.http.requests.count == 1)
        await catalog.loadTrending(for: today, calendar: calendar, store: fixture.store)
        #expect(catalog.firstPageRequestedAt == yesterday)
        #expect(catalog.items.map(\.id) == [1])
        #expect(catalog.errorMessage != nil)
        await catalog.loadTrending(for: today, calendar: calendar, store: fixture.store)
        #expect(catalog.firstPageRequestedAt == today)
        #expect(catalog.items.map(\.id) == [2])
        #expect(catalog.errorMessage == nil)
    }

    @Test("the daily carousel fills from later Trending pages without advancing the ordinary shelf cursor")
    func trendingCandidatesAcrossPages() async throws {
        let first = #"{"id":1,"mediaType":"movie"},{"id":1,"mediaType":"tv"},{"id":2,"mediaType":"person"},{"id":9,"mediaType":"movie","mediaInfo":{"id":9,"status":6}}"#
        let later = (1 ... 7).map { #"{"id":\#($0),"mediaType":"movie"}"# }.joined(separator: ",")
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, totalPages: 2, titles: first)),
            .init(json: Self.page(2, totalPages: 2, titles: later)),
            .init(json: Self.page(2, totalPages: 2, titles: later)),
        ])
        defer { fixture.cleanUp() }
        let catalog = SeerrCatalogStore(source: .feed(.trending))
        await catalog.loadTrending(for: .now, calendar: .current, store: fixture.store)
        let featured = try #require(catalog.featuredTrending)
        #expect(featured.titles.count == 8)
        #expect(featured.canSaveSelection)
        #expect(Set(featured.titles.map(\.seerrCatalogID)) == Set((1 ... 7).map { "movie:\($0)" } + ["tv:1"]))
        #expect(catalog.items.map(\.seerrCatalogID) == ["movie:1", "tv:1", "person:2"])
        #expect(catalog.hasMore)
        await catalog.loadMore(store: fixture.store)
        #expect(!catalog.hasMore)
        #expect(fixture.http.requests.map { Self.query($0, key: "page") } == ["1", "2", "2"])
    }

    @Test("only two extra pages are sampled from a sparse or restricted catalog, then viewed pages can fill vacancies")
    func sparseTrendingBudget() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.startOfDay(for: .now)
        let ordinal = try #require(calendar.ordinality(of: .day, in: .era, for: date))
        let samplePage = 2 + ordinal % 499
        let following = samplePage == 500 ? 2 : samplePage + 1
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, totalPages: 900, titles: #"{"id":1,"mediaType":"person"}"#)),
            .init(json: Self.page(samplePage, totalPages: 900, titles: "")),
            .init(json: Self.page(following, totalPages: 900, titles: "")),
            .init(json: Self.page(1, totalPages: 900, titles: #"{"id":1,"mediaType":"person"}"#)),
            .init(json: Self.page(2, totalPages: 900, titles: #"{"id":55,"mediaType":"movie"}"#)),
        ])
        defer { fixture.cleanUp() }
        let home = SeerrCatalogStore(source: .feed(.trending))
        await home.loadTrending(for: date, calendar: calendar, store: fixture.store)
        #expect(fixture.http.requests.map { Self.query($0, key: "page") } == ["1", String(samplePage), String(following)])
        #expect(home.featuredTrending?.titles.isEmpty == true)
        let grid = SeerrCatalogStore(source: .feed(.trending))
        await grid.load(store: fixture.store)
        await grid.loadMore(store: fixture.store)
        home.includeViewedTrending(grid, calendar: calendar, store: fixture.store)
        #expect(home.featuredTrending?.titles.map(\.id) == [55])
        #expect(home.items.map(\.id) == [1])
        #expect(fixture.http.requests.count == 5)
    }

    @Test("a later-page error displays first-page candidates without replacing the persisted daily sample")
    func trendingSampleFailureIsProvisional() async throws {
        let date = Calendar.current.startOfDay(for: .now)
        let first = (1 ... 8).map { #"{"id":\#($0),"mediaType":"movie"}"# }.joined(separator: ",")
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, totalPages: 2, titles: first)),
            .init(json: "{}", status: 503),
            .init(json: Self.page(1, totalPages: 2, titles: first)),
            .init(json: Self.page(2, totalPages: 2, titles: #"{"id":9,"mediaType":"movie"}"#)),
        ])
        defer { fixture.cleanUp() }
        let catalog = SeerrCatalogStore(source: .feed(.trending))
        await catalog.loadTrending(for: date, calendar: .current, store: fixture.store)
        #expect(catalog.featuredTrending?.titles.count == 8)
        #expect(catalog.featuredTrending?.canSaveSelection == false)
        #expect(catalog.featuredError != nil)
        #expect(catalog.errorMessage == nil)
        await catalog.loadTrending(for: date, calendar: .current, store: fixture.store)
        #expect(catalog.featuredTrending?.titles.count == 9)
        #expect(catalog.featuredTrending?.canSaveSelection == true)
        #expect(catalog.featuredError == nil)
    }

    @Test("server order and enabled built-in slider capabilities determine available feeds")
    func enabledSupportedFeeds() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: #"[{"id":1,"type":4,"order":3,"enabled":true,"isBuiltIn":true},{"id":2,"type":5,"order":0,"enabled":false,"isBuiltIn":true},{"id":3,"type":7,"order":1,"enabled":true,"isBuiltIn":false},{"id":4,"type":99,"order":2,"enabled":true,"isBuiltIn":true},{"id":5,"type":9,"order":0,"enabled":true,"isBuiltIn":true}]"#),
        ])
        defer { fixture.cleanUp() }
        let sliders = try await fixture.store.requireClient().discoverSliders()
        #expect(sliders.sorted { $0.order < $1.order }.compactMap(\.supportedSection) == [.titles(.popularTV), .titles(.trending)])
        #expect(fixture.http.requests.first?.url?.path == "/seerr/api/v1/settings/discover")
    }

    @Test("popular shelves inherit Seerr preferences and only filter original language after an explicit choice", arguments: [SeerrDiscoveryFeed.popularMovies, .popularTV])
    func popularLanguage(feed: SeerrDiscoveryFeed) async throws {
        let title = feed == .popularMovies ? #"{"id":22,"mediaType":"movie","title":"Movie"}"# : #"{"id":22,"mediaType":"tv","name":"TV"}"#
        let fixture = try await CatalogStoreFixture(replies: Array(repeating: .init(json: Self.page(1, titles: title)), count: 2))
        defer { fixture.cleanUp() }
        let catalog = SeerrCatalogStore(source: .feed(feed))
        await catalog.load(store: fixture.store)
        #expect(catalog.items.map(\.id) == [22])
        #expect(catalog.filtersOriginalLanguage)
        let initial = try #require(fixture.http.requests.first)
        #expect(initial.url?.path == "/seerr/api/v1/" + feed.path)
        #expect(Self.query(initial, key: "language") == nil)

        await catalog.applyFilters(SeerrCatalogFilters(language: "ja"), store: fixture.store)
        #expect(try Self.query(#require(fixture.http.requests.last), key: "language") == "ja")
    }

    @Test("genre directories decode backdrops, retry independently, and open paginated filtered results", arguments: [SeerrCategoryKind.movieGenres, .tvGenres])
    func genreDirectory(kind: SeerrCategoryKind) async throws {
        let movie = kind == .movieGenres
        let genreID = movie ? 28 : 10759
        let mediaType = movie ? "movie" : "tv"
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: "{}", status: 503),
            .init(json: #"[{"id":\#(genreID),"name":"Action","backdrops":["/landscape.jpg"]}]"#),
            .init(json: Self.page(1, totalPages: 2, titles: #"{"id":8,"mediaType":"\#(mediaType)","name":"First"}"#)),
            .init(json: Self.page(2, totalPages: 2, titles: #"{"id":9,"mediaType":"\#(mediaType)","name":"Next"}"#)),
        ])
        defer { fixture.cleanUp() }
        let directory = SeerrCategoryDirectory(kind: kind)
        await directory.load(store: fixture.store)
        #expect(directory.errorMessage != nil)
        await directory.load(store: fixture.store)
        let category = try #require(directory.categories.first)
        #expect(directory.errorMessage == nil)
        #expect(category.backdrops == ["/landscape.jpg"])
        #expect(fixture.http.requests.first?.url?.path == "/seerr/api/v1/discover/genreslider/" + mediaType)

        let catalog = SeerrCatalogStore(source: .category(kind, category.id))
        await catalog.load(store: fixture.store)
        #expect(catalog.hasMore)
        await catalog.loadMore(store: fixture.store)
        #expect(catalog.items.map(\.id) == [8, 9])
        #expect(!catalog.hasMore)
        let requests = fixture.http.requests.suffix(2)
        #expect(requests.allSatisfy { $0.url?.path == "/seerr/api/v1/discover/" + (movie ? "movies" : "tv") })
        #expect(requests.allSatisfy { Self.query($0, key: "genre") == String(genreID) && Self.query($0, key: "language") == nil })
        #expect(requests.map { Self.query($0, key: "page") } == ["1", "2"])
    }

    @Test("Seerr's built-in category types and curated studio and network cards lead to their respective catalogs")
    func companyDirectories() async throws {
        let kinds: [SeerrCategoryKind] = [.movieGenres, .studios, .tvGenres, .networks]
        #expect(zip([6, 8, 10, 12], kinds).allSatisfy { type, kind in
            SeerrDiscoverSlider(id: type, type: type, order: type, enabled: true, isBuiltIn: true).supportedSection == .categories(kind)
        })
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, titles: #"{"id":1,"mediaType":"movie","name":"Disney movie"}"#)),
            .init(json: Self.page(1, titles: #"{"id":2,"mediaType":"tv","name":"Netflix series"}"#)),
        ])
        defer { fixture.cleanUp() }
        for (kind, expectedName, count) in [(SeerrCategoryKind.studios, "Disney", 11), (.networks, "Netflix", 22)] {
            let directory = SeerrCategoryDirectory(kind: kind)
            await directory.load(store: fixture.store)
            #expect(directory.categories.count == count)
            let first = try #require(directory.categories.first)
            #expect(first.name == expectedName)
            #expect(SeerrArtwork.url(path: first.logoPath) != nil)
            let catalog = SeerrCatalogStore(source: .category(kind, first.id))
            await catalog.load(store: fixture.store)
            #expect(catalog.items.count == 1)
        }
        #expect(fixture.http.requests.compactMap { $0.url?.path } == [
            "/seerr/api/v1/discover/movies/studio/2", "/seerr/api/v1/discover/tv/network/213",
        ])
    }

    @Test("one feed's failure preserves another feed's successful catalog")
    func feedsFailIndependently() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, titles: #"{"id":1,"mediaType":"movie","title":"Retained"}"#)),
            .init(json: "{}", status: 503),
        ])
        defer { fixture.cleanUp() }
        let trending = SeerrCatalogStore(source: .feed(.trending))
        let movies = SeerrCatalogStore(source: .feed(.popularMovies))
        await trending.load(store: fixture.store)
        await movies.load(store: fixture.store)
        #expect(trending.items.map(\.id) == [1])
        #expect(trending.state == .loaded)
        if case .failed = movies.state {} else {
            Issue.record("The failed feed must retain its own error state")
        }
        #expect(fixture.store.isConnected)
    }

    @Test("a failed detail refresh retains the last authorized title")
    func failedDetailRefresh() async throws {
        let json = Self.movie(1, title: "Retained title", rating: "G")
        let fixture = try await CatalogStoreFixture(replies: [.init(json: json), .init(json: "{}", status: 503)])
        defer { fixture.cleanUp() }
        var seed = try JSONDecoder().decode(SeerrTitle.self, from: Data(json.utf8))
        seed.mediaType = .movie
        let detail = SeerrTitleDetailStore(title: seed)
        await detail.load(store: fixture.store)
        await detail.load(store: fixture.store)
        #expect(detail.title?.displayTitle == "Retained title")
        if case .failed = detail.state {} else {
            Issue.record("The retained title still needs refresh error feedback")
        }
        #expect(fixture.store.isConnected)
    }

    @Test("Discover movie and series discovery use Seerr genre IDs and the matching inclusive dates", arguments: [SeerrMediaType.movie, .tv])
    func naturalGenreAndDates(type: SeerrMediaType) async throws {
        let isMovie = type == .movie
        let name = isMovie ? "Science Fiction" : "Sci-Fi & Fantasy"
        let genre = isMovie ? 878 : 10765
        let date = isMovie ? "releaseDate" : "firstAirDate"
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: #"[{"id":\#(genre),"name":"\#(name)"}]"#),
            .init(json: Self.page(1, totalPages: 3, titles: #"{"id":71,"mediaType":"\#(type.rawValue)"}"#)),
            .init(json: Self.page(2, totalPages: 3, titles: #"{"id":71,"mediaType":"\#(type.rawValue)"},{"id":72,"mediaType":"\#(type.rawValue)"}"#)),
            .init(json: #"{"id":71,"name":"Orbit","overview":"A science fiction adventure.","\#(date)":"2020-01-01","genres":[{"id":\#(genre),"name":"\#(name)"}]}"#),
            .init(json: #"{"id":72,"name":"Archive","\#(date)":"2008-01-01","genres":[{"id":\#(genre),"name":"\#(name)"}]}"#),
        ])
        defer { fixture.cleanUp() }
        let intent = SeerrSearchIntent(mediaType: type.rawValue, genres: ["sci-fi"], minimumYear: 2011, maximumYear: 2024)
        let catalog = SeerrCatalogStore(source: .natural(intent))
        await catalog.load(store: fixture.store)
        #expect(catalog.items.map(\.id) == [71])
        #expect(!catalog.hasMore)
        let pages = fixture.http.requests.filter { $0.url?.lastPathComponent == (isMovie ? "movies" : "tv") && Self.query($0, key: "page") != nil }
        #expect(pages.map { Self.query($0, key: "page") } == ["1", "2"])
        let first = try #require(pages.first)
        #expect(Self.query(first, key: "genre") == String(genre))
        #expect(Self.query(first, key: isMovie ? "primaryReleaseDateGte" : "firstAirDateGte") == "2011-01-01")
        #expect(Self.query(first, key: isMovie ? "primaryReleaseDateLte" : "firstAirDateLte") == "2024-12-31")
    }

    @Test("A combined TV category cannot establish an exact science-fiction constraint")
    func combinedTVGenre() {
        let intent = SeerrSearchIntent(mediaType: "tv", genres: ["sci-fi"])
        let fantasy = SeerrTitle(id: 9, mediaType: .tv, name: "Ancient Kingdom", overview: "A magical forest.", genres: [.init(id: 10765, name: "Sci-Fi & Fantasy")])
        #expect(intent.score(fantasy) == nil)
    }

    @Test("All required character names belong to the same admitted Seerr title")
    func naturalCharacters() async throws {
        let candidates = #"{"id":1,"mediaType":"movie"},{"id":2,"mediaType":"movie"},{"id":3,"mediaType":"movie","mediaInfo":{"id":3,"status":6}}"#
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, titles: candidates)), .init(json: Self.page(1, titles: candidates)),
            .init(json: #"{"id":1,"title":"Together","credits":{"cast":[{"id":101,"name":"One","character":"Bruce Wayne / Batman"},{"id":102,"name":"Two","character":"The Joker (voice)"}],"crew":[]}}"#),
            .init(json: #"{"id":2,"title":"Impostors","credits":{"cast":[{"id":101,"name":"One","character":"Batman Impostor"},{"id":102,"name":"Two","character":"Joker Henchman"}],"crew":[]}}"#),
        ])
        defer { fixture.cleanUp() }
        let catalog = SeerrCatalogStore(source: .natural(SeerrSearchIntent(mediaType: "movie", characters: ["Batman", "Joker"])))
        await catalog.load(store: fixture.store)
        #expect(catalog.items.map(\.id) == [1])
        #expect(fixture.http.requests.compactMap { Self.query($0, key: "query") } == ["Batman", "Joker"])
        #expect(fixture.http.requests.count == 4)
    }

    @Test("Looking up a named person uses Seerr search and cannot yield a same-name movie")
    func naturalPerson() async throws {
        let rows = #"{"id":92,"name":"Example Person","mediaType":"person"},{"id":92,"title":"Example Person","mediaType":"movie"}"#
        let fixture = try await CatalogStoreFixture(replies: [.init(json: Self.page(1, titles: rows))])
        defer { fixture.cleanUp() }
        let catalog = SeerrCatalogStore(source: .natural(SeerrSearchIntent(mediaType: "person", keywords: ["Example Person"])))
        await catalog.load(store: fixture.store)
        #expect(catalog.items.map(\.seerrCatalogID) == ["person:92"])
        #expect(fixture.http.requests.count == 1)
    }

    @Test("Person lookups reconcile duplicate or misplaced names without dropping distinct constraints")
    func normalizedPersonLookup() {
        let expected = SeerrSearchIntent(mediaType: "person", keywords: ["Maya Chen"])
        let duplicated = SeerrSearchIntent(mediaType: "person", keywords: ["Maya Chen"], people: ["maya chen"])
        let misplaced = SeerrSearchIntent(mediaType: "person", people: ["Maya Chen"])
        #expect(duplicated.normalizedPersonLookup() == expected)
        #expect(misplaced.normalizedPersonLookup() == expected)
        let distinct = SeerrSearchIntent(mediaType: "person", keywords: ["Maya Chen"], people: ["Maya Chen", "Alex Chen"])
        #expect(distinct.normalizedPersonLookup().people == ["Alex Chen"])
        #expect(!distinct.normalizedPersonLookup().isSupported)
        let extraCondition = SeerrSearchIntent(mediaType: "person", people: ["Maya Chen"], minimumYear: 2000)
        #expect(extraCondition.normalizedPersonLookup() == extraCondition)
        let movie = SeerrSearchIntent(mediaType: "movie", people: ["Maya Chen"])
        #expect(movie.normalizedPersonLookup() == movie)
    }

    @Test("A director request must match the named director on each returned Seerr title")
    func naturalCredits() async throws {
        let fixture = try await CatalogStoreFixture(replies: [
            .init(json: Self.page(1, titles: #"{"id":7,"name":"Example Person","mediaType":"person"}"#)),
            .init(json: #"{"cast":[{"id":3,"mediaType":"movie"}],"crew":[{"id":1,"mediaType":"movie","job":"Director"},{"id":2,"mediaType":"movie","job":"Director"}]}"#),
            .init(json: #"{"id":1,"title":"Cameo","credits":{"cast":[{"id":7,"name":"Example Person"}],"crew":[{"id":9,"name":"Someone Else","job":"Director"}]}}"#),
            .init(json: #"{"id":2,"title":"Directed","credits":{"cast":[],"crew":[{"id":7,"name":"Example Person","job":"Director"}]}}"#),
        ])
        defer { fixture.cleanUp() }
        let intent = SeerrSearchIntent(mediaType: "movie", credits: [.init(name: "Example Person", role: "director")])
        let catalog = SeerrCatalogStore(source: .natural(intent))
        await catalog.load(store: fixture.store)
        #expect(catalog.items.map(\.id) == [2])
        #expect(fixture.http.requests.compactMap { Self.query($0, key: "query") } == ["Example Person"])
        #expect(fixture.http.requests.count == 4)
    }

    @Test("Unsupported and invalid intents do not issue broad catalog lookups")
    func unsupportedNaturalQueries() async throws {
        let fixture = try await CatalogStoreFixture(replies: [])
        defer { fixture.cleanUp() }
        for intent in [
            SeerrSearchIntent(),
            SeerrSearchIntent(mediaType: "book"),
            SeerrSearchIntent(unsupported: ["my watch state"]),
            SeerrSearchIntent(minimumYear: 2020, maximumYear: 2000),
        ] {
            #expect(!intent.isSupported)
            let catalog = SeerrCatalogStore(source: .natural(intent))
            await catalog.load(store: fixture.store)
            #expect(catalog.errorMessage != nil)
        }
        #expect(fixture.http.requests.isEmpty)
    }

    @Test("Predictive Discover completion shares the regular search's admitted rows and request")
    func keywordSuggestions() async throws {
        let rows = #"{"id":91,"mediaType":"movie","title":"Orbit"},{"id":92,"mediaType":"movie","title":"Orbital"},{"id":93,"mediaType":"movie","title":"ORBITAL"},{"id":94,"mediaType":"movie","title":"Orbit Hidden","mediaInfo":{"id":94,"status":6}}"#
        let fixture = try await CatalogStoreFixture(replies: [.init(json: Self.page(1, titles: rows))])
        defer { fixture.cleanUp() }
        let catalog = SeerrCatalogStore(source: .search("orb"))
        await catalog.load(store: fixture.store)
        let suggestions = SearchCompletions.matching("orb", candidates: catalog.items.filter { fixture.store.admits($0) }.map(\.displayTitle), limit: 5)
        #expect(suggestions == ["Orbit", "Orbital"])
        #expect(catalog.items.map(\.id) == [91, 92, 93])
        #expect(fixture.http.requests.count == 1)
    }

    private static func query(_ request: URLRequest, key: String) -> String? {
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == key }?.value
    }

    private static func page(_ page: Int, totalPages: Int = 1, titles: String) -> String {
        "{\"page\":\(page),\"totalPages\":\(totalPages),\"totalResults\":20,\"results\":[\(titles)]}"
    }

    private static func movie(_ id: Int, title: String, rating: String, status: Int = 1) -> String {
        "{\"id\":\(id),\"title\":\"\(title)\",\"releases\":{\"results\":[{\"iso_3166_1\":\"US\",\"release_dates\":[{\"certification\":\"\(rating)\",\"type\":3}]}]},\"mediaInfo\":{\"id\":\(id),\"status\":\(status)}}"
    }
}

@MainActor
private struct CatalogStoreFixture {
    let http: CatalogHTTPFixture
    let store: SeerrStore
    let defaults: UserDefaults
    private let suite: String
    private let directory: URL

    init(replies: [CatalogReply]) async throws {
        suite = "dev.ericslutz.gus.tests.catalog.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        http = CatalogHTTPFixture(replies: replies)
        store = SeerrStore(
            scope: AccountScope(serverID: "test-server", userID: "test-user"),
            directory: directory,
            tokens: CatalogTokenStore(),
            userDefaults: defaults
        )
        try await store.connect(client: http.client(), user: SeerrUser(id: 2, permissions: .request))
    }

    func cleanUp() {
        http.releasePausedResponses()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class CatalogTokenStore: TokenStore {
    private var values: [String: String] = [:]
    func token(for credential: SessionCredential) -> String? {
        token(account: credential.account)
    }

    func token(account: String) -> String? {
        values[account]
    }

    func setToken(_ token: String, for credential: SessionCredential) {
        setToken(token, account: credential.account)
    }

    func setToken(_ token: String, account: String) {
        values[account] = token
    }

    func deleteToken(for credential: SessionCredential) {
        deleteToken(account: credential.account)
    }

    func deleteToken(account: String) {
        values[account] = nil
    }
}

private struct CatalogReply: Sendable {
    var json: String
    var status = 200
    var paused = false
}

private final class CatalogHTTPFixture: @unchecked Sendable {
    private let id = UUID().uuidString
    private let state: CatalogProtocolState
    private let session: URLSession

    init(replies: [CatalogReply]) {
        state = CatalogProtocolState(replies: replies)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogURLProtocol.self]
        configuration.httpAdditionalHeaders = [CatalogURLProtocol.header: id]
        session = URLSession(configuration: configuration)
        CatalogURLProtocol.states.withLock { $0[id] = state }
    }

    deinit {
        session.invalidateAndCancel()
        _ = CatalogURLProtocol.states.withLock { $0.removeValue(forKey: id) }
    }

    var requests: [URLRequest] {
        state.requests
    }

    func waitForStarted(_ count: Int) async {
        await state.waitForStarted(count)
    }

    func releasePausedResponses() {
        state.release()
    }

    func client() throws -> SeerrClient {
        let base = try #require(URL(string: "https://media.example/seerr"))
        let cookie = SeerrSessionCookie(origin: base, name: "connect.sid", value: "catalog-fixture", path: "/", expiresAt: nil, secure: true)
        return try SeerrClient(baseURL: base, session: session, cookies: [cookie])
    }
}

/// Protocol callbacks are resumed only once; pending replies and waiters are protected by the state lock.
private final class CatalogURLProtocol: URLProtocol {
    static let header = "X-Gus-Catalog-Test-ID"
    static let states = OSAllocatedUnfairLock(initialState: [String: CatalogProtocolState]())
    private let stopped = OSAllocatedUnfairLock(initialState: false)

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: header) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: Self.header), let state = Self.states.withLock({ $0[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        if let reply = state.accept(request, loader: self) {
            send(reply)
        }
    }

    override func stopLoading() {
        stopped.withLock { $0 = true }
    }

    func send(_ reply: CatalogReply) {
        guard !stopped.withLock({ $0 }) else { return }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])
        else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class CatalogProtocolState: Sendable {
    private struct Pending {
        let loader: CatalogURLProtocol
        let reply: CatalogReply
    }

    private struct State {
        var replies: [CatalogReply]
        var requests: [URLRequest] = []
        var pending: [Pending] = []
        var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    }

    private let state: OSAllocatedUnfairLock<State>
    init(replies: [CatalogReply]) {
        // URLProtocol forbids Sendable conformance. Its pending reference stays behind this
        // lock until one release drains it; stopped loaders ignore delivery after cancellation.
        state = OSAllocatedUnfairLock(uncheckedState: State(replies: replies))
    }

    var requests: [URLRequest] {
        state.withLock { $0.requests }
    }

    func accept(_ request: URLRequest, loader: CatalogURLProtocol) -> CatalogReply? {
        let (reply, waiters) = state.withLockUnchecked { value -> (CatalogReply, [CheckedContinuation<Void, Never>]) in
            value.requests.append(request)
            let reply = value.replies.isEmpty ? CatalogReply(json: "{}", status: 500) : value.replies.removeFirst()
            if reply.paused {
                value.pending.append(Pending(loader: loader, reply: reply))
            }
            let ready = value.waiters.filter { $0.0 <= value.requests.count }.map(\.1)
            value.waiters.removeAll { $0.0 <= value.requests.count }
            return (reply, ready)
        }
        for waiter in waiters {
            waiter.resume()
        }
        return reply.paused ? nil : reply
    }

    func waitForStarted(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let alreadyStarted = state.withLock { value in
                if value.requests.count >= count {
                    return true
                }
                value.waiters.append((count, continuation))
                return false
            }
            if alreadyStarted {
                continuation.resume()
            }
        }
    }

    func release() {
        let pending = state.withLockUnchecked { value in
            let pending = value.pending
            value.pending = []
            return pending
        }
        for item in pending {
            item.loader.send(item.reply)
        }
    }
}
