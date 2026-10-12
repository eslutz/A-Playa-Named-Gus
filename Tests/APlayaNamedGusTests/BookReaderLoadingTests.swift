#if os(iOS) && canImport(ReadiumShared)
    import Foundation
    @testable import Gus
    import ReadiumShared
    import Testing

    @MainActor
    @Suite("EPUB loading and resume")
    struct BookReaderLoadingTests {
        @Test("concurrent readers own separate publications and load chapters")
        func independentPublications() async throws {
            let url = try fixtureURL()
            let first = makeModel(url: url)
            let second = makeModel(url: url)
            async let firstOpen: Void = first.open()
            async let secondOpen: Void = second.open()
            _ = await(firstOpen, secondOpen)

            #expect(first.state == .loaded)
            #expect(second.state == .loaded)
            let firstPublication = try #require(first.publication)
            let secondPublication = try #require(second.publication)
            #expect(firstPublication !== secondPublication)
            #expect(first.tableOfContents.map(\.title) == ["First Chapter", "Last Chapter"])
            #expect(second.tableOfContents.map(\.title) == ["First Chapter", "Last Chapter"])
        }

        @Test("exact local resume takes precedence without querying the server")
        func exactLocalResume() async throws {
            let url = try fixtureURL()
            let scope = AccountScope(serverID: UUID().uuidString, userID: "reader-test")
            let item = MediaItem(id: "reader-fixture", name: "Reader fixture", type: .book)
            let initial = BookReaderModel(item: item, fileURL: url, provider: nil, accountScope: scope)
            await initial.open()
            let publication = try #require(initial.publication)
            let href = try #require(publication.readingOrder.last?.href)
            let saved = Locator(
                href: href, mediaType: .xhtml,
                locations: .init(progression: 0.75, totalProgression: 0.875)
            )
            try BookProgressStore.shared.save(locatorJSON: saved.jsonString(), forItemID: "reader-fixture", scope: scope)
            defer {
                BookProgressStore.shared.deleteLocators(scope: scope)
                BookProgressStore.shared.flush()
            }

            let provider = FakeMediaProviderSession(capabilities: .init())
            provider.storedBookProgress = 0.05
            let reopened = BookReaderModel(item: item, fileURL: url, provider: provider, accountScope: scope)
            await reopened.open()

            #expect(reopened.state == .loaded)
            let restored = try #require(reopened.initialLocation)
            #expect(restored.href.isEquivalentTo(saved.href))
            #expect(restored.locations.progression == 0.75)
            #expect(restored.locations.totalProgression == 0.875)
            #expect(provider.bookProgressCallCount == 0)
        }

        @Test("invalid local EPUB becomes a readable failure")
        func invalidPublication() async throws {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
            try Data("This is not an EPUB archive.".utf8).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let model = makeModel(url: url)
            await model.open()

            guard case let .failed(message) = model.state else {
                Issue.record("Invalid EPUB did not fail cleanly")
                return
            }
            #expect(!message.isEmpty)
            #expect(model.publication == nil)
        }

        private func makeModel(url: URL) -> BookReaderModel {
            BookReaderModel(
                item: MediaItem(id: "reader-fixture", name: "Reader fixture", type: .book),
                fileURL: url,
                provider: nil,
                accountScope: AccountScope(serverID: UUID().uuidString, userID: "reader-test")
            )
        }

        private func fixtureURL() throws -> URL {
            try #require(Bundle(for: ReaderFixtureBundle.self).url(forResource: "ReaderOwnership", withExtension: "epub"))
        }
    }

    private final class ReaderFixtureBundle: NSObject {}
#endif
