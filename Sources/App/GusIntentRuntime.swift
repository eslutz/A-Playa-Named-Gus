import AppIntents
import Foundation

struct GusMediaEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Library Item")
    static let defaultQuery = GusMediaQuery()
    let id: String
    @Property(title: "Title") var title: String
    @Property(title: "Media Type") var kind: String
    @Property(title: "Year") var year: Int?
    @Property(title: "Premiere Date") var premiereDate: Date?
    @Property(title: "Series") var series: String?
    @Property(title: "Artist") var artist: String?
    @Property(title: "Genres") var genres: [String]
    @Property(title: "Duration") var duration: Measurement<UnitDuration>?
    let subtitle: String

    init(id: String, item: MediaItem) {
        self.id = id
        subtitle = [item.intentKind, item.yearText, item.seriesName, item.type == .episode ? item.episodeLocator : nil, item.artists.first ?? item.bookAuthorText].compactMap { $0 }.joined(separator: " · ")
        title = item.displayTitle
        kind = item.intentKind
        year = item.displayYear
        premiereDate = item.premiereDate
        series = item.seriesName
        artist = item.artists.first ?? item.albumArtist
        genres = item.genres
        duration = item.runTimeTicks.flatMap { $0 > 0 && item.type != .book ? Measurement(value: Double($0) / 10_000_000, unit: .seconds) : nil }
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }
}

private extension MediaItem {
    var intentKind: String {
        switch type {
        case .movie: String(localized: "Movie")
        case .series: String(localized: "Series")
        case .season: String(localized: "Season")
        case .episode: String(localized: "Episode")
        case .audio: String(localized: "Song")
        case .audioBook: String(localized: "Audiobook")
        case .book: String(localized: "Book")
        case .musicAlbum: String(localized: "Album")
        case .musicArtist: String(localized: "Artist")
        case .boxSet: String(localized: "Collection")
        case .collectionFolder: String(localized: "Library")
        case .folder: String(localized: "Folder")
        case .genre: String(localized: "Genre")
        case .video: String(localized: "Video")
        case .trailer: String(localized: "Trailer")
        case .playlist: String(localized: "Playlist")
        case .photo: String(localized: "Photo")
        case .photoAlbum: String(localized: "Photo Album")
        case .liveChannel: String(localized: "Channel")
        case .liveProgram: String(localized: "Program")
        case .recording: String(localized: "Recording")
        case .unknown, nil: String(localized: "Library Item")
        }
    }
}

struct GusMediaQuery: EntityStringQuery {
    let type: MediaItemType?

    init() {
        type = nil
    }

    init(type: MediaItemType) {
        self.type = type
    }

