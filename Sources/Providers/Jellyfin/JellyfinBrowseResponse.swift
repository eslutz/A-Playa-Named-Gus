import Foundation
import Get
import JellyfinAPI

extension JellyfinClient {
    /// Keep one authenticated GET and retain the SDK models, including pagination,
    /// artwork, ratings and user data. Read-only compatibility must never change
    /// a DTO that will subsequently be sent back to Jellyfin as a metadata edit.
    func browse<T: Decodable & Sendable>(_ request: Request<T>) async throws -> Response<T> {
        let response = try await data(for: request)
        return try response.map { try JellyfinBrowseResponse.decode(T.self, from: $0) }
    }
}

/// UserViews returns full item DTOs even though navigation only needs folder
/// identity, classification and artwork. Media metadata supplied by a plugin
/// must not prevent the user from entering that folder.
struct JellyfinLibraryViews: Decodable, Sendable {
    struct Library: Decodable, Sendable {
        var id: String
        var name: String?
        var type: String?
        var collectionType: String?
        var officialRating: String?
        var imageTags: [String: String]?
        var backdropImageTags: [String]?

        private enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", type = "Type", collectionType = "CollectionType"
            case officialRating = "OfficialRating", imageTags = "ImageTags", backdropImageTags = "BackdropImageTags"
        }

        var item: MediaItem {
            JellyfinMediaItemMapper.mediaItem(from: BaseItemDto(
                backdropImageTags: backdropImageTags,
                collectionType: collectionType.map { CollectionType(rawValue: $0) ?? .unknown },
                id: id, imageTags: imageTags, name: name, officialRating: officialRating,
                type: type.flatMap(BaseItemKind.init(rawValue:))
            ))
        }
    }

    var items: [Library]

    private enum CodingKeys: String, CodingKey { case items = "Items" }
}

private enum JellyfinBrowseResponse {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            let raw = try value.decode(String.self)
            // Jellyfin timestamps may serialize a .NET DateTime without an offset.
            let format = Date.ISO8601FormatStyle(includingFractionalSeconds: raw.contains("."))
            if let date = raw.wholeMatch(of: format)?.output ?? (raw + "Z").wholeMatch(of: format)?.output {
                return date
            }
            throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid Jellyfin timestamp.")
        }
        do {
            return try decoder.decode(type, from: data)
        } catch let DecodingError.dataCorrupted(context) {
            let path = context.codingPath.map(\.stringValue)
            guard path.last == "CollectionType" || (path.last == "Type" && path.dropLast(2).last == "People") else {
                throw DecodingError.dataCorrupted(context)
            }
            // Some virtual folder kinds are excluded from Jellyfin's OpenAPI
            // schema. Person kinds also vary by server version (e.g. Narrator).
            // Normalize just those two optional classifications on a compatibility
            // miss. A second schema error still propagates and no item is discarded.
            let object = try JSONSerialization.jsonObject(with: data)
            let normalized: Any
            if var page = object as? [String: Any], let items = page["Items"] as? [[String: Any]] {
                page["Items"] = items.map(normalizedItem)
                normalized = page
            } else if let items = object as? [[String: Any]] {
                normalized = items.map(normalizedItem)
            } else if let item = object as? [String: Any] {
                normalized = normalizedItem(item)
            } else {
                throw DecodingError.dataCorrupted(context)
            }
            return try decoder.decode(type, from: JSONSerialization.data(withJSONObject: normalized))
        }
    }

    private static func normalizedItem(_ original: [String: Any]) -> [String: Any] {
        var item = original
        if let kind = item["CollectionType"] as? String, CollectionType(rawValue: kind) == nil {
            item["CollectionType"] = CollectionType.unknown.rawValue
        }
        if var people = item["People"] as? [[String: Any]] {
            for index in people.indices {
                if let kind = people[index]["Type"] as? String, PersonKind(rawValue: kind) == nil {
                    if (item["Type"] as? String) == BaseItemKind.audioBook.rawValue,
                       kind.caseInsensitiveCompare("Narrator") == .orderedSame
                    {
                        people[index]["Role"] = "Narrator"
                    }
                    people[index]["Type"] = PersonKind.unknown.rawValue
                }
            }
            item["People"] = people
        }
        return item
    }
}
