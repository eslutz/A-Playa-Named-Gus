import Foundation

enum MediaItemType: String, Codable, Hashable {
    case movie
    case episode
    case series
    case season
    case collectionFolder
    case folder
    case trailer
    case video
    case audio
    case musicArtist
    case musicAlbum
    case playlist
    case book
    case audioBook
    case photo
    case liveChannel
    case liveProgram
    case recording
    case unknown
}

enum MediaCollectionType: String, Codable, Hashable {
    case movies
    case tvshows
    case music
    case books
    case photos
    case livetv
    case unknown
}

enum MediaImageKind: String, Codable, Hashable {
    case primary = "Primary"
    case backdrop = "Backdrop"
}

enum MediaStreamKind: String, Codable, Hashable {
    case audio
    case subtitle
    case video
    case unknown
}

enum MediaVideoType: String, Codable, Hashable {
    case videoFile
    case unknown
}

enum Media3DFormat: String, Codable, Hashable {
    case halfSideBySide
    case fullSideBySide
    case halfTopAndBottom
    case fullTopAndBottom
    case mvc
}

enum MediaItemSort: String, Codable, Hashable {
    case name
    case recentlyAdded
    case releaseDate
    case rating
    case random
    /// Disc then track order — for songs inside an album.
    case trackOrder
}

enum MediaItemStatusFilter: String, Codable, Hashable {
    case all
    case unplayed
    case played
    case resumable
}

enum MediaPlaybackMethod: String, Codable, Hashable {
    case directPlay
    case directStream
    case transcode
}

struct MediaUserData: Codable, Hashable {
    var playbackPositionTicks: Int?
    var playedPercentage: Double?

    private enum CodingKeys: String, CodingKey {
        case playbackPositionTicks
        case playedPercentage
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playedPercentage = "PlayedPercentage"
    }

    init(playbackPositionTicks: Int? = nil, playedPercentage: Double? = nil) {
        self.playbackPositionTicks = playbackPositionTicks
        self.playedPercentage = playedPercentage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        playbackPositionTicks = try container.decodeIfPresent(Int.self, forKey: .playbackPositionTicks)
            ?? legacyContainer.decodeIfPresent(Int.self, forKey: .playbackPositionTicks)
        playedPercentage = try container.decodeIfPresent(Double.self, forKey: .playedPercentage)
            ?? legacyContainer.decodeIfPresent(Double.self, forKey: .playedPercentage)
    }
}

struct MediaStudio: Codable, Hashable, Identifiable {
    var id: String?
    var name: String?

    init(id: String? = nil, name: String? = nil) {
        self.id = id
        self.name = name
    }
}

struct MediaPerson: Codable, Hashable, Identifiable {
    var id: String?
    var name: String?
    var primaryImageTag: String?
    var role: String?

    init(id: String? = nil, name: String? = nil, primaryImageTag: String? = nil, role: String? = nil) {
        self.id = id
        self.name = name
        self.primaryImageTag = primaryImageTag
        self.role = role
    }
}

struct MediaStreamInfo: Codable, Hashable {
    var codecTag: String?
    var codec: String?
    var displayTitle: String?
    var index: Int?
    var isDefault: Bool?
    var language: String?
    var profile: String?
    var title: String?
    var type: MediaStreamKind?

    init(
        codec: String? = nil,
        codecTag: String? = nil,
        displayTitle: String? = nil,
        index: Int? = nil,
        isDefault: Bool? = nil,
        language: String? = nil,
        profile: String? = nil,
        title: String? = nil,
        type: MediaStreamKind? = nil
    ) {
        self.codecTag = codecTag
        self.codec = codec
        self.displayTitle = displayTitle
        self.index = index
        self.isDefault = isDefault
        self.language = language
        self.profile = profile
        self.title = title
        self.type = type
    }
}

struct MediaSource: Codable, Hashable, Identifiable {
    var container: String?
    var id: String?
    var mediaStreams: [MediaStreamInfo]
    var supportsDirectPlay: Bool?
    var transcodingURL: String?
    var video3DFormat: Media3DFormat?
    var videoType: MediaVideoType?

    init(
        container: String? = nil,
        id: String? = nil,
        mediaStreams: [MediaStreamInfo] = [],
        supportsDirectPlay: Bool? = nil,
        transcodingURL: String? = nil,
        video3DFormat: Media3DFormat? = nil,
        videoType: MediaVideoType? = nil
    ) {
        self.container = container
        self.id = id
        self.mediaStreams = mediaStreams
        self.supportsDirectPlay = supportsDirectPlay
        self.transcodingURL = transcodingURL
        self.video3DFormat = video3DFormat
        self.videoType = videoType
    }
}

struct MediaChapterInfo: Codable, Hashable {
    var name: String?
    var startPositionTicks: Int?

