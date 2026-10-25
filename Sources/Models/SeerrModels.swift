import Foundation

/// Seerr's API uses TMDB identifiers, which must never be treated as Jellyfin item IDs.
enum SeerrMediaType: String, Codable, Hashable, Sendable {
    case movie, tv, person, collection, unknown

    init(from decoder: Decoder) throws {
        self = try Self(rawValue: decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

/// Source of truth: seerr-team/seerr server/lib/permissions.ts (v3.0.0–v3.5.1).
struct SeerrPermissions: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt64

    static let admin = Self(rawValue: 2)
    static let manageSettings = Self(rawValue: 4)
    static let manageUsers = Self(rawValue: 8)
    static let manageRequests = Self(rawValue: 16)
    static let request = Self(rawValue: 32)
    static let autoApprove = Self(rawValue: 128)
    static let autoApproveMovie = Self(rawValue: 256)
    static let autoApproveTV = Self(rawValue: 512)
    static let request4K = Self(rawValue: 1024)
    static let request4KMovie = Self(rawValue: 2048)
    static let request4KTV = Self(rawValue: 4096)
    static let requestAdvanced = Self(rawValue: 8192)
    static let requestView = Self(rawValue: 16384)
    static let autoApprove4K = Self(rawValue: 32768)
    static let autoApprove4KMovie = Self(rawValue: 65536)
    static let autoApprove4KTV = Self(rawValue: 131_072)
    static let requestMovie = Self(rawValue: 262_144)
    static let requestTV = Self(rawValue: 524_288)
    static let recentView = Self(rawValue: 67_108_864)
    static let manageBlocklist = Self(rawValue: 268_435_456)
    static let viewBlocklist = Self(rawValue: 1_073_741_824)

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt64.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    func permits(_ permission: Self) -> Bool {
        contains(.admin) || !intersection(permission).isEmpty
    }
}

struct SeerrUser: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    var username: String?
    var email: String?
    var displayName: String?
    var jellyfinUsername: String?
    var jellyfinUserId: String?
    var permissions: SeerrPermissions
    var avatar: String?
    var userType: Int?

    var name: String {
        displayName ?? username ?? jellyfinUsername ?? email ?? String(id)
    }

    var canManageRequests: Bool {
        permissions.permits(.manageRequests)
    }

    func canRequest(_ type: SeerrMediaType, is4K: Bool = false) -> Bool {
        guard type == .movie || type == .tv else { return false }
        if is4K {
            return permissions.permits([.request4K, type == .movie ? .request4KMovie : .request4KTV])
        }
        return permissions.permits([.request, type == .movie ? .requestMovie : .requestTV])
    }

    func automaticallyApproves(_ type: SeerrMediaType, is4K: Bool = false) -> Bool {
        guard type == .movie || type == .tv else { return false }
        return is4K
            ? permissions.permits([.autoApprove4K, type == .movie ? .autoApprove4KMovie : .autoApprove4KTV])
            : permissions.permits([.autoApprove, type == .movie ? .autoApproveMovie : .autoApproveTV])
    }
}

/// Unknown numeric states remain visible but cannot enable request or management actions.
enum SeerrMediaStatus: Hashable, Sendable, Codable {
    case notRequested, pending, processing, partiallyAvailable, available, blocklisted, deleted
    case unknown(Int)

