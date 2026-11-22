import AppIntents
import Foundation

enum GusSearchMediaType: String, AppEnum {
    case movie, series, episode, book, audioBook, musicAlbum, audio
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Search Media Type"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .movie: "Movie", .series: "Series", .episode: "Episode", .book: "Book",
        .audioBook: "Audiobook", .musicAlbum: "Album", .audio: "Song",
    ]
}

enum GusLibraryStatus: String, AppEnum {
    case all, played, unplayed, resumable
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Library Status"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .all: "All", .played: "Finished", .unplayed: "Unplayed", .resumable: "In Progress",
    ]
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct FilterGusLibraryIntent: AppIntent {
    static let title: LocalizedStringResource = "Filter Library Items"
    static let description = IntentDescription("Find up to 60 library items that match all supplied filters. Genres and credited people use the names in your library.", categoryName: "Library")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Media Type") var mediaType: GusSearchMediaType?
    @Parameter(title: "Keyword") var keyword: String?
    @Parameter(title: "Genre") var genre: String?
    @Parameter(title: "Credited Person") var person: String?
    @Parameter(title: "Character") var character: String?
    @Parameter(title: "Earliest Year") var earliestYear: Int?
    @Parameter(title: "Latest Year") var latestYear: Int?
    @Parameter(title: "Earliest Premiere Date", kind: .date) var earliestPremiereDate: Date?
    @Parameter(title: "Latest Premiere Date", kind: .date) var latestPremiereDate: Date?
    @Parameter(title: "Minimum Minutes") var minimumMinutes: Int?
    @Parameter(title: "Maximum Minutes") var maximumMinutes: Int?
    @Parameter(title: "Status", default: .all) var status: GusLibraryStatus
    @Parameter(title: "Favorites Only", default: false) var favoritesOnly: Bool

    func filters() throws -> GusSearchIntent {
        guard Self.validRange(earliestYear, latestYear, minimum: 1), Self.validRange(minimumMinutes, maximumMinutes, minimum: 0) else {
            throw GusError.server(String(localized: "Check the range. The minimum must be no greater than the maximum."))
        }
        func phrases(_ text: String?) -> [String] {
            guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return [] }
            return [value]
        }
        var filters = GusSearchIntent()
        filters.mediaTypes = mediaType.flatMap { MediaItemType(rawValue: $0.rawValue) }.map { [$0] } ?? []
        filters.keywords = phrases(keyword)
        filters.genres = phrases(genre)
        filters.people = phrases(person)
        filters.characters = phrases(character)
        filters.minimumYear = earliestYear
        filters.maximumYear = latestYear
        filters.premieredOnOrAfter = earliestPremiereDate.flatMap { Self.premiereDay($0) }
        filters.premieredBefore = latestPremiereDate.flatMap { Self.premiereDay($0, endOfDay: true) }
        if let lower = filters.premieredOnOrAfter, let upper = filters.premieredBefore, lower >= upper {
            throw GusError.server(String(localized: "Choose an earliest premiere date on or before the latest date."))
        }
        filters.minimumMinutes = minimumMinutes
        filters.maximumMinutes = maximumMinutes
        filters.status = MediaItemStatusFilter(rawValue: status.rawValue) ?? .all
        filters.favoritesOnly = favoritesOnly
        return filters
    }

    /// Jellyfin encodes a premiere day at midnight UTC. Preserve the date the user picked in their time zone.
    static func premiereDay(_ date: Date, timeZone: TimeZone = .current, endOfDay: Bool = false) -> Date? {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        guard let day = utc.date(from: local.dateComponents([.year, .month, .day], from: date)) else { return nil }
        return endOfDay ? utc.date(byAdding: .day, value: 1, to: day) : day
    }

    static func validRange(_ lower: Int?, _ upper: Int?, minimum: Int) -> Bool {
        (lower ?? minimum) >= minimum && (upper ?? Int.max) >= (lower ?? minimum)
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[GusMediaEntity]> {
        let session = try await GusIntentRuntime.session()
        let results = try await session.libraryIntelligence.search(filters())
        try GusIntentRuntime.validate(session)
        return .result(value: results.compactMap { GusIntentRuntime.entity($0, in: session) })
    }
}

struct AskGusLibraryIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Library in Natural Language"
    static let description = IntentDescription("Interpret a description using the intelligence settings for this profile and return matches from its Jellyfin library.", categoryName: "Library")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Description") var prompt: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[GusMediaEntity]> {
        let session = try await GusIntentRuntime.session()
        guard session.intelligenceAccess.usesNaturalSearch else {
            throw GusError.server(String(localized: "Natural language search isn’t available for this profile. Use Filter Library Items."))
        }
        let plan = try await GusIntelligenceModel(session: session).interpretLibrary(prompt)
        try GusIntentRuntime.validate(session)
        guard plan.unsupported.isEmpty, !plan.appliedFilters.isEmpty else {
            throw GusError.server(String(localized: "Gus couldn’t match that description to supported library filters."))
        }
        let results = try await session.libraryIntelligence.search(plan)
        try GusIntentRuntime.validate(session)
        guard session.intelligenceAccess.usesNaturalSearch else { throw GusError.cancelled }
        return .result(value: results.compactMap { GusIntentRuntime.entity($0, in: session) })
    }
}