    init(name: String? = nil, startPositionTicks: Int? = nil) {
        self.name = name
        self.startPositionTicks = startPositionTicks
    }
}

struct MediaItem: Codable, Hashable, Identifiable {
    var providerKind: MediaProviderKind
    var album: String?
    var albumArtist: String?
    var artists: [String]
    var backdropImageTags: [String]
    var canDownload: Bool?
    var chapters: [MediaChapterInfo]
    var collectionType: MediaCollectionType?
    var communityRating: Double?
    var container: String?
    var criticRating: Double?
    /// Live TV: the program currently airing on this channel.
    var currentProgramName: String?
    var genres: [String]
    var id: String?
    var imageTags: [String: String]
    var indexNumber: Int?
    var mediaSources: [MediaSource]
    var name: String?
    var officialRating: String?
    var overview: String?
    var parentBackdropImageTags: [String]
    var parentID: String?
    var parentIndexNumber: Int?
    var people: [MediaPerson]
    var primaryImageAspectRatio: Double?
    var productionYear: Int?
    var runTimeTicks: Int?
    var seriesID: String?
    var seriesName: String?
    var seriesPrimaryImageTag: String?
    var studios: [MediaStudio]
    var taglines: [String]
    var type: MediaItemType?
    var userData: MediaUserData?
    var video3DFormat: Media3DFormat?

    private enum CodingKeys: String, CodingKey {
        case providerKind
        case album
        case albumArtist
        case artists
        case backdropImageTags
        case canDownload
        case chapters
        case collectionType
        case communityRating
        case container
        case criticRating
        case currentProgramName
        case genres
        case id
        case imageTags
        case indexNumber
        case mediaSources
        case name
        case officialRating
        case overview
        case parentBackdropImageTags
        case parentID
        case parentIndexNumber
        case people
        case primaryImageAspectRatio
        case productionYear
        case runTimeTicks
        case seriesID
        case seriesName
        case seriesPrimaryImageTag
        case studios
        case taglines
        case type
        case userData
        case video3DFormat
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case album = "Album"
        case albumArtist = "AlbumArtist"
        case artists = "Artists"
        case backdropImageTags = "BackdropImageTags"
        case canDownload = "CanDownload"
        case collectionType = "CollectionType"
        case communityRating = "CommunityRating"
        case container = "Container"
        case criticRating = "CriticRating"
        case genres = "Genres"
        case id = "Id"
        case imageTags = "ImageTags"
        case indexNumber = "IndexNumber"
        case name = "Name"
        case officialRating = "OfficialRating"
        case overview = "Overview"
        case parentBackdropImageTags = "ParentBackdropImageTags"
        case parentID = "ParentId"
        case parentIndexNumber = "ParentIndexNumber"
        case primaryImageAspectRatio = "PrimaryImageAspectRatio"
        case productionYear = "ProductionYear"
        case runTimeTicks = "RunTimeTicks"
        case seriesID = "SeriesId"
        case seriesName = "SeriesName"
        case seriesPrimaryImageTag = "SeriesPrimaryImageTag"
        case taglines = "Taglines"
        case type = "Type"
        case userData = "UserData"
        case video3DFormat = "Video3DFormat"
    }