    init(rawValue: Int) {
        switch rawValue {
        case 1: self = .notRequested
        case 2: self = .pending
        case 3: self = .processing
        case 4: self = .partiallyAvailable
        case 5: self = .available
        case 6: self = .blocklisted
        case 7: self = .deleted
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: Int {
        switch self {
        case .notRequested: 1
        case .pending: 2
        case .processing: 3
        case .partiallyAvailable: 4
        case .available: 5
        case .blocklisted: 6
        case .deleted: 7
        case let .unknown(value): value
        }
    }

    var isRequestable: Bool {
        self == .notRequested || self == .deleted
    }

    init(from decoder: Decoder) throws {
        try self.init(rawValue: decoder.singleValueContainer().decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum SeerrRequestStatus: Hashable, Sendable, Codable {
    case pending, approved, declined, failed, completed
    case unknown(Int)

    init(rawValue: Int) {
        switch rawValue {
        case 1: self = .pending
        case 2: self = .approved
        case 3: self = .declined
        case 4: self = .failed
        case 5: self = .completed
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: Int {
        switch self {
        case .pending: 1
        case .approved: 2
        case .declined: 3
        case .failed: 4
        case .completed: 5
        case let .unknown(value): value
        }
    }

    init(from decoder: Decoder) throws {
        try self.init(rawValue: decoder.singleValueContainer().decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct SeerrStatus: Codable, Hashable, Sendable {
    var version: String
    var commitTag: String?
    var restartRequired: Bool?

    /// Only stable, identifiable Seerr releases are supported; legacy Jellyseerr is not Seerr 3.
    var isSupported: Bool {
        let version = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let pieces = version.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(pieces[0]), Int(pieces[1]) != nil, Int(pieces[2]) != nil
        else { return false }
        return major == 3
    }
}

struct SeerrPublicSettings: Codable, Hashable, Sendable {
    var initialized: Bool
    var applicationTitle: String?
    var localLogin: Bool?
    var mediaServerLogin: Bool?
    var mediaServerType: Int?
    var movie4kEnabled: Bool?
    var series4kEnabled: Bool?
    var partialRequestsEnabled: Bool?
    var enableSpecialEpisodes: Bool?
    var hideAvailable: Bool?
    var hideRequested: Bool?
    var jellyfinServerName: String?
    var jellyfinExternalHost: String?

    var supportsJellyfinLogin: Bool {
        initialized && mediaServerLogin == true && mediaServerType == 2
    }

    var supportsLocalLogin: Bool {
        initialized && localLogin == true
    }

    func permits4K(_ type: SeerrMediaType) -> Bool {
        type == .movie ? movie4kEnabled == true : type == .tv && series4kEnabled == true
    }
}

struct SeerrServerInfo: Sendable {
    let status: SeerrStatus
    let settings: SeerrPublicSettings
}

struct SeerrPage: Codable, Hashable, Sendable {
    var page: Int
    var totalPages: Int
    var totalResults: Int
    var results: [SeerrTitle]
}

struct SeerrGenre: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
}

struct SeerrExternalIDs: Codable, Hashable, Sendable {
    var imdbId: String?
    var tvdbId: Int?
}

/// Shared movie, TV, person and collection result fields; detail responses use the same camel-case keys.
struct SeerrTitle: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var mediaType: SeerrMediaType?
    var title: String?
    var name: String?
    var overview: String?
    var posterPath: String?
    var backdropPath: String?
    var profilePath: String?
    var releaseDate: String?
    var firstAirDate: String?
    var voteAverage: Double?
    var runtime: Int?
    var episodeRunTime: [Int]?
    var tagline: String?
    var numberOfSeasons: Int?
    var genres: [SeerrGenre]?
    var credits: SeerrCredits?
    var seasons: [SeerrSeason]?
    var mediaInfo: SeerrMediaInfo?
    var externalIds: SeerrExternalIDs?
    var releases: SeerrMovieReleases?
    var contentRatings: SeerrContentRatings?
    var collection: SeerrCollection?
    var character: String?
    var job: String?

    var displayTitle: String {
        title ?? name ?? String(id)
    }

    var releaseYear: String? {
        guard let date = releaseDate ?? firstAirDate, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }

    /// Uses US certifications so the existing Jellyfin content-rating gate receives its supported scale.
    var certification: String? {
        if let rating = contentRatings?.results.first(where: { $0.countryCode == "US" })?.rating,
           !rating.isEmpty
        {
            return rating
        }
        let dates = releases?.results.first(where: { $0.countryCode == "US" })?.releaseDates ?? []
        return dates.first(where: { $0.type == 3 && !$0.certification.isEmpty })?.certification
            ?? dates.first(where: { !$0.certification.isEmpty })?.certification
    }

    func imageURL(width: String = "w500") -> URL? {
        SeerrArtwork.url(path: posterPath ?? profilePath, width: width)
    }
}

struct SeerrMovieReleases: Codable, Hashable, Sendable {
    var results: [SeerrMovieReleaseCountry]
}

struct SeerrMovieReleaseCountry: Codable, Hashable, Sendable {
    var countryCode: String
    var releaseDates: [SeerrMovieReleaseDate]
    enum CodingKeys: String, CodingKey {
        case countryCode = "iso_3166_1"
        case releaseDates = "release_dates"
    }
}

struct SeerrMovieReleaseDate: Codable, Hashable, Sendable {
    var certification: String
    var type: Int?
}

struct SeerrContentRatings: Codable, Hashable, Sendable {
    var results: [SeerrContentRating]
}

struct SeerrContentRating: Codable, Hashable, Sendable {
    var countryCode: String
    var rating: String
    enum CodingKeys: String, CodingKey {
        case countryCode = "iso_3166_1"
        case rating
    }
}

struct SeerrCollection: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String?
    var posterPath: String?
    var backdropPath: String?
    var parts: [SeerrTitle]?
}

struct SeerrCredit: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var character: String?
    var job: String?
    var profilePath: String?
    func imageURL(width: String = "w185") -> URL? {
        SeerrArtwork.url(path: profilePath, width: width)
    }
}

struct SeerrCredits: Codable, Hashable, Sendable {
    var cast: [SeerrCredit]
    var crew: [SeerrCredit]
}

struct SeerrPerson: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var biography: String?
    var profilePath: String?
    var birthday: String?
    var placeOfBirth: String?
    func imageURL(width: String = "w500") -> URL? {
        SeerrArtwork.url(path: profilePath, width: width)
    }
}

struct SeerrPersonCredits: Codable, Hashable, Sendable {
    var cast: [SeerrTitle]
    var crew: [SeerrTitle]
}

struct SeerrSeason: Codable, Identifiable, Hashable, Sendable {
    var id: Int?
    var seasonNumber: Int
    var name: String?
    var overview: String?
    var posterPath: String?
    var airDate: String?
    var episodeCount: Int?
    var episodes: [SeerrEpisode]?
}

struct SeerrEpisode: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var episodeNumber: Int
    var name: String?
    var overview: String?
    var stillPath: String?
    var airDate: String?
}

struct SeerrMediaSeason: Codable, Hashable, Sendable {
    var seasonNumber: Int
    var status: SeerrMediaStatus
    var status4k: SeerrMediaStatus?
}

struct SeerrMediaInfo: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var tmdbId: Int?
    var tvdbId: Int?
    var mediaType: SeerrMediaType?
    var status: SeerrMediaStatus
    var status4k: SeerrMediaStatus?
    var requests: [SeerrRequest]?
    var seasons: [SeerrMediaSeason]?
    var jellyfinMediaId: String?
    var jellyfinMediaId4k: String?

    func availability(is4K: Bool = false) -> SeerrMediaStatus {
        is4K ? status4k ?? .unknown(0) : status
    }
}

struct SeerrRequestSeason: Codable, Hashable, Sendable {
    var seasonNumber: Int
    var status: SeerrRequestStatus?
}

struct SeerrRequest: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var status: SeerrRequestStatus
    var type: SeerrMediaType?
    var media: SeerrMediaInfo?
    var requestedBy: SeerrUser?
    var modifiedBy: SeerrUser?
    var is4k: Bool?
    var createdAt: String?
    var updatedAt: String?
    var seasons: [SeerrRequestSeason]?
    var serverId: Int?
    var profileId: Int?
    var rootFolder: String?

    func canCancel(user: SeerrUser) -> Bool {
        if case .unknown = status {
            return false
        }
        return user.canManageRequests || (status == .pending && requestedBy?.id == user.id)
    }

    func canModerate(user: SeerrUser) -> Bool {
        user.canManageRequests && status == .pending
    }

    func canRetry(user: SeerrUser) -> Bool {
        user.canManageRequests && status == .failed
    }
}

struct SeerrPageInfo: Codable, Hashable, Sendable {
    var pages: Int
    var pageSize: Int
    var results: Int
    var page: Int
}

struct SeerrRequestPage: Codable, Hashable, Sendable {
    var pageInfo: SeerrPageInfo
    var results: [SeerrRequest]
}

struct SeerrQuota: Codable, Hashable, Sendable {
    var movie: SeerrQuotaStatus
    var tv: SeerrQuotaStatus
    func status(for type: SeerrMediaType) -> SeerrQuotaStatus {
        type == .movie ? movie : tv
    }
}

struct SeerrQuotaStatus: Codable, Hashable, Sendable {
    var days: Int?
    var limit: Int?
    var used: Int
    var remaining: Int?
    var restricted: Bool

    /// TV quota counts seasons, including specials only when explicitly selected.
    func allows(count: Int) -> Bool {
        guard count > 0, !restricted else { return false }
        guard let limit, limit > 0 else { return true }
        guard let remaining else { return false }
        return count <= remaining
    }
}

enum SeerrDiscoveryFeed: String, CaseIterable, Hashable, Sendable {
    case trending, popularMovies, popularTV, upcomingMovies, upcomingTV
    var path: String {
        switch self {
        case .trending: "discover/trending"
        case .popularMovies: "discover/movies"
        case .popularTV: "discover/tv"
        case .upcomingMovies: "discover/movies/upcoming"
        case .upcomingTV: "discover/tv/upcoming"
        }
    }
}

enum SeerrRequestFilter: String, CaseIterable, Hashable, Sendable {
    case all, approved, available, pending, processing, unavailable, failed, deleted, completed
}

/// Explicit season numbers keep request confirmations truthful, including when partial requests are disabled.
struct SeerrRequestPayload: Codable, Hashable, Sendable {
    var mediaType: SeerrMediaType
    var mediaId: Int
    var seasons: [Int]?
    var is4k: Bool
    var serverId: Int?
    var profileId: Int?
    var rootFolder: String?
    var languageProfileId: Int?
    var tags: [Int]?
    var tvdbId: Int?

    init(
        mediaType: SeerrMediaType,
        mediaId: Int,
        seasons: [Int]? = nil,
        is4k: Bool = false,
        serverId: Int? = nil,
        profileId: Int? = nil,
        rootFolder: String? = nil,
        languageProfileId: Int? = nil,
        tags: [Int]? = nil,
        tvdbId: Int? = nil
    ) {
        self.mediaType = mediaType
        self.mediaId = mediaId
        self.seasons = seasons.map { Array(Set($0)).sorted() }
        self.is4k = is4k
        self.serverId = serverId
        self.profileId = profileId
        self.rootFolder = rootFolder
        self.languageProfileId = languageProfileId
        self.tags = tags
        self.tvdbId = tvdbId
    }

    var isValid: Bool {
        guard mediaId > 0, mediaType == .movie || mediaType == .tv else { return false }
        if mediaType == .movie {
            return seasons == nil
        }
        guard let seasons, !seasons.isEmpty else { return false }
        return seasons.allSatisfy { $0 >= 0 }
    }
}

enum SeerrRequestEligibility {
    /// Missing media-info means no existing request; unknown server states never become requestable.
    static func requestableSeasons(title: SeerrTitle, settings: SeerrPublicSettings, is4K: Bool = false) -> [Int] {
        guard title.mediaInfo?.status != .blocklisted,
              title.mediaInfo?.availability(is4K: is4K) != .blocklisted
        else { return [] }
        if let state = title.mediaInfo?.status, case .unknown = state {
            return []
        }
        if let state = title.mediaInfo?.availability(is4K: is4K), case .unknown = state {
            return []
        }
        return (title.seasons ?? []).filter { season in
            guard season.seasonNumber >= 0, season.episodeCount.map({ $0 > 0 }) ?? false,
                  season.seasonNumber != 0 || settings.enableSpecialEpisodes == true
            else { return false }
            let stored = title.mediaInfo?.seasons?.first { $0.seasonNumber == season.seasonNumber }
            let state = is4K ? stored?.status4k : stored?.status
            guard state?.isRequestable ?? true else { return false }
            return !(title.mediaInfo?.requests ?? []).contains { request in
                (request.is4k ?? false) == is4K && request.status != .declined && request.status != .completed
                    && (request.seasons ?? []).contains { $0.seasonNumber == season.seasonNumber }
            }
        }.map(\.seasonNumber).sorted()
    }

    static func canRequest(
        title: SeerrTitle,
        type: SeerrMediaType,
        user: SeerrUser,
        settings: SeerrPublicSettings,
        quota: SeerrQuota,
        is4K: Bool = false,
        seasons: [Int] = []
    ) -> Bool {
        guard settings.initialized, user.canRequest(type, is4K: is4K), title.mediaInfo?.status != .blocklisted,
              !is4K || settings.permits4K(type)
        else { return false }
        if let state = title.mediaInfo?.status, case .unknown = state {
            return false
        }
        if type == .movie {
            let hasExistingRequest = (title.mediaInfo?.requests ?? []).contains {
                ($0.is4k ?? false) == is4K && $0.status != .declined && $0.status != .completed
            }
            return !hasExistingRequest && (title.mediaInfo?.availability(is4K: is4K).isRequestable ?? true)
                && quota.movie.allows(count: 1)
        }
        guard type == .tv, !seasons.isEmpty else { return false }
        let eligible = Set(requestableSeasons(title: title, settings: settings, is4K: is4K))
        let selected = Set(seasons)
        return selected.isSubset(of: eligible) && quota.tv.allows(count: selected.count)
            && (settings.partialRequestsEnabled == true || selected == eligible)
    }
}

/// Disabled or unsupported server sliders are never silently replaced by hard-coded feeds.
struct SeerrDiscoverSlider: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var type: Int
    var order: Int
    var enabled: Bool
    var isBuiltIn: Bool
    var title: String?
    var data: String?

    var supportedFeed: SeerrDiscoveryFeed? {
        guard enabled, isBuiltIn else { return nil }
        switch type {
        case 4: return .trending
        case 5: return .popularMovies
        case 7: return .upcomingMovies
        case 9: return .popularTV
        case 11: return .upcomingTV
        default: return nil
        }
    }
}

struct SeerrServiceServer: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var is4k: Bool
    var isDefault: Bool
    var activeProfileId: Int?
    var activeDirectory: String?
    var activeLanguageProfileId: Int?
    var activeTags: [Int]?
}

struct SeerrServiceProfile: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
}

struct SeerrRootFolder: Codable, Identifiable, Hashable, Sendable {
    var id: Int?
    var path: String
    var freeSpace: Int64?
}

struct SeerrServiceTag: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var label: String
}

struct SeerrServiceDetails: Codable, Hashable, Sendable {
    var server: SeerrServiceServer
    var profiles: [SeerrServiceProfile]
    var rootFolders: [SeerrRootFolder]
    var languageProfiles: [SeerrServiceProfile]?
    var tags: [SeerrServiceTag]?
}

/// Only allow TMDB-relative artwork, never arbitrary URLs supplied by a remote metadata response.
enum SeerrArtwork {
    static func url(path: String?, width: String = "w500") -> URL? {
        guard let path, path.hasPrefix("/"), !path.hasPrefix("//"),
              !path.contains(".."), !path.contains("?"), !path.contains("#"),
              ["w92", "w154", "w185", "w300", "w342", "w500", "w780", "w1280", "original"].contains(width)
        else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(width)\(path)")
    }
}
