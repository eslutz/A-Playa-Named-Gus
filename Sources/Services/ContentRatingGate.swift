import SwiftUI

/// Combines the household's preference and the device's Apple-derived ceiling.
/// Only a successful system response may change the latter.
enum ContentRatingGate {
    /// Comparable severity rank for a rating limit. Higher admits more mature content.
    enum Limit: String, CaseIterable, Identifiable, Codable {
        case off
        case general
        case parentalGuidance
        case teen
        case mature

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .off:
                return String(localized: "Off", comment: "Content limit: no filtering")
            case .general:
                return String(localized: "All Ages", comment: "Content limit tier")
            case .parentalGuidance:
                return String(localized: "Parental Guidance", comment: "Content limit tier")
            case .teen:
                return String(localized: "Teen", comment: "Content limit tier")
            case .mature:
                return String(localized: "Mature", comment: "Content limit tier")
            }
        }

        /// Highest admitted rating rank; `nil` disables filtering.
        var maximumRank: Int? {
            switch self {
            case .off: return nil
            case .general: return 0
            case .parentalGuidance: return 1
            case .teen: return 2
            case .mature: return 3
            }
        }
    }

    static let limitDefaultsKey = "dev.ericslutz.gus.contentRatingLimit"
    static let hideUnratedDefaultsKey = "dev.ericslutz.gus.contentRatingHideUnrated"

    static let ageCeilingKey = "dev.ericslutz.gus.contentRatingAgeCeiling"

    static let awaitingRangeKey = "dev.ericslutz.gus.awaitingRequiredAgeRange"

    struct Policy: Equatable {
        let limit: Limit
        let hideUnrated: Bool
        let ageCeiling: Limit
        let awaitingRequiredRange: Bool

        init(manual: Limit, hideUnrated: Bool, ageCeiling: Limit = .off, awaitingRequiredRange: Bool = false) {
            self.awaitingRequiredRange = awaitingRequiredRange
            self.ageCeiling = ageCeiling
            let preferred = (manual.maximumRank ?? Int.max) < (ageCeiling.maximumRank ?? Int.max) ? manual : ageCeiling
            limit = awaitingRequiredRange ? .general : preferred
            self.hideUnrated = hideUnrated || ageCeiling != .off || awaitingRequiredRange
        }

        var revision: String {
            "\(limit.rawValue):\(hideUnrated):\(ageCeiling.rawValue):\(awaitingRequiredRange)"
        }

        func admits(_ item: MediaItem) -> Bool {
            !awaitingRequiredRange && ContentRatingGate.admits(item, limit: limit, hideUnrated: hideUnrated, ageCeiling: ageCeiling)
        }
    }

    static func storedPolicy(userDefaults: UserDefaults = .standard) -> Policy {
        Policy(
            manual: userDefaults.string(forKey: limitDefaultsKey).flatMap(Limit.init(rawValue:)) ?? .off,
            hideUnrated: userDefaults.bool(forKey: hideUnratedDefaultsKey),
            ageCeiling: userDefaults.string(forKey: ageCeilingKey).flatMap(Limit.init(rawValue:)) ?? .off,
            awaitingRequiredRange: userDefaults.bool(forKey: awaitingRangeKey)
        )
    }

    /// Store the derived tier, including an explicitly returned adult result.
    /// The original bounds and the source of the declaration never leave memory.
    static func applySharedRange(lowerBound: Int?, userDefaults: UserDefaults = .standard) {
        let ceiling: Limit
        switch lowerBound ?? 0 {
        case ..<13: ceiling = .general
        case 13 ..< 16: ceiling = .teen
        case 16 ..< 18: ceiling = .mature
        default: ceiling = .off
        }
        userDefaults.set(ceiling.rawValue, forKey: ageCeilingKey)
    }

    /// Rating-string → rank table covering US movie (MPA), US TV, and the common
    /// international systems Jellyfin emits (BBFC, FSK, ACB, OFLC, Canadian).
    /// Rank 0 = all ages … 3 = mature, 4 = adults-only.
    ///
    /// "Unrated"-style strings are deliberately absent: they mean "no rating", so they
    /// follow the household's Hide Unrated toggle instead of a fixed rank.
    private static let ratingRanks: [String: Int] = [
        // US movie (MPA)
        "g": 0, "pg": 1, "pg-13": 2, "r": 3, "nc-17": 4,
        // US TV
        "tv-y": 0, "tv-y7": 0, "tv-g": 0, "tv-pg": 1, "tv-14": 2, "tv-ma": 3,
        // UK (BBFC)
        "u": 0, "12": 2, "12a": 2, "15": 2, "18": 3, "r18": 4,
        // Germany (FSK)
        "fsk 0": 0, "fsk-0": 0, "fsk 6": 1, "fsk-6": 1, "fsk 12": 2, "fsk-12": 2,
        "fsk 16": 3, "fsk-16": 3, "fsk 18": 3, "fsk-18": 3,
        // Australia (ACB) / New Zealand (OFLC)
        "m": 2, "ma15+": 2, "r16": 3, "r18+": 3, "x18+": 4,
        // Canada
        "14a": 2, "18a": 3, "a": 4,
        // Common defaults Jellyfin emits
        "approved": 1, "x": 4, "xxx": 4,
    ]

    /// Strings that explicitly mean "no rating assigned" — treated the same as a
    /// missing rating (admitted unless Hide Unrated is on), not as adults-only.
    private static let unratedValues: Set<String> = ["unrated", "not rated", "nr", "n/a"]

    /// Rank for an official rating string; `nil` when the rating is unknown, absent, or
    /// an explicit "unrated" marker. Country prefixes ("US-PG", "DE-16", "GB-15") are
    /// stripped, and bare/suffixed ages ("16", "16+") map by age bracket so unlisted
    /// regional systems still gate sensibly.
    static func rank(for officialRating: String?) -> Int? {
        guard let officialRating else { return nil }
        let normalized = officialRating.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, !unratedValues.contains(normalized) else { return nil }

        if let rank = ratingRanks[normalized] {
            return rank
        }

        // Country-prefixed forms, e.g. "de-16", "gb-15", "us-pg-13".
        if let separator = normalized.firstIndex(where: { $0 == "-" || $0 == "/" || $0 == ":" }) {
            let prefix = String(normalized[..<separator])
            if prefix.count == 2, prefix.allSatisfy(\.isLetter) {
                let remainder = String(normalized[normalized.index(after: separator)...])
                if let rank = rank(for: remainder) {
                    return rank
                }
            }
        }

        // Bare minimum-age ratings, e.g. "6", "16", "16+".
        let digits = normalized.hasSuffix("+") ? String(normalized.dropLast()) : normalized
        if let age = Int(digits), (0 ... 21).contains(age) {
            switch age {
            case 0 ... 6: return 0
            case 7 ... 12: return 1
            case 13 ... 15: return 2
            default: return 3
            }
        }

        return nil
    }

    /// Whether an item is admitted under the limit. Unknown/missing ratings are admitted
    /// unless `hideUnrated` is set (strict households).
    static func admits(_ item: MediaItem, limit: Limit, hideUnrated: Bool, ageCeiling: Limit = .off) -> Bool {
        guard let maximumRank = limit.maximumRank else { return true }

        // Library containers and folders stay visible so navigation keeps working.
        switch item.type {
        case .genre, .boxSet, .collectionFolder, .folder, .musicArtist, .musicAlbum, .playlist:
            return true
        case .photo where ageCeiling == .off, nil where ageCeiling == .off:
            return true
        default:
            break
        }

        if ageCeiling != .off, let minimum = explicitMinimumAge(for: item.officialRating) {
            let guaranteedMinimum = ageCeiling == .mature ? 16 : ageCeiling == .teen ? 13 : 0
            guard guaranteedMinimum >= minimum else { return false }
        }
        guard let rank = rank(for: item.officialRating) else {
            return !hideUnrated
        }
        return rank <= maximumRank
    }

    /// Regional minimum-age certificates can span a Gus tier (for example, GB-15
    /// and GB-18). US advisory categories continue to use the tier table above.
    private static func explicitMinimumAge(for rating: String?) -> Int? {
        guard var value = rating?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        if let separator = value.firstIndex(where: { "-/:".contains($0) }),
           value[..<separator] != "tv", value[..<separator].count == 2, value[..<separator].allSatisfy(\.isLetter)
        {
            value = String(value[value.index(after: separator)...])
        }
        for prefix in ["fsk", "ma", "r", "x"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            break
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: " -+a"))
        return Int(value)
    }

    /// Filters a list of items against the stored preference.
    static func filter(
        _ items: [MediaItem],
        userDefaults: UserDefaults = .standard
    ) -> [MediaItem] {
        let policy = storedPolicy(userDefaults: userDefaults)
        guard policy.limit != .off else { return items }
        return items.filter(policy.admits)
    }

    /// Whether a single item is admitted under the stored preference. List filtering
    /// hides restricted items; this is the second layer that gates detail and playback
    /// for items reached another way (deep link, downloads, stale navigation).
    static func admitsStored(_ item: MediaItem, userDefaults: UserDefaults = .standard) -> Bool {
        storedPolicy(userDefaults: userDefaults).admits(item)
    }

    /// Server artwork can be a mosaic of current playlist members. Cached or
    /// locally edited membership can never establish which images are in it.
    static func playlistCoverItems(playlist: MediaItem, entries: [MediaItem], limit: Limit, hideUnrated: Bool, ageCeiling: Limit = .off) -> [MediaItem] {
        let members = coverMembers(entries, limit: limit, hideUnrated: hideUnrated, count: 1, ageCeiling: ageCeiling)
        return (limit == .off ? [playlist] : []) + members
    }

    /// Prefer titles with reported artwork in server order. A bounded list lets
    /// native image loading recover from stale tags without probing every title.
    static func coverMembers(_ entries: [MediaItem], limit: Limit, hideUnrated: Bool, count: Int, ageCeiling: Limit = .off) -> [MediaItem] {
        let admitted = entries.lazy.filter { item in
            guard item.id != nil, item.type != nil,
                  ![.playlist, .boxSet, .collectionFolder, .folder].contains(item.type)
            else { return false }
            return admits(item, limit: limit, hideUnrated: hideUnrated, ageCeiling: ageCeiling)
        }
        let tagged = Array(admitted.lazy.filter(\.hasTaggedCoverArtwork).prefix(count))
        return tagged.isEmpty ? Array(admitted.prefix(count)) : tagged
    }

    static func storedLimit(userDefaults: UserDefaults = .standard) -> Limit {
        storedPolicy(userDefaults: userDefaults).limit
    }
}

/// SwiftUI observes the same inputs used by the non-UI playback and data gates.
@propertyWrapper
struct StoredContentPolicy: DynamicProperty {
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var manual = ContentRatingGate.Limit.off
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false
    @AppStorage(ContentRatingGate.awaitingRangeKey) private var awaitingRequiredRange = false
    @AppStorage(ContentRatingGate.ageCeilingKey) private var ceiling = ContentRatingGate.Limit.off

    var wrappedValue: ContentRatingGate.Policy {
        .init(manual: manual, hideUnrated: hideUnrated, ageCeiling: ceiling, awaitingRequiredRange: awaitingRequiredRange)
    }
}
