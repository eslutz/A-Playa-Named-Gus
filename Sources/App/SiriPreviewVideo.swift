#if GUS_SIRI_VIDEO_27_3 && canImport(MediaIntents) && (os(iOS) || os(tvOS) || os(visionOS))
    import AppIntents
    import Foundation
    import MediaIntents

    /// Only Config/SiriDeveloperPreview.xcconfig enables these declarations, with a 27.3 deployment target.
    /// VideoSearch is a MediaIntents request. Its urls case differs from AudioSearch's url case.
    @MainActor
    private final class GusVideoCatalog {
        let session: SessionStore
        private let policy: ContentRatingGate.Policy
        private var loaded = [String: MediaItem]()
        private var liveTV: Bool?

        init(session: SessionStore) {
            self.session = session
            policy = ContentRatingGate.storedPolicy()
        }

        func validate() throws {
            try GusIntentRuntime.validate(session)
            guard ContentRatingGate.storedPolicy() == policy else { throw GusError.cancelled }
        }

        func identifier(_ item: MediaItem) -> String? {
            GusIntentRuntime.entity(item, in: session)?.id
        }

        func item(rawID: String) async throws -> MediaItem? {
            try validate()
            if let result = loaded[rawID] {
                return result
            }
            do {
                let result = try await GusIntentRuntime.playbackItem(id: rawID, in: session)
                try validate()
                guard result.id == rawID, identifier(result) != nil else { return nil }
                loaded[rawID] = result
                return result
            } catch where GusError(from: error) == .notFound { return nil }
        }

        func item(identifier: String) async throws -> MediaItem? {
            guard let id = GusIntentID.value(identifier, resource: "media", provider: session.server.providerKind, scope: session.references.scope) else { return nil }
            return try await item(rawID: id)
        }

        func candidates(for search: MediaIntents.VideoSearch, types: [MediaItemType]) async throws -> [MediaItem] {
            switch search.criteria {
            case let .searchQuery(text):
                return try await GusIntentRuntime.search(text, in: session, types: types, includeOffline: true).items
            case let .urls(urls):
                var results = [MediaItem]()
                for url in urls.prefix(25) {
                    guard let link = ContentLink(url: url), link.serverID == session.server.id, link.provider == session.server.providerKind,
                          let result = try await item(rawID: link.itemID) else { continue }
                    results.append(result)
                }
                return MediaPageLoader.unique(results)
            case .unspecified:
                guard session.systemSurfacePreferences.personalHistoryEnabled else { return [] }
                let rows = try await session.mediaProvider.resumeItems(limit: 50)
                try validate()
                return rows.filter { $0.type.map(types.contains) == true }
            @unknown default: return []
            }
        }

        func show(for child: MediaItem) async throws -> GusSiriShow? {
            guard let id = child.seriesID, let parent = try await item(rawID: id), parent.type == .series,
                  let identifier = identifier(parent) else { return nil }
            return GusSiriShow(id: identifier, item: parent, catalog: self)
        }

        /// Persist a credit in the context of its admitted title. A restricted or removed title no longer resolves its cast.
        func credits(_ parent: MediaItem) -> [GusSiriVideoPerson] {
            guard let ownerID = parent.id else { return [] }
            return parent.people.compactMap { credit in
                guard let id = credit.id, !id.isEmpty, let name = credit.name, !name.isEmpty,
                      let payload = try? JSONEncoder().encode([ownerID, id]) else { return nil }
                let identifier = GusIntentID.make(resource: "video-credit", id: payload.base64EncodedString(), provider: parent.providerKind, scope: session.references.scope)
                return GusSiriVideoPerson(id: identifier, name: name, credit: credit)
            }
        }

        func canUseLiveTV() async throws -> Bool {
            try validate()
            if let liveTV {
                return liveTV
            }
            let enabled = try await session.mediaProvider.liveTVAvailability() == .enabled
            try validate()
            liveTV = enabled
            return enabled
        }

        func play(_ id: String, types: [MediaItemType]) async throws {
            guard let item = try await item(identifier: id), item.type.map(types.contains) == true else { throw GusError.notFound }
            switch item.type {
            case .series, .season:
                let episode = try await PlaybackDeadline.run(for: .seconds(20)) { try await self.episode(for: item) }
                guard let episode, let raw = episode.id,
                      let current = try await self.item(rawID: raw), current.type == .episode,
                      current.seriesID == episode.seriesID, item.type == .series || current.parentID == item.id else { throw GusError.notFound }
                try GusIntentRuntime.open(current, in: session, play: true)
            case .episode:
                guard try await show(for: item) != nil else { throw GusError.notFound }
                if let parentID = item.parentID {
                    guard let season = try await self.item(rawID: parentID), season.type == .season, season.seriesID == item.seriesID else { throw GusError.notFound }
                }
                try GusIntentRuntime.open(item, in: session, play: true)
            case .liveChannel:
                guard try await canUseLiveTV() else { throw GusError.forbidden }
                guard GusSiriFreeform.classification(item) != nil else { throw GusError.notFound }
                try GusIntentRuntime.open(item, in: session, play: true)
            case .trailer:
                guard GusSiriFreeform.classification(item) != nil else { throw GusError.notFound }
                try GusIntentRuntime.open(item, in: session, play: true)
            default:
                try GusIntentRuntime.open(item, in: session, play: true)
            }
        }

        private func episode(for parent: MediaItem) async throws -> MediaItem? {
            guard let seriesID = parent.type == .series ? parent.id : parent.seriesID,
                  let series = try await item(rawID: seriesID), series.type == .series else { return nil }
            let next = try await session.mediaProvider.nextUpItems(seriesID: seriesID, limit: 50)
            try validate()
            if let result = next.first(where: { $0.type == .episode && $0.seriesID == seriesID && (parent.type == .series || $0.parentID == parent.id) && identifier($0) != nil }) {
                return result
            }
            let seasons: [MediaItem]
            if parent.type == .season {
                seasons = [parent]
            } else {
                let all = try await session.mediaProvider.seasons(seriesID: seriesID)
                try validate()
                let admitted = all.filter { $0.type == .season && $0.seriesID == seriesID && identifier($0) != nil }
                seasons = admitted.filter { $0.indexNumber != 0 } + admitted.filter { $0.indexNumber == 0 }
            }
            for season in seasons {
                guard let seasonID = season.id else { continue }
                var offset = 0
                var total: Int?
                var previous: [MediaItem]?
                while true {
                    try validate()
                    let page = try await session.mediaProvider.episodesPage(seriesID: seriesID, seasonID: seasonID, startIndex: offset, limit: 50)
                    try validate()
                    total = try MediaPageLoader.validatedTotal(for: page, startIndex: offset, previousTotal: total)
                    if let result = page.items.first(where: { $0.type == .episode && $0.seriesID == seriesID && $0.parentID == seasonID && identifier($0) != nil }) {
                        return result
                    }
                    if page.items.isEmpty || page.items == previous {
                        break
                    }
                    previous = page.items
                    offset += page.items.count
                    if total.map({ offset >= $0 }) ?? (page.items.count < 50) {
                        break
                    }
                }
            }
            return nil
        }
    }

    private protocol GusVideoProjection: AppEntity where ID == String {
        static var types: [MediaItemType] { get }
        @MainActor static func project(_ item: MediaItem, id: String, in catalog: GusVideoCatalog) async throws -> Self?
    }

    @MainActor private func videoEntities<T: GusVideoProjection>(_ type: T.Type, ids: [String]? = nil, search: MediaIntents.VideoSearch? = nil) async throws -> [T] {
        let catalog = try await GusVideoCatalog(session: GusIntentRuntime.session())
        var items = [MediaItem]()
        if let search {
            items = try await catalog.candidates(for: search, types: type.types)
        } else {
            for id in ids ?? [] {
                if let item = try await catalog.item(identifier: id) {
                    items.append(item)
                }
            }
        }
        var results = [T]()
        for item in items {
            guard item.type.map(type.types.contains) == true, let id = catalog.identifier(item),
                  let value = try await type.project(item, id: id, in: catalog) else { continue }
            results.append(value)
        }
        try catalog.validate()
        if let search, case .unspecified = search.criteria, !catalog.session.systemSurfacePreferences.personalHistoryEnabled {
            return []
        }
        return results
    }

    private func videoDuration(_ item: MediaItem) -> Duration? {
        guard let ticks = item.runTimeTicks, ticks > 0 else { return nil }
        return .seconds(PlaybackTime.seconds(fromTicks: ticks))
    }

    @AppEnum(schema: .video.personRole)
    enum GusSiriVideoRole: String {
        case actor, director, producer, writer, creator, executiveProducer, other
        static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
            .actor: "Actor", .director: "Director", .producer: "Producer", .writer: "Writer", .creator: "Creator",
            .executiveProducer: "Executive Producer", .other: "Other",
        ]
    }

    @AppEntity(schema: .video.person)
    struct GusSiriVideoPerson {
        static let defaultQuery = Query()
        let id: String
        var name: String
        var roles: [GusSiriVideoRole]
        var image: GusSiriVideoImage?
        var url: URL?
        var description: String?
        var characterNames: [String]
        var displayRepresentation: DisplayRepresentation {
            .init(title: "\(name)")
        }

        init(id: String, name: String, credit: MediaPerson) {
            self.id = id
            self.name = name
            let role = GusSiriVideoRole.allCases.first { $0.rawValue.lowercased() == credit.creditType?.replacingOccurrences(of: " ", with: "").lowercased() } ?? .other
            roles = [role]
            characterNames = role == .actor ? [credit.role].compactMap { $0?.trimmedNilIfEmpty } : []
        }

        struct Query: EntityQuery {
            @MainActor func entities(for identifiers: [String]) async throws -> [GusSiriVideoPerson] {
                let catalog = try await GusVideoCatalog(session: GusIntentRuntime.session())
                let session = catalog.session
                var people = [GusSiriVideoPerson]()
                for identifier in identifiers {
                    guard let encoded = GusIntentID.value(identifier, resource: "video-credit", provider: session.server.providerKind, scope: session.references.scope),
                          let data = Data(base64Encoded: encoded), let pair = try? JSONDecoder().decode([String].self, from: data), pair.count == 2,
                          let item = try await catalog.item(rawID: pair[0]), let person = catalog.credits(item).first(where: { $0.id == identifier }) else { continue }
                    people.append(person)
                }
                try catalog.validate()
                return people
            }
        }
    }

    @AppEnum(schema: .video.imageType)
    enum GusSiriVideoImageType: String {
        case standardPoster, widePoster, hero, headshot, logo
        static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
            .standardPoster: "Poster", .widePoster: "Wide Poster", .hero: "Hero Image", .headshot: "Headshot", .logo: "Logo",
        ]
    }

    /// The schema requires these relationship types. Gus has no public image URL or authoritative creator-channel identity to export.
    @AppEntity(schema: .video.image)
    struct GusSiriVideoImage {
        static let defaultQuery = Query()
        let id: String
        var url: URL
        var type: GusSiriVideoImageType
        var width: Int?
        var height: Int?
        var displayRepresentation: DisplayRepresentation {
            "Artwork"
        }

        struct Query: EntityQuery {
            func entities(for identifiers: [String]) async throws -> [GusSiriVideoImage] {
                []
            }
        }
    }

    @AppEntity(schema: .video.contentCreator)
    struct GusSiriVideoCreator {
        static let defaultQuery = Query()
        let id: String
        var name: String
        var channelName: String?
        var images: [GusSiriVideoImage]
        var displayRepresentation: DisplayRepresentation {
            .init(title: "\(name)")
        }

        struct Query: EntityQuery {
            func entities(for identifiers: [String]) async throws -> [GusSiriVideoCreator] {
                []
            }
        }
    }

    @AppEnum(schema: .video.videoContentType)
    enum GusSiriVideoForm: String {
        case shortForm, longForm, live
        static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.shortForm: "Short Form", .longForm: "Long Form", .live: "Live"]
    }

    @AppEntity(schema: .video.movie)
    struct GusSiriMovie: GusVideoProjection {
        static let defaultQuery = Query()
        static let types: [MediaItemType] = [.movie]
        let id: String
        var title: String
        var description: String?
        var genres: [String]
        var castAndCrew: [GusSiriVideoPerson]
        var images: [GusSiriVideoImage]
        var trailers: [URL]
        var releaseDate: Date?
        var duration: Duration?
        var displayRepresentation: DisplayRepresentation {
            .init(title: "\(title)")
        }

        struct Query: EntityQuery, IntentValueQuery {
            @MainActor func entities(for identifiers: [String]) async throws -> [GusSiriMovie] {
                try await videoEntities(GusSiriMovie.self, ids: identifiers)
            }

            @MainActor func values(for search: MediaIntents.VideoSearch) async throws -> [GusSiriMovie] {
                try await videoEntities(GusSiriMovie.self, search: search)
            }
        }

        @MainActor fileprivate static func project(_ item: MediaItem, id: String, in catalog: GusVideoCatalog) async throws -> Self? {
            return Self(id: id, item: item, catalog: catalog)
        }

        @MainActor fileprivate init(id: String, item: MediaItem, catalog: GusVideoCatalog) {
            self.id = id
            title = item.displayTitle
            description = item.overview
            genres = item.genres
            castAndCrew = catalog.credits(item)
            images = []
            trailers = []
            releaseDate = item.premiereDate
            duration = videoDuration(item)
        }
    }

    @AppEntity(schema: .video.tvShow)
    struct GusSiriShow: GusVideoProjection {
        static let defaultQuery = Query()
        static let types: [MediaItemType] = [.series]
        let id: String
        var title: String
        var description: String?
        var genres: [String]
        var premiereDate: Date?
        var finaleDate: Date?
        var castAndCrew: [GusSiriVideoPerson]
        var images: [GusSiriVideoImage]
        var trailers: [URL]
        var seasonCount: Int?
        var displayRepresentation: DisplayRepresentation {
            .init(title: "\(title)")
        }

        struct Query: EntityQuery, IntentValueQuery {
            @MainActor func entities(for identifiers: [String]) async throws -> [GusSiriShow] {
                try await videoEntities(GusSiriShow.self, ids: identifiers)
            }

            @MainActor func values(for search: MediaIntents.VideoSearch) async throws -> [GusSiriShow] {
                try await videoEntities(GusSiriShow.self, search: search)
            }
        }

        @MainActor fileprivate static func project(_ item: MediaItem, id: String, in catalog: GusVideoCatalog) async throws -> Self? {
            return Self(id: id, item: item, catalog: catalog)
        }

        @MainActor fileprivate init(id: String, item: MediaItem, catalog: GusVideoCatalog) {
            self.id = id
            title = item.displayTitle
            description = item.overview
            genres = item.genres
            premiereDate = item.premiereDate
            castAndCrew = catalog.credits(item)
            images = []
            trailers = []
        }
    }

    @AppEntity(schema: .video.tvSeason)
    struct GusSiriSeason: GusVideoProjection {
        static let defaultQuery = Query()
        static let types: [MediaItemType] = [.season]
        let id: String
        var title: String
        var description: String?
        var premiereDate: Date?
        var castAndCrew: [GusSiriVideoPerson]
        var images: [GusSiriVideoImage]
        var trailers: [URL]
        var seasonNumber: String?
        var tvShow: GusSiriShow
        var displayRepresentation: DisplayRepresentation {
            .init(title: "\(title)")
        }

        struct Query: EntityQuery, IntentValueQuery {
            @MainActor func entities(for identifiers: [String]) async throws -> [GusSiriSeason] {
                try await videoEntities(GusSiriSeason.self, ids: identifiers)
            }

            @MainActor func values(for search: MediaIntents.VideoSearch) async throws -> [GusSiriSeason] {
                try await videoEntities(GusSiriSeason.self, search: search)
            }
        }

        @MainActor fileprivate static func project(_ item: MediaItem, id: String, in catalog: GusVideoCatalog) async throws -> Self? {
            guard let show = try await catalog.show(for: item) else { return nil }
            return Self(id: id, item: item, catalog: catalog, show: show)
        }

        @MainActor fileprivate init(id: String, item: MediaItem, catalog: GusVideoCatalog, show: GusSiriShow) {
            self.id = id
            title = item.displayTitle
            description = item.overview
            premiereDate = item.premiereDate
            castAndCrew = catalog.credits(item)
            images = []
            trailers = []
            seasonNumber = item.indexNumber.map(String.init)
            tvShow = show
        }
    }

    @AppEntity(schema: .video.tvEpisode)
    struct GusSiriEpisode: GusVideoProjection {
        static let defaultQuery = Query()
        static let types: [MediaItemType] = [.episode]
        let id: String
        var title: String
        var description: String?
        var premiereDate: Date?
        var castAndCrew: [GusSiriVideoPerson]
        var images: [GusSiriVideoImage]
        var trailers: [URL]
        var seasonNumber: String?
        var episodeNumber: String?
        var tvSeason: GusSiriSeason?
        var tvShow: GusSiriShow
        var duration: Duration?
        var displayRepresentation: DisplayRepresentation {
            .init(title: "\(title)")
        }

        struct Query: EntityQuery, IntentValueQuery {
            @MainActor func entities(for identifiers: [String]) async throws -> [GusSiriEpisode] {
                try await videoEntities(GusSiriEpisode.self, ids: identifiers)
            }

            @MainActor func values(for search: MediaIntents.VideoSearch) async throws -> [GusSiriEpisode] {
                try await videoEntities(GusSiriEpisode.self, search: search)
            }
        }

        @MainActor fileprivate static func project(_ item: MediaItem, id: String, in catalog: GusVideoCatalog) async throws -> Self? {
            guard let show = try await catalog.show(for: item) else { return nil }
            var season: GusSiriSeason?
            if let seasonID = item.parentID {
                guard let parent = try await catalog.item(rawID: seasonID), parent.type == .season,
                      parent.seriesID == item.seriesID, let identifier = catalog.identifier(parent) else { return nil }
                season = GusSiriSeason(id: identifier, item: parent, catalog: catalog, show: show)
            }
            return Self(id: id, item: item, catalog: catalog, show: show, season: season)
        }

        @MainActor fileprivate init(id: String, item: MediaItem, catalog: GusVideoCatalog, show: GusSiriShow, season: GusSiriSeason?) {
            self.id = id
            title = item.displayTitle
            description = item.overview
            premiereDate = item.premiereDate
            castAndCrew = catalog.credits(item)
            images = []
            trailers = []
            seasonNumber = item.parentIndexNumber.map(String.init)
            episodeNumber = item.indexNumber.map(String.init)
            tvSeason = season
            tvShow = show
            duration = videoDuration(item)
        }
    }

    @AppEntity(schema: .video.freeformVideo)
    struct GusSiriFreeform: GusVideoProjection {
        static let defaultQuery = Query()
        static let types: [MediaItemType] = [.trailer, .liveChannel]
        let id: String
        var title: String
        var creator: GusSiriVideoCreator?
        var images: [GusSiriVideoImage]
        var url: URL?
        var collaborators: [GusSiriVideoCreator]
        var tags: [String]
        var description: String?
        var contentType: GusSiriVideoForm
        var viewCount: Int?
        var releaseDate: Date?
        var duration: Duration?
        var isExplicitContent: Bool
        var displayRepresentation: DisplayRepresentation {
            .init(title: "\(title)")
        }

        struct Query: EntityQuery, IntentValueQuery {
            @MainActor func entities(for identifiers: [String]) async throws -> [GusSiriFreeform] {
                try await videoEntities(GusSiriFreeform.self, ids: identifiers)
            }

            @MainActor func values(for search: MediaIntents.VideoSearch) async throws -> [GusSiriFreeform] {
                try await videoEntities(GusSiriFreeform.self, search: search)
            }
        }

        @MainActor fileprivate static func project(_ item: MediaItem, id: String, in catalog: GusVideoCatalog) async throws -> Self? {
            guard let classification = classification(item) else { return nil }
            if item.type == .liveChannel, try await !catalog.canUseLiveTV() {
                return nil
            }
            return Self(id: id, item: item, classification: classification)
        }

        /// Jellyfin trailers identify short form and channels identify live content. Unclassified videos
        /// and unknown explicit-content ratings stay available through the ordinary Gus library actions.
        fileprivate static func classification(_ item: MediaItem) -> (GusSiriVideoForm, Bool)? {
            let form: GusSiriVideoForm
            switch item.type {
            case .trailer: form = .shortForm
            case .liveChannel: form = .live
            default: return nil
            }
            if item.tags.contains(where: { $0.caseInsensitiveCompare("Explicit") == .orderedSame }) {
                return (form, true)
            }
            if let rank = ContentRatingGate.rank(for: item.officialRating), rank <= 1 {
                return (form, false)
            }
            if ["XXX", "X"].contains(item.officialRating?.uppercased() ?? "") {
                return (form, true)
            }
            return nil
        }

        @MainActor fileprivate init(id: String, item: MediaItem, classification: (GusSiriVideoForm, Bool)) {
            self.id = id
            title = item.displayTitle
            images = []
            collaborators = []
            tags = item.tags
            description = item.overview
            contentType = classification.0
            releaseDate = item.premiereDate
            duration = videoDuration(item)
            isExplicitContent = classification.1
        }
    }

    @UnionValue
    enum GusSiriVideoContent {
        case movie(GusSiriMovie)
        case tvShow(GusSiriShow)
        case tvSeason(GusSiriSeason)
        case tvEpisode(GusSiriEpisode)
        case freeformVideo(GusSiriFreeform)
    }

    @AppIntent(schema: .video.playContent)
    struct GusPlaySystemVideo {
        static let supportedModes: IntentModes = .foreground
        static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
        var content: GusSiriVideoContent

        @MainActor func perform() async throws -> some IntentResult {
            let catalog = try await GusVideoCatalog(session: GusIntentRuntime.session())
            let selection: (String, [MediaItemType]) = switch content {
            case let .movie(movie): (movie.id, GusSiriMovie.types)
            case let .tvShow(show): (show.id, GusSiriShow.types)
            case let .tvSeason(season): (season.id, GusSiriSeason.types)
            case let .tvEpisode(episode): (episode.id, GusSiriEpisode.types)
            case let .freeformVideo(video): (video.id, GusSiriFreeform.types)
            }
            try await catalog.play(selection.0, types: selection.1)
            return .result()
        }
    }
#endif
