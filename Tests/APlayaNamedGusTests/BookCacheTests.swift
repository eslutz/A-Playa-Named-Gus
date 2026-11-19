import CoreGraphics
import Foundation
@testable import Gus
import Testing

@Suite("Book cache and progress scoping")
struct BookCacheTests {
    @Test("book cache destinations are scoped by server and user")
    func cacheDestinationsAreScopedByAccount() throws {
        let root = try temporaryDirectory()
        let item = MediaItem(id: "book-1", name: "Dracula: A/B", type: .book)
        let adultScope = AccountScope(serverID: "server-adult", userID: "adult")
        let childScope = AccountScope(serverID: "server-child", userID: "child")

        let adultURL = try BookFileProvider.cacheDestination(
            for: item,
            fileExtension: "epub",
            scope: adultScope,
            cachesDirectory: root
        )
        let childURL = try BookFileProvider.cacheDestination(
            for: item,
            fileExtension: "epub",
            scope: childScope,
            cachesDirectory: root
        )

        #expect(adultURL != childURL)
        #expect(adultURL.path.contains(adultScope.storageKey))
        #expect(childURL.path.contains(childScope.storageKey))
        #expect(adultURL.lastPathComponent == "Dracula  A B.epub")
    }

    @MainActor
    @Test("book progress locators are scoped by server and user")
    func progressLocatorsAreScopedByAccount() throws {
        let directory = try temporaryDirectory()
        let adultScope = AccountScope(serverID: "server-adult", userID: "adult")
        let childScope = AccountScope(serverID: "server-child", userID: "child")
        let store = BookProgressStore(directory: directory)

        store.save(locatorJSON: #"{"href":"adult"}"#, forItemID: "book-1", scope: adultScope)
        store.save(locatorJSON: #"{"href":"child"}"#, forItemID: "book-1", scope: childScope)
        store.flush()

        let reloaded = BookProgressStore(directory: directory)
        #expect(reloaded.locatorJSON(forItemID: "book-1", scope: adultScope) == #"{"href":"adult"}"#)
        #expect(reloaded.locatorJSON(forItemID: "book-1", scope: childScope) == #"{"href":"child"}"#)
        #expect(reloaded.locatorJSON(forItemID: "book-2", scope: adultScope) == nil)
    }

    @MainActor
    @Test("Read and Share use one named original, including offline", arguments: ["epub", "pdf"])
    func fetchOriginalAndShareOffline(fileExtension: String) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let item = MediaItem(canDownload: true, id: "book", name: "Display title", type: .book)
        let provider = FakeMediaProviderSession(capabilities: .init(supportsDownloads: true))
        let files = BookFileProvider(session: .makeTestSession(mediaProvider: provider), cachesDirectory: root)
        provider.itemHandler = { _ in item }
        let data = try originalBytes(for: fileExtension)
        let original = root.appendingPathComponent("transfer.tmp")
        let filename = "Original edition." + fileExtension
        try data.write(to: original)
        provider.downloadBookHandler = { _ in (original, filename) }

        let share = try await files.fileForSharing(for: item)
        #expect(share.lastPathComponent == filename)
        #expect(try Data(contentsOf: share) == data)
        provider.itemHandler = { _ in throw GusError.offline }
        provider.downloadBookHandler = { _ in throw GusError.offline }
        #expect(try await files.localFile(for: item) == share)
        #expect(try await files.fileForSharing(for: item) == share)
        var revoked = item
        revoked.canDownload = false
        await #expect(throws: GusError.forbidden) { try await files.fileForSharing(for: revoked) }
    }

    @MainActor
    @Test("Share preserves authentication, permission, and network failures", arguments: [GusError.unauthorized, .forbidden, .offline])
    func downloadFailures(error: GusError) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let item = MediaItem(canDownload: true, id: "book", name: "Display title", type: .book)
        let provider = FakeMediaProviderSession(capabilities: .init(supportsDownloads: true))
        let files = BookFileProvider(session: .makeTestSession(mediaProvider: provider), cachesDirectory: root)
        provider.itemHandler = { _ in item }
        provider.downloadBookHandler = { _ in throw error }
        await #expect(throws: error) { try await files.fileForSharing(for: item) }
    }

