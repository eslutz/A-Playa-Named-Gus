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

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
