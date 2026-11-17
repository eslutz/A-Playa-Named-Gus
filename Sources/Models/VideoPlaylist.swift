import Foundation

struct VideoPlaylist: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    let scope: AccountScope
    var entries: [VideoPlaylistEntry]
    var cursor: PlaylistCursor?
    var queued: Bool
    var activityAt: Date?

    var appearsInNextUp: Bool {
        cursor?.finished != true && (queued || cursor != nil)
    }
}

struct VideoPlaylistEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var reference: MediaReference
}

struct PlaylistCursor: Codable, Equatable, Sendable {
    var entryID: UUID?
    var positionTicks: Int?
    var finished: Bool
}

struct SavedMediaIntent: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var reference: MediaReference
    var queued: Bool
    var activityAt: Date?
}

/// The cloud payload is an allowlist, never an encoded provider response. Artwork,
/// paths, endpoints, provider watch history and credentials remain on the device.
struct SavedMediaReference: Codable, Equatable, Sendable {
    let scope: AccountScope
    let id: String?
    let name: String?
    let type: MediaItemType?
    let productionYear: Int?
    let seriesID: String?
    let seriesName: String?
    let season: Int?
    let episode: Int?
    let officialRating: String?
    let externalIDs: [String: String]

    init(_ reference: MediaReference) {
        let item = reference.item
        scope = reference.scope
        id = item.id
        name = item.name
        type = item.type
        productionYear = item.productionYear
        seriesID = item.seriesID
        seriesName = item.seriesName
        season = item.parentIndexNumber
        episode = item.indexNumber
        officialRating = item.officialRating
        externalIDs = item.externalIDs.reduce(into: [:]) { result, pair in
            let key = pair.key.lowercased()
            if ["imdb", "tmdb", "tvdb"].contains(key),
               pair.value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
            {
                result[key] = pair.value
            }
        }
    }

    var reference: MediaReference {
        var item = MediaItem(
            id: id,
            indexNumber: episode,
            name: name,
            officialRating: officialRating,
            parentIndexNumber: season,
            productionYear: productionYear,
            seriesID: seriesID,
            seriesName: seriesName,
            type: type
        )
        item.externalIDs = externalIDs
        return MediaReference(item: item, scope: scope)
    }
}

/// A Lamport clock observes every imported field before creating a local edit.
/// Device IDs break concurrent ties without relying on wall-clock accuracy.
struct SavedMediaRevision: Codable, Equatable, Comparable, Sendable {
    var counter: UInt64
    var device: String

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.counter == rhs.counter ? lhs.device < rhs.device : lhs.counter < rhs.counter
    }
}

struct SavedMediaField: Codable, Equatable, Sendable {
    var revision: SavedMediaRevision
    var data: Data
}

/// Supplemental intent, cursor and activity registers merge independently.
/// Jellyfin owns list membership and ordering.
struct SavedMediaRecord: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case playlist, cursor, intent, activity }
    let id: String
    let scope: AccountScope
    let kind: Kind
    var fields: [String: SavedMediaField] = [:]

    mutating func set<T: Encodable>(_ key: String, value: T, revision: SavedMediaRevision) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        fields[key] = try SavedMediaField(revision: revision, data: encoder.encode(value))
    }

    func value<T: Decodable>(_ key: String, as _: T.Type = T.self) -> T? {
        fields[key].flatMap { try? JSONDecoder().decode(T.self, from: $0.data) }
    }

    func merging(_ other: Self) -> Self {
        guard id == other.id, scope == other.scope, kind == other.kind else { return self }
        var result = self
        for (key, incoming) in other.fields {
            guard let current = fields[key] else { result.fields[key] = incoming; continue }
            // Activity represents an actual event; preserve the latest event even
            // when an older offline event arrives with a newer logical revision.
            if key == "activity", let a = try? JSONDecoder().decode(Date.self, from: current.data),
               let b = try? JSONDecoder().decode(Date.self, from: incoming.data), a != b
            {
                result.fields[key] = a > b ? current : incoming
            } else if current.revision < incoming.revision {
                result.fields[key] = incoming
            }
        }
        return result
    }
}

/// Decodes only supported supplemental records. Unknown/retired record kinds are
/// dropped without discarding current records stored beside them. Malformed
/// supported records still fail decoding and preserve the original file.
struct CurrentSavedMediaRecord: Decodable {
    let record: SavedMediaRecord?
    private enum CodingKeys: String, CodingKey { case kind }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(String.self, forKey: .kind)
        guard SavedMediaRecord.Kind(rawValue: kind) != nil else {
            record = nil
            return
        }
        let candidate = try SavedMediaRecord(from: decoder)
        switch candidate.kind {
        case .playlist:
            record = candidate.id.hasPrefix("server-") && candidate.value("serverBacked", as: Bool.self) == true ? candidate : nil
        case .cursor:
            record = candidate.id.hasPrefix("cursor-server-") ? candidate : nil
        case .intent, .activity:
            record = candidate
        }
    }
}