enum GusLibraryShelf: String, AppEnum {
    case libraries, favorites, recentlyAdded, recentlyPlayed, recommendations
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Library Shelf"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .libraries: "Libraries", .favorites: "Favorites", .recentlyAdded: "Recently Added",
        .recentlyPlayed: "Recently Played", .recommendations: "For You",
    ]
}

struct GetGusShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Library Shelf"
    static let description = IntentDescription("Return up to 50 items from a shelf in the active profile.", categoryName: "Library")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Shelf") var shelf: GusLibraryShelf
    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$shelf)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[GusMediaEntity]> {
        let session = try await GusIntentRuntime.session()
        let items: [MediaItem]
        switch shelf {
        case .libraries:
            items = try await session.mediaProvider.userViews()
        case .recommendations:
            #if os(tvOS)
                let policy = ContentRatingGate.storedPolicy()
                let context = ForYouShelfState.Context(
                    cloudEnabled: false,
                    recommendationsEnabled: session.intelligencePreferences.forYouSyncEnabled,
                    limit: policy.limit.rawValue,
                    hideUnrated: policy.hideUnrated,
                    ageCeiling: policy.ageCeiling,
                    activityRevision: 0,
                    tasteRevision: 0
                )
                guard context.recommendationsEnabled else { throw GusError.server(String(localized: "Enable For You in Gus to use this shelf.")) }
                await session.forYouShelf.load(context, session: session)
                try GusIntentRuntime.validate(session)
                if let error = session.forYouShelf.error {
                    throw GusError.server(error)
                }
                guard session.forYouShelf.canDisplay(context, session: session), session.intelligencePreferences.forYouSyncEnabled else { throw GusError.cancelled }
                items = session.forYouShelf.picks.map(\.item)
            #else
                guard session.intelligencePreferences.recommendationsEnabled else { throw GusError.server(String(localized: "Enable For You in Gus to use this shelf.")) }
                items = try await session.libraryIntelligence.recommendations().map(\.item)
            #endif
        case .favorites, .recentlyAdded, .recentlyPlayed:
            var query = MediaItemQuery(startIndex: 0, limit: 50, isRecursive: true, sort: shelf == .recentlyAdded ? .recentlyAdded : .name)
            query.favoritesOnly = shelf == .favorites
            query.mostRecentlyPlayedFirst = shelf == .recentlyPlayed
            query.metadataOnly = true
            let page = try await session.mediaProvider.items(query: query)
            items = page.items.filter { item in
                (shelf != .recentlyPlayed || item.userData?.lastPlayedAt != nil) && (shelf != .favorites || item.userData?.isFavorite == true)
            }
        }
        try GusIntentRuntime.validate(session)
        return .result(value: Array(items.compactMap { GusIntentRuntime.entity($0, in: session) }.prefix(50)))
    }
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct GetGusContentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Contents of Library Item"
    static let description = IntentDescription("Get a page of library, album, playlist, collection, series, or folder items in server order. The first item is number 1.", categoryName: "Library")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Library Item") var item: GusMediaEntity
    @Parameter(title: "Starting Item", default: 1) var startingItem: Int
    @Parameter(title: "Maximum Items", default: 50) var maximumItems: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[GusMediaEntity]> {
        let session = try await GusIntentRuntime.session()
        let current = try await GusIntentRuntime.resolve(item, in: session)
        guard let id = current.id else { throw GusError.notFound }
        guard (1 ... 100).contains(maximumItems), startingItem >= 1, startingItem <= Int.max - maximumItems else {
            throw GusError.server(String(localized: "Choose a positive starting item and a page size from 1 to 100."))
        }
        let offset = startingItem - 1
        let provider = session.mediaProvider
        let contents: [MediaItem]
        switch current.type {
        case .playlist:
            guard let uuid = ServerMediaListID.uuid(id) else { throw GusError.notFound }
            contents = try await provider.mediaList(id: uuid, kind: .playlist).entries.dropFirst(offset).prefix(maximumItems).map(\.item)
        case .series:
            contents = try await Array(provider.seasons(seriesID: id).dropFirst(offset).prefix(maximumItems))
        case .season:
            guard let seriesID = current.seriesID else { throw GusError.notFound }
            contents = try await provider.episodesPage(seriesID: seriesID, seasonID: id, startIndex: offset, limit: maximumItems).items
        case .boxSet:
            contents = try await provider.collectionMembers(id: id, startIndex: offset, limit: maximumItems).items
        case .musicArtist, .musicAlbum, .photoAlbum, .folder, .collectionFolder:
            var query = MediaItemQuery(
                parentID: current.type == .musicArtist ? nil : id,
                artistID: current.type == .musicArtist ? id : nil,
                includeTypes: current.type == .musicArtist ? [.musicAlbum] : current.type == .musicAlbum ? [.audio] : nil,
                startIndex: offset,
                limit: maximumItems,
                sort: current.type == .musicAlbum ? .trackOrder : .name
            )
            query.metadataOnly = true
            contents = try await provider.items(query: query).items
        default: throw GusError.server(String(localized: "Choose a library, playlist, collection, album, series, season, artist, or folder."))
        }
        try GusIntentRuntime.validate(session)
        return .result(value: contents.compactMap { GusIntentRuntime.entity($0, in: session) })
    }
}
