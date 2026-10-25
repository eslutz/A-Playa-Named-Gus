import Foundation

extension SeerrPermissions {
    static let manageIssues = Self(rawValue: 1_048_576)
    static let viewIssues = Self(rawValue: 2_097_152)
    static let createIssues = Self(rawValue: 4_194_304)
}

extension SeerrUser {
    var canViewIssues: Bool {
        permissions.permits([.manageIssues, .viewIssues, .createIssues])
    }

    var canCreateIssues: Bool {
        permissions.permits([.manageIssues, .createIssues])
    }

    var canViewBlocklist: Bool {
        permissions.permits([.manageBlocklist, .viewBlocklist])
    }

    var canManageBlocklist: Bool {
        permissions.permits(.manageBlocklist)
    }
}

enum SeerrIssueType: Int, Codable, CaseIterable, Sendable {
    case video = 1, audio, subtitles, other
    var title: String {
        switch self {
        case .video: String(localized: "Video")
        case .audio: String(localized: "Audio")
        case .subtitles: String(localized: "Subtitles")
        case .other: String(localized: "Other")
        }
    }
}

struct SeerrIssue: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var issueType: Int
    var status: Int
    var problemSeason: Int?
    var problemEpisode: Int?
    var media: SeerrMediaInfo?
    var createdBy: SeerrUser?
    var comments: [SeerrIssueComment]?
    var createdAt: String?

    var isOpen: Bool {
        status == 1
    }

    var isResolved: Bool {
        status == 2
    }

    func canModify(user: SeerrUser) -> Bool {
        (isOpen || isResolved) && user.canCreateIssues
            && (user.permissions.permits(.manageIssues) || createdBy?.id == user.id)
    }
}

struct SeerrIssueComment: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var message: String
    var user: SeerrUser?
    var createdAt: String?
}

struct SeerrIssuePage: Codable, Sendable {
    var pageInfo: SeerrPageInfo
    var results: [SeerrIssue]
}

enum SeerrIssueFilter: String, CaseIterable, Sendable {
    case all, open, resolved
    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .open: String(localized: "Open")
        case .resolved: String(localized: "Resolved")
        }
    }
}

struct SeerrBlocklistItem: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var tmdbId: Int
    var mediaType: SeerrMediaType
    var title: String?
}

struct SeerrBlocklistPage: Codable, Sendable {
    var pageInfo: SeerrPageInfo
    var results: [SeerrBlocklistItem]
}

struct SeerrRegion: Codable, Identifiable, Hashable, Sendable {
    var code: String
    var name: String
    var id: String {
        code
    }

    enum CodingKeys: String, CodingKey {
        case code = "iso_3166_1"
        case name = "english_name"
    }
}

struct SeerrLanguage: Codable, Identifiable, Hashable, Sendable {
    var code: String
    var name: String
    var id: String {
        code
    }

    enum CodingKeys: String, CodingKey {
        case code = "iso_639_1"
        case name = "english_name"
    }
}

struct SeerrRegionalPreferences: Sendable, Equatable {
    var discoverRegion: String
    var streamingRegion: String
    var originalLanguage: String
}

struct SeerrRegionalPreferenceFields: OptionSet, Sendable {
    let rawValue: UInt8
    static let discovery = Self(rawValue: 1)
    static let streaming = Self(rawValue: 2)
    static let language = Self(rawValue: 4)
    static let all: Self = [.discovery, .streaming, .language]
}

struct SeerrEmailNotificationPreferences: Sendable {
    static let editableEventsMask = 4 | 8 | 64 | 512 | 1024
    var enabled: Bool
    var events: Int
}

/// A lossless settings snapshot preserves fields introduced across Seerr 3 releases.
/// Notification snapshots may contain provider credentials: keep them inside the client actor.
enum SeerrSettingValue: Codable, Sendable, Equatable {
    case string(String), integer(Int), number(Double), boolean(Bool), object([String: SeerrSettingValue]), array([SeerrSettingValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: Self].self) {
            self = .object(value)
        } else {
            self = try .array(container.decode([Self].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .boolean(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var string: String? {
        if case let .string(value) = self {
            value
        } else {
            nil
        }
    }

    var integer: Int? {
        if case let .integer(value) = self {
            value
        } else {
            nil
        }
    }

    var boolean: Bool? {
        if case let .boolean(value) = self {
            value
        } else {
            nil
        }
    }

    var object: [String: Self]? {
        if case let .object(value) = self {
            value
        } else {
            nil
        }
    }
}
