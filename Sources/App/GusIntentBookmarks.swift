import AppIntents
import Foundation

/// User-created positions are local to one Jellyfin profile and one media version.
struct GusAudiobookBookmark: Codable, Equatable {
    let id: UUID
    let name: String
    let itemID: String
    let sourceID: String?
    let ticks: Int
}

@MainActor
struct GusAudiobookBookmarks {
    let credential: SessionCredential
    var defaults: UserDefaults = .standard

    private var key: String {
        "dev.ericslutz.gus.audiobookBookmarks." + GusIntentID.make(resource: "bookmarks", id: "1", provider: credential.providerKind, scope: AccountScope(serverID: credential.serverID, userID: credential.userID))
    }

    func all() throws -> [GusAudiobookBookmark] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return try JSONDecoder().decode([GusAudiobookBookmark].self, from: data)
    }

    func add(name: String, itemID: String, sourceID: String?, ticks: Int) throws -> GusAudiobookBookmark {
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= 256, ticks >= 0 else {
            throw GusError.server(String(localized: "Use a bookmark name between 1 and 256 characters and a valid position."))
        }
        var bookmarks = try all()
        if let existing = bookmarks.first(where: { $0.itemID == itemID && $0.sourceID == sourceID && $0.ticks == ticks && $0.name == label }) {
            return existing
        }
        let bookmark = GusAudiobookBookmark(id: UUID(), name: label, itemID: itemID, sourceID: sourceID, ticks: ticks)
        bookmarks.append(bookmark)
        try defaults.set(JSONEncoder().encode(bookmarks), forKey: key)
        return bookmark
    }

    func remove(_ id: UUID) throws {
        let bookmarks = try all().filter { $0.id != id }
        try defaults.set(JSONEncoder().encode(bookmarks), forKey: key)
    }

    func forget() {
        defaults.removeObject(forKey: key)
    }
}

struct GusBookmarkEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Audiobook Bookmark"
    static let defaultQuery = GusBookmarkQuery()
    let id: String
    @Property(title: "Name") var name: String
    @Property(title: "Book") var book: String
    @Property(title: "Position in Seconds") var position: Int

    @MainActor
    init(bookmark: GusAudiobookBookmark, item: MediaItem, session: SessionStore) {
        id = GusIntentID.make(resource: "bookmark", id: bookmark.id.uuidString, provider: session.server.providerKind, scope: session.references.scope)
        name = bookmark.name
        book = item.displayTitle
        position = bookmark.ticks / PlaybackTime.ticksPerSecond
    }

    var displayRepresentation: DisplayRepresentation {
        .init(title: "\(name)", subtitle: "\(book)")
    }
}

struct GusBookmarkQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [GusBookmarkEntity] {
        let session = try await GusIntentRuntime.session()
        let requested = identifiers.compactMap { GusIntentID.value($0, resource: "bookmark", provider: session.server.providerKind, scope: session.references.scope) }.compactMap(UUID.init(uuidString:))
        let bookmarks = try GusAudiobookBookmarks(credential: session.lease.credential).all()
        return try await entities(requested.compactMap { id in bookmarks.first(where: { $0.id == id }) }, session: session)
    }

    @MainActor
    func entities(matching string: String) async throws -> [GusBookmarkEntity] {
        let session = try await GusIntentRuntime.session()
        let bookmarks = try GusAudiobookBookmarks(credential: session.lease.credential).all()
        return try await entities(bookmarks.filter { $0.name.localizedStandardContains(string) }, session: session)
    }

    @MainActor
    func suggestedEntities() async throws -> [GusBookmarkEntity] {
        await GusIntentRuntime.personalSuggestions { session in
            let recent = try GusAudiobookBookmarks(credential: session.lease.credential).all().suffix(8).reversed()
            return try await entities(Array(recent), session: session)
        }
    }

    @MainActor
    func entities(_ bookmarks: [GusAudiobookBookmark], session: SessionStore) async throws -> [GusBookmarkEntity] {
        var loaded: [String: MediaItem] = [:]
        for id in Set(bookmarks.map(\.itemID)) {
            do {
                let item = try await session.mediaProvider.item(id: id)
                try GusIntentRuntime.validate(session)
                if item.id == id, item.type == .audioBook, item.providerKind == session.server.providerKind {
                    loaded[id] = item
                }
            } catch where GusError(from: error) == .notFound { continue }
            catch where GusIntentRuntime.canUseDownload(after: error) {
                if let item = GusIntentRuntime.download(id: id, in: session)?.playbackItem, item.type == .audioBook {
                    loaded[id] = item
                }
            }
        }
        try GusIntentRuntime.validate(session)
        return bookmarks.compactMap { bookmark in
            guard let item = loaded[bookmark.itemID], ContentRatingGate.admitsStored(item) else { return nil }
            return GusBookmarkEntity(bookmark: bookmark, item: item, session: session)
        }
    }

    @MainActor
    func record(_ entity: GusBookmarkEntity, in session: SessionStore) throws -> GusAudiobookBookmark {
        let id = GusIntentID.value(entity.id, resource: "bookmark", provider: session.server.providerKind, scope: session.references.scope)
        let store = GusAudiobookBookmarks(credential: session.lease.credential)
        guard let id, let record = try store.all().first(where: { $0.id.uuidString == id }) else { throw GusError.notFound }
        return record
    }
}

