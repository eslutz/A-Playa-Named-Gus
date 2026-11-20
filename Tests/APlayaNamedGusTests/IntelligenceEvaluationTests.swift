import Foundation
@testable import Gus
import Testing
#if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)
    import FoundationModels
#endif

/// Runs the actual local system model when available. Separate fixtures exercise retrieval
/// and networking on CI and simulators that cannot host Apple Intelligence.
@MainActor
struct IntelligenceEvaluationTests {
    @Test func cloudInputExcludesServerAndCredentialFields() {
        let hosts = ["library.example.invalid"]
        for sample in [
            "https://somewhere.invalid/title",
            "LIBRARY.example.invalid",
            "api_key=fixture",
            "accessToken: abc",
            "Bearer fixture",
            UUID().uuidString,
        ] {
            #expect(!GusIntelligenceModel.allowsCloudInput(sample, serverHosts: hosts))
        }
        #expect(GusIntelligenceModel.allowsCloudInput("Find the movie The Password from 1994", serverHosts: hosts))
    }

    @Test func cloudRoutingUsesCurrentConsentAndAtMostOneAttempt() async throws {
        var calls = 0
        var consent = true
        let cloud = { calls += 1; return ["cloud"] }
        let empty: [String] = try await GusIntelligenceModel.route(local: { [] }, cloudAllowed: { true }, mayEscalate: { _ in true }, cloud: cloud)
        #expect(empty.isEmpty && calls == 0)
        let recovered = try await GusIntelligenceModel.route(
            local: { throw GusIntelligenceError.invalidResponse },
            cloudAllowed: { consent },
            mayEscalate: { _ in true },
            cloud: cloud
        )
        #expect(recovered == ["cloud"] && calls == 1)
        await #expect(throws: GusIntelligenceError.self) {
            _ = try await GusIntelligenceModel.route(local: {
                consent = false
                throw GusIntelligenceError.invalidResponse
            }, cloudAllowed: { consent }, mayEscalate: { _ in true }, cloud: cloud)
        }
        await #expect(throws: CancellationError.self) {
            _ = try await GusIntelligenceModel.route(
                local: { throw CancellationError() },
                cloudAllowed: { true },
                mayEscalate: { _ in true },
                cloud: cloud
            )
        }
        await #expect(throws: GusIntelligenceError.self) {
            let _: [String] = try await GusIntelligenceModel.route(local: { nil }, cloudAllowed: { true }, mayEscalate: { _ in true }) {
                calls += 1
                throw GusIntelligenceError.quota(nil)
            }
        }
        #expect(calls == 2)
    }

    #if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)
        private nonisolated static var hasLocalModel: Bool {
            SystemLanguageModel.default.isAvailable && SystemLanguageModel.default.supportsLocale()
        }

        @Test(.enabled(if: hasLocalModel, "Requires an available on-device Apple model"))
        func localModelLibraryTopFive() async throws {
            let provider = FakeMediaProviderSession(capabilities: .init())
            let session = try makeSession(provider)
            defer { GusLibraryIntelligence.deleteCatalog(scope: session.references.scope) }
            let movie = MediaItem(genres: ["Mystery"], id: "M", name: "Glacier Road", productionYear: 2019, type: .movie)
            let series = MediaItem(genres: ["Drama"], id: "S", name: "Open Harbor", productionYear: 2005, type: .series)
            let episode = MediaItem(id: "E", name: "The Lighthouse", seriesName: "Open Harbor", type: .episode)
            let book = MediaItem(id: "B", name: "Hidden Maps", people: [.init(name: "Marta Cruz", creditType: "Author")], type: .book)
            let audioBook = MediaItem(id: "AB", name: "Hidden Maps", people: [.init(name: "Eli Snow", creditType: "Narrator")], type: .audioBook)
            let album = MediaItem(albumArtist: "Summer Night", id: "A", name: "First Snow", type: .musicAlbum)
            let song = MediaItem(artists: ["Summer Night"], id: "T", name: "Blue Hour", type: .audio)
            let items = [movie, series, episode, book, audioBook, album, song]
            provider.itemsHandler = { query in
                let available = items.filter { item in query.itemIDs.map { $0.contains(item.id ?? "") } ?? true }
                return MediaItemPage(
                    items: Array(available.dropFirst(min(query.startIndex, available.count)).prefix(query.limit)),
                    totalRecordCount: available.count
                )
            }
            let prompts: [(String, String)] = [
                ("Mystery movies released in 2019", "M"), ("Dramatic TV series from 2005", "S"),
                ("Show me the episode called The Lighthouse", "E"), ("Libros de Marta Cruz", "B"),
                ("Audiobooks narrated by Eli Snow", "AB"), ("Albums by Summer Night", "A"), ("Find the song Blue Hour", "T"),
            ]
            let model = GusIntelligenceModel(session: session)
            for (prompt, expected) in prompts {
                let intent = try await model.interpretLibrary(prompt)
                let results = try await session.libraryIntelligence.search(intent)
                #expect(results.prefix(5).contains { $0.id == expected }, "Missing expected match for \(prompt)")
            }
            let missing = try await model.interpretLibrary("Find the movie titled Nonexistent Violet Observatory")
            #expect(try await session.libraryIntelligence.search(missing).isEmpty)
        }

        @Test(.enabled(if: hasLocalModel, "Requires an available on-device Apple model"))
        func localModelDiscoverTopFive() async throws {
            let model = try GusIntelligenceModel(session: makeSession(FakeMediaProviderSession(capabilities: .init())))
            let titles: [SeerrTitle] = [
                .init(id: 1, mediaType: .movie, title: "Moon Garden", releaseDate: "2017-09-15", genres: [.init(id: 878, name: "Science Fiction")]),
                .init(id: 2, mediaType: .tv, name: "Valley Rain", firstAirDate: "2009-04-12"),
                .init(id: 3, mediaType: .person, name: "Marta Cruz"),
            ]
            for (query, expected) in [
                ("Find the movie Moon Garden", 1),
                ("Series llamadas Valley Rain", 2),
                ("Look up the person Marta Cruz", 3),
                ("Sci-fi movies released after 2014", 1),
            ] {
                let intent = try await model.interpretDiscover(query)
                #expect(intent.isSupported)
                let hits = titles.filter { intent.score($0) != nil }
                #expect(hits.map(\.id) == [expected])
            }
        }

        private func makeSession(_ provider: FakeMediaProviderSession) throws -> SessionStore {
            let url = try #require(URL(string: "https://example.invalid"))
            let scope = UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: scope))
            return SessionStore(
                client: JellyfinClientFactory.makeClient(url: url),
                user: .init(id: "fixture", name: "Fixture", serverID: scope),
                server: .init(id: scope, name: "Fixture", url: url),
                mediaProvider: provider,
                historyDefaults: defaults
            )
        }
    #endif
}
