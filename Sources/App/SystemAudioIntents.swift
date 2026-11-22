#if canImport(MediaIntents) && (os(iOS) || os(macOS) || os(visionOS))
    import AppIntents
    import MediaIntents

    @available(iOS 27, macOS 27, visionOS 27, *)
    @AppEntity(schema: .audio.song)
    struct GusSystemSong {
        static let defaultQuery = GusSongQuery()
        let id: String
        var title: String
        var artistName: String
        var albumTitle: String?
        var album: GusSystemAlbum?
        var artists: [GusSystemArtist]
        var composers: [GusSystemArtist]
        var composerName: String?
        var internationalStandardRecordingCode: String?
        init(id: String, item: MediaItem, scope: AccountScope) {
            self.id = id
            title = item.displayTitle
            artistName = item.artists.first ?? item.albumArtist ?? ""
            albumTitle = item.album
            artists = GusSystemArtist.credits(item, scope: scope)
            composers = []
            composerName = item.people.first { $0.creditType?.lowercased() == "composer" }?.name
            if let albumID = item.albumID, let name = item.album {
                album = GusSystemAlbum(id: GusIntentID.make(resource: "media", id: albumID, provider: item.providerKind, scope: scope), title: name, artist: item.albumArtist ?? "", credits: GusSystemArtist.credits(item, scope: scope))
            }
        }

        var displayRepresentation: DisplayRepresentation {
            .init(title: "\(title)", subtitle: "\(artistName)")
        }
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    @AppEntity(schema: .audio.album)
    struct GusSystemAlbum {
        static let defaultQuery = GusAlbumQuery()
        let id: String
        var title: String
        var artistName: String
        var artists: [GusSystemArtist]
        var universalProductCode: String?

        init(id: String, title: String, artist: String, credits: [GusSystemArtist]) {
            self.id = id
            self.title = title
            artistName = artist
            artists = credits
        }

        var displayRepresentation: DisplayRepresentation {
            .init(title: "\(title)", subtitle: "\(artistName)")
        }
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    @AppEntity(schema: .audio.audiobook)
    struct GusSystemAudiobook {
        static let defaultQuery = GusAudiobookQuery()
        let id: String
        var title: String?
        var author: String?
        var genre: String?
        var narrator: String?
        var seriesTitle: String?
        var releaseDate: Date?
        var purchaseDate: Date?
        var publisher: String?
        init(id: String, item: MediaItem) {
            self.id = id
            title = item.displayTitle
            author = item.bookAuthorText
            genre = item.genres.first
            narrator = item.bookNarratorNames.first
            seriesTitle = item.seriesName
            releaseDate = item.premiereDate
            publisher = item.studios.first?.name
        }

        var displayRepresentation: DisplayRepresentation {
            .init(title: "\(title ?? "")", subtitle: "\(author ?? "")")
        }
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    @AppEntity(schema: .audio.artist)
    struct GusSystemArtist {
        static let defaultQuery = GusArtistQuery()
        let id: String
        var name: String
        var displayRepresentation: DisplayRepresentation {
            .init(title: "\(name)")
        }

        init(identifier: String, name: String) {
            id = identifier
            self.name = name
        }

        static func credits(_ item: MediaItem, scope: AccountScope) -> [Self] {
            (item.artistCredits ?? []).compactMap { credit in
                guard let id = credit.id, !id.isEmpty, let name = credit.name else { return nil }
                return Self(identifier: GusIntentID.make(resource: "media", id: id, provider: item.providerKind, scope: scope), name: name)
            }
        }
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    struct GusArtistQuery: EntityQuery {
        @MainActor func entities(for identifiers: [String]) async throws -> [GusSystemArtist] {
            let session = try await GusIntentRuntime.session()
            return try await SystemAudioLibrary.items(identifiers, type: .musicArtist, session: session).compactMap { item in
                guard let entity = GusIntentRuntime.entity(item, in: session) else { return nil }
                return GusSystemArtist(identifier: entity.id, name: entity.title)
            }
        }
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    @UnionValue
    enum GusSystemAudio {
        case song(GusSystemSong)
        case album(GusSystemAlbum)
        case audiobook(GusSystemAudiobook)
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    @MainActor
    private enum SystemAudioLibrary {
        static func items(_ identifiers: [String], type: MediaItemType, session: SessionStore) async throws -> [MediaItem] {
            var results: [MediaItem] = []
            for identifier in identifiers {
                guard let id = GusIntentID.value(identifier, resource: "media", provider: session.server.providerKind, scope: session.references.scope) else { continue }
                do {
                    let item = try await GusIntentRuntime.playbackItem(id: id, in: session)
                    try GusIntentRuntime.validate(session)
                    if item.id == id, item.type == type, item.providerKind == session.server.providerKind, ContentRatingGate.admitsStored(item) {
                        results.append(item)
                    }
                } catch where GusError(from: error) == .notFound { continue }
            }
            return results
        }

        static func find(_ search: AudioSearch, type: MediaItemType, session: SessionStore) async throws -> [MediaItem] {
            switch search.criteria {
            case let .searchQuery(text):
                return try await GusIntentRuntime.search(text, in: session, types: [type], includeOffline: true).items
            case let .url(urls):
                let identifiers = urls.prefix(25).compactMap { url -> String? in
                    guard let link = ContentLink(url: url), link.serverID == session.server.id, link.provider == session.server.providerKind else { return nil }
                    return GusIntentID.make(resource: "media", id: link.itemID, provider: session.server.providerKind, scope: session.references.scope)
                }
                return try await items(identifiers, type: type, session: session)
            case .unspecified:
                guard session.systemSurfacePreferences.personalHistoryEnabled else { return [] }
                var query = MediaItemQuery(includeTypes: [type], startIndex: 0, limit: 20, isRecursive: true)
                query.mostRecentlyPlayedFirst = true
                let page = try await session.mediaProvider.items(query: query)
                try GusIntentRuntime.validate(session)
                guard session.systemSurfacePreferences.personalHistoryEnabled else { return [] }
                return page.items.filter { $0.userData?.lastPlayedAt != nil && $0.type == type && ContentRatingGate.admitsStored($0) }
            @unknown default: return []
            }
        }
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    struct GusSongQuery: EntityQuery, IntentValueQuery {
        @MainActor private func song(_ item: MediaItem, session: SessionStore) -> GusSystemSong? {
            guard item.type == .audio, let media = GusIntentRuntime.entity(item, in: session) else { return nil }
            return GusSystemSong(id: media.id, item: item, scope: session.references.scope)
        }

        @MainActor func entities(for identifiers: [String]) async throws -> [GusSystemSong] {
            let session = try await GusIntentRuntime.session()
            return try await SystemAudioLibrary.items(identifiers, type: .audio, session: session).compactMap { song($0, session: session) }
        }

        @MainActor func values(for search: AudioSearch) async throws -> [GusSystemSong] {
            let session = try await GusIntentRuntime.session()
            return try await SystemAudioLibrary.find(search, type: .audio, session: session).compactMap { song($0, session: session) }
        }
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    struct GusAlbumQuery: EntityQuery, IntentValueQuery {
        @MainActor private func album(_ item: MediaItem, session: SessionStore) -> GusSystemAlbum? {
            guard item.type == .musicAlbum, let media = GusIntentRuntime.entity(item, in: session) else { return nil }
            return GusSystemAlbum(id: media.id, title: item.displayTitle, artist: item.albumArtist ?? media.artist ?? "", credits: GusSystemArtist.credits(item, scope: session.references.scope))
        }

        @MainActor func entities(for identifiers: [String]) async throws -> [GusSystemAlbum] {
            let session = try await GusIntentRuntime.session()
            return try await SystemAudioLibrary.items(identifiers, type: .musicAlbum, session: session).compactMap { album($0, session: session) }
        }

        @MainActor func values(for search: AudioSearch) async throws -> [GusSystemAlbum] {
            let session = try await GusIntentRuntime.session()
            return try await SystemAudioLibrary.find(search, type: .musicAlbum, session: session).compactMap { album($0, session: session) }
        }
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    struct GusAudiobookQuery: EntityQuery, IntentValueQuery {
        @MainActor private func book(_ item: MediaItem, session: SessionStore) -> GusSystemAudiobook? {
            guard item.type == .audioBook, let media = GusIntentRuntime.entity(item, in: session) else { return nil }
            return GusSystemAudiobook(id: media.id, item: item)
        }

        @MainActor func entities(for identifiers: [String]) async throws -> [GusSystemAudiobook] {
            let session = try await GusIntentRuntime.session()
            return try await SystemAudioLibrary.items(identifiers, type: .audioBook, session: session).compactMap { book($0, session: session) }
        }

        @MainActor func values(for search: AudioSearch) async throws -> [GusSystemAudiobook] {
            let session = try await GusIntentRuntime.session()
            return try await SystemAudioLibrary.find(search, type: .audioBook, session: session).compactMap { book($0, session: session) }
        }
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    @AppEnum(schema: .audio.playbackAttributes)
    enum GusAudioPlaybackAttribute: String {
        case shuffle, `repeat`
        static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.shuffle: "Shuffle", .repeat: "Repeat"]
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    @AppEnum(schema: .audio.queueInsertionLocation)
    enum GusAudioQueueLocation: String {
        case next, tail
        static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.next: "Play Next", .tail: "Play Last"]
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    @AppEntity(schema: .audio.warmupAudioQueueResult)
    struct GusAudioWarmupResult: TransientAppEntity {
        var displayRepresentation: DisplayRepresentation {
            "Prepared Audio"
        }
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    @AppIntent(schema: .audio.playAudio)
    struct GusPlaySystemAudioIntent {
        var audioEntity: GusSystemAudio
        var playbackAttributes: Set<GusAudioPlaybackAttribute>
        var queueLocation: GusAudioQueueLocation?
        var warmupAudioQueueResult: GusAudioWarmupResult?

        #if !os(iOS)
            static let supportedModes: IntentModes = .foreground
        #endif

        @MainActor func perform() async throws -> some IntentResult {
            let session = try await GusIntentRuntime.session()
            let selection: (String, MediaItemType) = switch audioEntity {
            case let .song(value): (value.id, .audio)
            case let .album(value): (value.id, .musicAlbum)
            case let .audiobook(value): (value.id, .audioBook)
            }
            guard let item = try await SystemAudioLibrary.items([selection.0], type: selection.1, session: session).first else { throw GusError.notFound }
            #if os(iOS)
                if let queueLocation {
                    guard let player = AppModel.shared.audioPlayback.store, playbackAttributes.isEmpty else {
                        throw GusError.server(String(localized: "Start an audio queue in Gus before adding more tracks."))
                    }
                    try await player.enqueueSystemAudio(item, playNext: queueLocation == .next, in: session)
                    return .result()
                }
                guard await SiriMediaHandler.startAudio(item, session: session, shuffle: playbackAttributes.contains(.shuffle), repeating: playbackAttributes.contains(.repeat)) else {
                    throw GusError.server(String(localized: "Audio playback is unavailable."))
                }
            #else
                guard queueLocation == nil, playbackAttributes.isEmpty else {
                    throw GusError.server(String(localized: "Choose the playback order in the Gus player on this device."))
                }
                try GusIntentRuntime.open(item, in: session, play: true)
            #endif
            return .result()
        }
    }
#endif