    init(
        providerKind: MediaProviderKind = .jellyfin,
        album: String? = nil,
        albumArtist: String? = nil,
        artists: [String] = [],
        backdropImageTags: [String] = [],
        canDownload: Bool? = nil,
        chapters: [MediaChapterInfo] = [],
        collectionType: MediaCollectionType? = nil,
        communityRating: Double? = nil,
        container: String? = nil,
        criticRating: Double? = nil,
        currentProgramName: String? = nil,
        genres: [String] = [],
        id: String? = nil,
        imageTags: [String: String] = [:],
        indexNumber: Int? = nil,
        mediaSources: [MediaSource] = [],
        name: String? = nil,
        officialRating: String? = nil,
        overview: String? = nil,
        parentBackdropImageTags: [String] = [],
        parentID: String? = nil,
        parentIndexNumber: Int? = nil,
        people: [MediaPerson] = [],
        primaryImageAspectRatio: Double? = nil,
        productionYear: Int? = nil,
        runTimeTicks: Int? = nil,
        seriesID: String? = nil,
        seriesName: String? = nil,
        seriesPrimaryImageTag: String? = nil,
        studios: [MediaStudio] = [],
        taglines: [String] = [],
        type: MediaItemType? = nil,
        userData: MediaUserData? = nil,
        video3DFormat: Media3DFormat? = nil
    ) {
        self.providerKind = providerKind
        self.album = album
        self.albumArtist = albumArtist
        self.artists = artists
        self.backdropImageTags = backdropImageTags
        self.canDownload = canDownload
        self.chapters = chapters
        self.collectionType = collectionType
        self.communityRating = communityRating
        self.container = container
        self.criticRating = criticRating
        self.currentProgramName = currentProgramName
        self.genres = genres
        self.id = id
        self.imageTags = imageTags
        self.indexNumber = indexNumber
        self.mediaSources = mediaSources
        self.name = name
        self.officialRating = officialRating
        self.overview = overview
        self.parentBackdropImageTags = parentBackdropImageTags
        self.parentID = parentID
        self.parentIndexNumber = parentIndexNumber
        self.people = people
        self.primaryImageAspectRatio = primaryImageAspectRatio
        self.productionYear = productionYear
        self.runTimeTicks = runTimeTicks
        self.seriesID = seriesID
        self.seriesName = seriesName
        self.seriesPrimaryImageTag = seriesPrimaryImageTag
        self.studios = studios
        self.taglines = taglines
        self.type = type
        self.userData = userData
        self.video3DFormat = video3DFormat
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacyValues = try decoder.container(keyedBy: LegacyCodingKeys.self)

        providerKind = try values.decodeIfPresent(MediaProviderKind.self, forKey: .providerKind) ?? .jellyfin
        album = try values.decodeIfPresent(String.self, forKey: .album)
            ?? legacyValues.decodeIfPresent(String.self, forKey: .album)
        albumArtist = try values.decodeIfPresent(String.self, forKey: .albumArtist)
            ?? legacyValues.decodeIfPresent(String.self, forKey: .albumArtist)
        artists = try values.decodeIfPresent([String].self, forKey: .artists)
            ?? legacyValues.decodeIfPresent([String].self, forKey: .artists) ?? []
        backdropImageTags = try values.decodeIfPresent([String].self, forKey: .backdropImageTags)
            ?? legacyValues.decodeIfPresent([String].self, forKey: .backdropImageTags) ?? []
        canDownload = try values.decodeIfPresent(Bool.self, forKey: .canDownload)
            ?? legacyValues.decodeIfPresent(Bool.self, forKey: .canDownload)
        chapters = try values.decodeIfPresent([MediaChapterInfo].self, forKey: .chapters) ?? []
        collectionType = try values.decodeIfPresent(MediaCollectionType.self, forKey: .collectionType)
            ?? Self.decodeLegacyCollectionType(from: legacyValues)
        communityRating = try values.decodeIfPresent(Double.self, forKey: .communityRating)
            ?? legacyValues.decodeIfPresent(Double.self, forKey: .communityRating)
        container = try values.decodeIfPresent(String.self, forKey: .container)
            ?? legacyValues.decodeIfPresent(String.self, forKey: .container)
        criticRating = try values.decodeIfPresent(Double.self, forKey: .criticRating)
            ?? legacyValues.decodeIfPresent(Double.self, forKey: .criticRating)
        currentProgramName = try values.decodeIfPresent(String.self, forKey: .currentProgramName)
        genres = try values.decodeIfPresent([String].self, forKey: .genres)
            ?? legacyValues.decodeIfPresent([String].self, forKey: .genres) ?? []
        id = try values.decodeIfPresent(String.self, forKey: .id)
            ?? legacyValues.decodeIfPresent(String.self, forKey: .id)
        imageTags = try values.decodeIfPresent([String: String].self, forKey: .imageTags)
            ?? legacyValues.decodeIfPresent([String: String].self, forKey: .imageTags) ?? [:]
        indexNumber = try values.decodeIfPresent(Int.self, forKey: .indexNumber)
            ?? legacyValues.decodeIfPresent(Int.self, forKey: .indexNumber)
        mediaSources = try values.decodeIfPresent([MediaSource].self, forKey: .mediaSources) ?? []
        name = try values.decodeIfPresent(String.self, forKey: .name)
            ?? legacyValues.decodeIfPresent(String.self, forKey: .name)
        officialRating = try values.decodeIfPresent(String.self, forKey: .officialRating)
            ?? legacyValues.decodeIfPresent(String.self, forKey: .officialRating)
        overview = try values.decodeIfPresent(String.self, forKey: .overview)
            ?? legacyValues.decodeIfPresent(String.self, forKey: .overview)
        parentBackdropImageTags = try values.decodeIfPresent([String].self, forKey: .parentBackdropImageTags)
            ?? legacyValues.decodeIfPresent([String].self, forKey: .parentBackdropImageTags) ?? []
        parentID = try values.decodeIfPresent(String.self, forKey: .parentID)
            ?? legacyValues.decodeIfPresent(String.self, forKey: .parentID)
        parentIndexNumber = try values.decodeIfPresent(Int.self, forKey: .parentIndexNumber)
            ?? legacyValues.decodeIfPresent(Int.self, forKey: .parentIndexNumber)
        people = try values.decodeIfPresent([MediaPerson].self, forKey: .people) ?? []
        primaryImageAspectRatio = try values.decodeIfPresent(Double.self, forKey: .primaryImageAspectRatio)
            ?? legacyValues.decodeIfPresent(Double.self, forKey: .primaryImageAspectRatio)
        productionYear = try values.decodeIfPresent(Int.self, forKey: .productionYear)
            ?? legacyValues.decodeIfPresent(Int.self, forKey: .productionYear)
        runTimeTicks = try values.decodeIfPresent(Int.self, forKey: .runTimeTicks)
            ?? legacyValues.decodeIfPresent(Int.self, forKey: .runTimeTicks)
        seriesID = try values.decodeIfPresent(String.self, forKey: .seriesID)
            ?? legacyValues.decodeIfPresent(String.self, forKey: .seriesID)
        seriesName = try values.decodeIfPresent(String.self, forKey: .seriesName)
            ?? legacyValues.decodeIfPresent(String.self, forKey: .seriesName)
        seriesPrimaryImageTag = try values.decodeIfPresent(String.self, forKey: .seriesPrimaryImageTag)
            ?? legacyValues.decodeIfPresent(String.self, forKey: .seriesPrimaryImageTag)
        studios = try values.decodeIfPresent([MediaStudio].self, forKey: .studios) ?? []
        taglines = try values.decodeIfPresent([String].self, forKey: .taglines)
            ?? legacyValues.decodeIfPresent([String].self, forKey: .taglines) ?? []
        type = try values.decodeIfPresent(MediaItemType.self, forKey: .type)
            ?? Self.decodeLegacyItemType(from: legacyValues)
        userData = try values.decodeIfPresent(MediaUserData.self, forKey: .userData)
            ?? legacyValues.decodeIfPresent(MediaUserData.self, forKey: .userData)
        video3DFormat = try values.decodeIfPresent(Media3DFormat.self, forKey: .video3DFormat)
            ?? Self.decodeLegacy3DFormat(from: legacyValues)
    }