    @MainActor
    @Test("Sharing a completed offline download retains the managed file and its EPUB contents")
    func shareManagedDownload() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var item = MediaItem(canDownload: true, id: "book", name: "Offline title", type: .book)
        item.originalBookFilename = "Original offline edition.epub"
        let provider = FakeMediaProviderSession(capabilities: .init(supportsDownloads: true))
        provider.itemHandler = { _ in throw GusError.offline }
        let session = SessionStore.makeTestSession(mediaProvider: provider)
        let store = OfflineDownloadFileStore(directory: root)
        let record = store.prepareDownloadRecord(item: item, serverID: session.server.id, userID: session.user.id, fileExtension: "epub", status: .complete, progress: 1)
        let saved = URL(fileURLWithPath: record.filePath)
        let bytes = try originalBytes(for: "epub")
        try bytes.write(to: saved)
        let downloads = OfflineDownloadStore(fileStore: store, coordinator: FakeDownloadSessionCoordinator())
        let files = BookFileProvider(session: session, downloads: downloads, cachesDirectory: root)
        #expect(try await files.localFile(for: item) == saved)
        let share = try await files.fileForSharing(for: item)
        #expect(share.lastPathComponent == "Original offline edition.epub")
        #expect(try Data(contentsOf: share) == bytes)
        #expect(try Data(contentsOf: saved) == bytes)
    }

    @Test("Audiobook fallback requires matching author tags and excludes the narrator")
    func audiobookCredits() {
        var item = MediaItem(albumArtist: "Joe Schreiber", artists: ["joe schreiber"], people: [.init(name: "Sean Kenin", creditType: "Narrator")], type: .audioBook)
        #expect(item.bookAuthorNames == ["Joe Schreiber"])
        #expect(item.bookNarratorNames == ["Sean Kenin"])
        item.people.append(.init(name: "Explicit Credit", creditType: "Writer"))
        #expect(item.bookAuthorNames == ["Explicit Credit"])
        item.people.removeLast()
        item.artists = ["Someone Else"]
        #expect(item.bookAuthorNames.isEmpty)
        item.albumArtist = "Sean Kenin"
        item.artists = ["Sean Kenin"]
        #expect(item.bookAuthorNames.isEmpty)
    }

    @Test("A series byline uses distinct accessible volume credits in volume order")
    func seriesCredits() throws {
        func book(_ index: Int, authors: [String]) -> MediaItem {
            MediaItem(id: String(index), indexNumber: index, people: authors.map { MediaPerson(name: $0, creditType: "Author") }, seriesName: "Saga", type: .book)
        }
        let first = book(1, authors: ["Author A", "Author B"])
        let second = book(2, authors: ["Author A", "Author B"])
        let different = book(3, authors: ["author b", "Author C"])
        let blank = book(4, authors: [])
        let key = try #require(BookSeriesKey(item: first))
        #expect(BookSeriesCatalog([blank]).series(key)?.authorNames == [])
        #expect(BookSeriesCatalog([book(1, authors: ["Author A"]), blank]).series(key)?.authorNames == ["Author A"])
        #expect(BookSeriesCatalog([second, first]).series(key)?.authorNames == ["Author A", "Author B"])
        #expect(BookSeriesCatalog([different, second, blank, first]).series(key)?.authorNames == ["Author A", "Author B", "Author C"])
    }

    private final class FixtureBundle: NSObject {}

    private func originalBytes(for fileExtension: String) throws -> Data {
        if fileExtension == "epub" {
            let fixture = try #require(Bundle(for: FixtureBundle.self).url(forResource: "ReaderOwnership", withExtension: "epub"))
            return try Data(contentsOf: fixture)
        }
        var page = CGRect(x: 0, y: 0, width: 200, height: 300)
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &page, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