struct SaveGusBookmarkIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Audiobook Bookmark"
    static let description = IntentDescription("Save the current position on this device, or enter the position in seconds.", categoryName: "Audiobooks")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Audiobook", query: GusMediaQuery(type: .audioBook)) var audiobook: GusMediaEntity
    @Parameter(title: "Name") var name: String
    @Parameter(title: "Position in Seconds") var position: Int?
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<GusBookmarkEntity> {
        let session = try await GusIntentRuntime.session()
        let book = try await GusIntentRuntime.resolveForPlayback(audiobook, in: session)
        guard book.type == .audioBook, let id = book.id else { throw GusError.notFound }
        let request = PlaybackRequest(item: book)
        var source = PlaybackChoicePosition.sourceID(for: request, session: session, downloads: .shared)
        var ticks = PlaybackChoicePosition.ticks(for: request, session: session, progress: .shared, downloads: .shared)
        #if os(iOS)
            if let playing = AppModel.shared.audioPlayback.store, let current = playing.bookmarkPosition(for: id, session: session) {
                ticks = current.ticks
                source = current.source
            }
        #endif
        if let position {
            let result = position.multipliedReportingOverflow(by: PlaybackTime.ticksPerSecond)
            guard !result.overflow, result.partialValue >= 0 else { throw GusError.server(String(localized: "Choose a valid playback position.")) }
            ticks = result.partialValue
        }
        guard let ticks, book.mediaSources.count <= 1 || source != nil else {
            throw GusError.server(String(localized: "Play the audiobook first or enter a position in seconds."))
        }
        let duration = book.mediaSources.first(where: { $0.id == source })?.runTimeTicks ?? book.runTimeTicks
        guard duration.map({ $0 <= 0 || ticks < $0 }) != false else {
            throw GusError.server(String(localized: "This position is beyond the selected version’s runtime."))
        }
        let bookmark = try GusAudiobookBookmarks(credential: session.lease.credential).add(name: name, itemID: id, sourceID: source, ticks: ticks)
        return .result(value: GusBookmarkEntity(bookmark: bookmark, item: book, session: session))
    }
}

struct GetGusBookmarksIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Audiobook Bookmarks"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Audiobook", query: GusMediaQuery(type: .audioBook)) var audiobook: GusMediaEntity?
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[GusBookmarkEntity]> {
        let session = try await GusIntentRuntime.session()
        var bookmarks = try GusAudiobookBookmarks(credential: session.lease.credential).all()
        if let audiobook {
            let book = try await GusIntentRuntime.resolveForPlayback(audiobook, in: session)
            guard book.type == .audioBook else { throw GusError.notFound }
            bookmarks = bookmarks.filter { $0.itemID == book.id }
        }
        return try await .result(value: GusBookmarkQuery().entities(bookmarks, session: session))
    }
}

struct ResumeGusBookmarkIntent: AppIntent {
    static let title: LocalizedStringResource = "Play from Audiobook Bookmark"
    static let supportedModes: IntentModes = .foreground
    @Parameter(title: "Bookmark") var bookmark: GusBookmarkEntity
    @MainActor
    func perform() async throws -> some IntentResult {
        let session = try await GusIntentRuntime.session()
        let record = try GusBookmarkQuery().record(bookmark, in: session)
        let placeholder = MediaItem(id: record.itemID, type: .audioBook)
        let id = GusIntentID.make(resource: "media", id: record.itemID, provider: session.server.providerKind, scope: session.references.scope)
        let book = try await GusIntentRuntime.resolveForPlayback(GusMediaEntity(id: id, item: placeholder), in: session)
        guard book.type == .audioBook,
              record.sourceID.map({ source in book.mediaSources.contains { $0.id == source } }) ?? (book.mediaSources.count <= 1),
              try GusBookmarkQuery().record(bookmark, in: session) == record else { throw GusError.notFound }
        let source = book.mediaSources.first { $0.id == record.sourceID }
        guard (source?.runTimeTicks ?? book.runTimeTicks).map({ $0 <= 0 || record.ticks < $0 }) != false else { throw GusError.notFound }
        let request = PlaybackRequest(item: book, streamSelection: .init(audioStreamIndex: nil, subtitleStreamIndex: nil, mediaSourceID: record.sourceID), startPositionTicks: record.ticks)
        try GusIntentRuntime.open(book, in: session, play: true, request: request)
        return .result()
    }
}

struct DeleteGusBookmarkIntent: AppIntent {
    static let title: LocalizedStringResource = "Delete Audiobook Bookmark"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Bookmark") var bookmark: GusBookmarkEntity
    @MainActor
    func perform() async throws -> some IntentResult {
        let session = try await GusIntentRuntime.session()
        let record = try GusBookmarkQuery().record(bookmark, in: session)
        try GusAudiobookBookmarks(credential: session.lease.credential).remove(record.id)
        return .result()
    }
}