    private func accepts(_ item: MediaItem) -> Bool {
        type == nil || item.type == type
    }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [GusMediaEntity] {
        guard !identifiers.isEmpty else { return [] }
        let session = try await GusIntentRuntime.session()
        // Resolve a saved action only in the account that supplied its parameter.
        var members: [MediaItem] = []
        for identifier in identifiers {
            guard let id = GusIntentID.value(identifier, resource: "media", provider: session.server.providerKind, scope: session.references.scope) else { continue }
            do {
                let item = try await GusIntentRuntime.playbackItem(id: id, in: session)
                if accepts(item) {
                    members.append(item)
                }
            } catch where GusError(from: error) == .notFound { continue }
        }
        try GusIntentRuntime.validate(session)
        return members.compactMap { GusIntentRuntime.entity($0, in: session) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [GusMediaEntity] {
        let session = try await GusIntentRuntime.session()
        if type == .liveChannel {
            guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            let channels = try await GusIntentRuntime.channels(in: session)
            return channels.filter { $0.displayTitle.localizedStandardContains(string) }.compactMap { GusIntentRuntime.entity($0, in: session) }
        }
        return try await GusIntentRuntime.search(string, in: session, types: type.map { [$0] }, includeOffline: true).items.filter(accepts).compactMap { GusIntentRuntime.entity($0, in: session) }
    }

    @MainActor
    func suggestedEntities() async throws -> [GusMediaEntity] {
        await GusIntentRuntime.personalSuggestions { session in
            let items: [MediaItem]
            switch type {
            case .liveChannel:
                items = try await GusIntentRuntime.channels(in: session, limit: 8)
            case .playlist:
                items = try await session.mediaProvider.items(query: .init(includeTypes: [.playlist], startIndex: 0, limit: 8, isRecursive: true, sort: .name)).items
            case .series:
                let episodes = try await session.mediaProvider.nextUpItems(seriesID: nil, limit: 8)
                items = MediaPageLoader.unique(ContentRatingGate.filter(episodes).map(\.latestTVDisplayItem))
            default:
                items = try await session.mediaProvider.resumeItems(limit: 8)
            }
            return items.filter(accepts).compactMap { GusIntentRuntime.entity($0, in: session) }
        }
    }
}

@MainActor
enum GusIntentRuntime {
    /// System-initiated refreshes can run during sign-out or while offline.
    /// Publishing an empty list also retires the previous profile's choices.
    static func personalSuggestions<Entity>(_ load: @MainActor (SessionStore) async throws -> [Entity]) async -> [Entity] {
        guard let current = AppModel.shared.currentSession, current.isActive,
              current.systemSurfacePreferences.personalHistoryEnabled, !AppModel.shared.isTransitioning else { return [] }
        do {
            guard try await session() === current else { return [] }
            let result = try await load(current)
            try validate(current)
            return current.systemSurfacePreferences.personalHistoryEnabled ? result : []
        } catch {
            return []
        }
    }

    static func session() async throws -> SessionStore {
        let app = AppModel.shared
        await app.restoreForIntentIfNeeded()
        guard let session = app.currentSession else {
            throw GusError.server(String(localized: "Sign in to a Jellyfin server in A Playa Named Gus first."))
        }
        #if canImport(DeclaredAgeRange) && (os(iOS) || os(macOS))
            guard await session.ageRangeAccess.permitsExternalMedia(isCurrent: { app.currentSession === session && session.isActive }) else {
                throw GusError.server(String(localized: "Open Gus to check your age range."))
            }
        #endif
        try validate(session)
        return session
    }

    static func validate(_ session: SessionStore) throws {
        try Task.checkCancellation()
        guard session.isActive, AppModel.shared.currentSession === session, !AppModel.shared.isTransitioning else { throw GusError.cancelled }
        guard !ContentRatingGate.storedPolicy().awaitingRequiredRange else {
            throw GusError.server(String(localized: "Open Gus to check your age range."))
        }
    }

    static func entity(_ item: MediaItem, in session: SessionStore) -> GusMediaEntity? {
        guard let id = item.id, !id.isEmpty, item.providerKind == session.server.providerKind,
              ContentRatingGate.admitsStored(item) else { return nil }
        return GusMediaEntity(id: GusIntentID.make(resource: "media", id: id, provider: item.providerKind, scope: session.references.scope), item: item)
    }

    static func resolve(_ entity: GusMediaEntity, in session: SessionStore) async throws -> MediaItem {
        try validate(session)
        guard let id = GusIntentID.value(entity.id, resource: "media", provider: session.server.providerKind, scope: session.references.scope) else { throw GusError.notFound }
        return try await currentItem(id: id, in: session)
    }

    private static func currentItem(id: String, in session: SessionStore) async throws -> MediaItem {
        try validate(session)
        let item = try await session.mediaProvider.item(id: id)
        try validate(session)
        guard item.id == id, item.providerKind == session.server.providerKind, ContentRatingGate.admitsStored(item) else { throw GusError.notFound }
        return item
    }

    static func resolveForPlayback(_ entity: GusMediaEntity, in session: SessionStore) async throws -> MediaItem {
        guard let id = GusIntentID.value(entity.id, resource: "media", provider: session.server.providerKind, scope: session.references.scope) else { throw GusError.notFound }
        return try await playbackItem(id: id, in: session)
    }

    static func playbackItem(id: String, in session: SessionStore) async throws -> MediaItem {
        do { return try await currentItem(id: id, in: session) }
        catch where canUseDownload(after: error) && DownloadsAvailability.isSupported {
            try validate(session)
            if let record = download(id: id, in: session) {
                return record.playbackItem
            }
            let records = try completedDownloads(in: session)
            guard let album = DownloadedLibrary.albums(in: records).first(where: { $0.id == id }) else { throw error }
            return album
        }
    }

    static func completedDownloads(in session: SessionStore) throws -> [OfflineDownloadRecord] {
        try validate(session)
        let scope = session.references.scope
        let downloads = OfflineDownloadStore.shared
        downloads.load(serverID: scope.serverID, userID: scope.userID)
        if let failure = downloads.loadErrorMessage {
            throw GusError.server(failure)
        }
        return downloads.completedRecords(serverID: scope.serverID, userID: scope.userID).filter { $0.item.providerKind == session.server.providerKind }
    }

    static func canUseDownload(after error: Error) -> Bool {
        let failure = GusError(from: error)
        return failure == .offline || failure == .timeout
    }

    static func download(
        id: String, in session: SessionStore, files: OfflineDownloadFileStore = .shared,
        policy: ContentRatingGate.Policy = ContentRatingGate.storedPolicy()
    ) -> OfflineDownloadRecord? {
        let scope = session.references.scope
        guard DownloadsAvailability.isSupported,
              let record = files.record(forItemID: id, serverID: scope.serverID, userID: scope.userID),
              record.item.providerKind == session.server.providerKind,
              record.isAdmitted(by: policy.admits), files.localFileURL(for: record) != nil else { return nil }
        return record
    }

    static func localPlayback(for link: ContentLink, in session: SessionStore, after error: Error) -> ItemRef? {
        guard canUseDownload(after: error), (try? validate(session)) != nil,
              case .play = link, link.accepts(server: session.server), let record = download(id: link.itemID, in: session) else { return nil }
        var request = link.playbackRequest ?? record.playbackRequest
        guard request.streamSelection.mediaSourceID == nil || request.streamSelection.mediaSourceID == record.mediaSourceID else { return nil }
        request.item = record.playbackItem
        request.streamSelection.mediaSourceID = record.mediaSourceID
        return ItemRef(item: request.item, localOnly: true, serverID: session.server.id, userID: session.user.id, playbackRequest: request)
    }

    static func playDownloadedAlbum(for link: ContentLink, in session: SessionStore, audio: AudioPlaybackCoordinator, after error: Error) -> Bool {
        guard DownloadsAvailability.isSupported, canUseDownload(after: error), case .play = link, link.accepts(server: session.server),
              link.playbackRequest?.item.type == nil || link.playbackRequest?.item.type == .musicAlbum,
              let records = try? completedDownloads(in: session),
              DownloadedLibrary.albums(in: records).contains(where: { $0.id == link.itemID }) else { return false }
        let tracks = DownloadedLibrary.tracks(in: records, albumID: link.itemID)
        guard let first = tracks.first else { return false }
        audio.play(tracks: tracks.map(\.playbackItem), localOnly: true, request: first.playbackRequest, session: session, downloads: .shared)
        return true
    }

    static func search(_ text: String, in session: SessionStore, types: [MediaItemType]? = nil, includeOffline: Bool = false) async throws -> MediaItemPage {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { throw GusError.server(String(localized: "Enter a library title to search for.")) }
        var query = MediaItemQuery(searchTerm: term, includeTypes: types, startIndex: 0, limit: 50, isRecursive: true)
        query.metadataOnly = true
        let page: MediaItemPage
        do { page = try await session.mediaProvider.items(query: query) }
        catch where includeOffline && DownloadsAvailability.isSupported && canUseDownload(after: error) {
            try validate(session)
            let records = try completedDownloads(in: session)
            let policy = ContentRatingGate.storedPolicy()
            let local = records.filter { $0.isAdmitted(by: policy.admits) }.map(\.playbackItem)
            let items = (local + DownloadedLibrary.albums(in: records))
                .filter { item in item.displayTitle.localizedStandardContains(term) && (types == nil || item.type.map { types?.contains($0) == true } == true) }
            page = MediaItemPage(items: Array(items.prefix(query.limit)), totalRecordCount: items.count)
        }
        try validate(session)
        let total = page.totalRecordCount ?? (page.items.count == query.limit ? query.limit + 1 : page.items.count)
        return MediaItemPage(items: MediaPageLoader.unique(ContentRatingGate.filter(page.items)).filter { $0.id != nil && $0.providerKind == session.server.providerKind }, totalRecordCount: total)
    }

    static func channels(in session: SessionStore, limit: Int? = nil) async throws -> [MediaItem] {
        guard try await session.mediaProvider.liveTVAvailability() == .enabled else {
            throw GusError.server(String(localized: "Live TV isn’t available for this account."))
        }
        try validate(session)
        let items: [MediaItem]
        if let limit {
            items = try await session.mediaProvider.liveTVChannels(startIndex: 0, limit: limit).items
        } else {
            items = try await MediaPageLoader.collect(pageSize: 100) { start, count in
                try validate(session)
                return try await session.mediaProvider.liveTVChannels(startIndex: start, limit: count)
            }
        }
        try validate(session)
        return ContentRatingGate.filter(items).filter { $0.type == .liveChannel }
    }

    static func open(_ item: MediaItem, in session: SessionStore, play: Bool, request: PlaybackRequest? = nil) throws {
        try validate(session)
        guard let id = item.id, item.providerKind == session.server.providerKind, ContentRatingGate.admitsStored(item) else { throw GusError.notFound }
        let link: ContentLink
        if play, canPresentPlayer(for: item) {
            link = .play(id: id, serverID: session.server.id, provider: item.providerKind, request: request ?? PlaybackRequest(item: item))
        } else {
            link = .item(id: id, serverID: session.server.id, provider: item.providerKind)
        }
        AppNavigationModel.shared.open(link, for: session)
    }

    private static func canPresentPlayer(for item: MediaItem) -> Bool {
        switch item.type {
        case .movie, .episode, .video, .trailer, .audio, .audioBook, .photo, .playlist, .musicAlbum, .recording, .liveChannel: return true
        case .book:
            #if os(iOS)
                return true
            #else
                return false
            #endif
        default: return false
        }
    }

    static func playlistPlayer(_ item: MediaItem, in session: SessionStore, audio: AudioPlaybackCoordinator) async throws -> ItemRef? {
        if item.type == .musicAlbum, let id = item.id {
            let query = MediaItemQuery(parentID: id, includeTypes: [.audio], startIndex: 0, limit: 100, sort: .trackOrder)
            let page = try await session.mediaProvider.items(query: query)
            try validate(session)
            let total = try MediaPageLoader.validatedTotal(for: page, startIndex: 0)
            let tracks = ContentRatingGate.filter(MediaPageLoader.unique(page.items)).filter { $0.type == .audio && $0.id != nil }
            guard !tracks.isEmpty else { throw GusError.notFound }
            let more = total.map { page.items.count < $0 } ?? (page.items.count == query.limit)
            let continuation = more ? AudioQueueContinuation(query: query, nextStartIndex: page.items.count, totalRecordCount: total) : nil
            audio.play(tracks: tracks, continuation: continuation, session: session, downloads: .shared)
            return nil
        }
        guard item.type == .playlist, let playlistID = item.id.flatMap(ServerMediaListID.uuid) else { throw GusError.notFound }
        let lists = ServerMediaListsStore.shared
        let scope = session.references.scope
        await lists.refresh(id: playlistID, kind: .playlist, session: session)
        try validate(session)
        guard let playlist = lists.videoPlaylist(id: playlistID, scope: scope, supplemental: .shared),
              let startID = playlist.playbackAction.entryID,
              let index = playlist.entries.firstIndex(where: { $0.id == startID })
        else {
            throw GusError.server(String(localized: "This playlist has no available starting item."))
        }
        let entries = playlist.entries.map(\.reference.item)
        let first = entries[index]
        guard ContentRatingGate.admitsStored(first) else { throw GusError.notFound }
        if entries.allSatisfy(\.isAudioPlayable) {
            let admitted = entries.enumerated().filter { ContentRatingGate.admitsStored($0.element) }
            guard let start = admitted.firstIndex(where: { $0.offset == index }) else { throw GusError.notFound }
            audio.play(tracks: admitted.map(\.element), startIndex: start, session: session, downloads: .shared)
            return nil
        }
        if entries.allSatisfy({ [.movie, .episode, .video].contains($0.type) }) {
            return ItemRef(item: first, serverID: scope.serverID, userID: scope.userID, playlistID: playlist.id, playlistEntryID: startID)
        }
        guard canPresentPlayer(for: first), first.type != .playlist else { throw GusError.notFound }
        return ItemRef(item: first, serverID: scope.serverID, userID: scope.userID)
    }
}