    private static func decodeLegacyItemType(from container: KeyedDecodingContainer<LegacyCodingKeys>) -> MediaItemType? {
        guard let rawValue = try? container.decodeIfPresent(String.self, forKey: .type) else { return nil }
        switch rawValue.lowercased() {
        case "movie": return .movie
        case "episode": return .episode
        case "series": return .series
        case "season": return .season
        case "collectionfolder": return .collectionFolder
        case "folder": return .folder
        case "trailer": return .trailer
        case "video": return .video
        case "audio": return .audio
        case "musicartist": return .musicArtist
        case "musicalbum": return .musicAlbum
        case "playlist": return .playlist
        case "book": return .book
        case "audiobook": return .audioBook
        case "photo": return .photo
        case "tvchannel", "livetvchannel", "livechannel": return .liveChannel
        case "tvprogram", "livetvprogram", "liveprogram": return .liveProgram
        case "recording": return .recording
        default: return .unknown
        }
    }

    private static func decodeLegacyCollectionType(from container: KeyedDecodingContainer<LegacyCodingKeys>) -> MediaCollectionType? {
        guard let rawValue = try? container.decodeIfPresent(String.self, forKey: .collectionType) else { return nil }
        return MediaCollectionType(rawValue: rawValue.lowercased()) ?? .unknown
    }

    private static func decodeLegacy3DFormat(from container: KeyedDecodingContainer<LegacyCodingKeys>) -> Media3DFormat? {
        guard let rawValue = try? container.decodeIfPresent(String.self, forKey: .video3DFormat) else { return nil }
        switch rawValue.lowercased() {
        case "halfsidebyside": return .halfSideBySide
        case "fullsidebyside": return .fullSideBySide
        case "halftopandbottom": return .halfTopAndBottom
        case "fulltopandbottom": return .fullTopAndBottom
        case "mvc": return .mvc
        default: return nil
        }
    }
}

/// Feature gates a provider exposes to the UI. Only flags that gate real behavior
/// belong here — speculative capabilities accumulate as unread dead weight, and the
/// `true` defaults describe Jellyfin (a new provider must opt out explicitly).
struct ProviderCapabilities: Codable, Equatable {
    var supportsSearch = true
    var supportsDownloads = true
    /// Whether the server round-trips EPUB reading position (Jellyfin stores it on
    /// `UserData.PlaybackPositionTicks`; see `JellyfinBookProgress`).
    var supportsBookProgressSync = true

    init(
        supportsSearch: Bool = true,
        supportsDownloads: Bool = true,
        supportsBookProgressSync: Bool = true
    ) {
        self.supportsSearch = supportsSearch
        self.supportsDownloads = supportsDownloads
        self.supportsBookProgressSync = supportsBookProgressSync
    }
}

extension MediaItem {
    /// Items that play through the audio player rather than the video player.
    var isAudioPlayable: Bool {
        type == .audio || type == .audioBook
    }
}
