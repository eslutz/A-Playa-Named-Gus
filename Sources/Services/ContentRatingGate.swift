import Foundation

/// Maps official content ratings onto comparable ranks and filters media above the
/// household's chosen limit.
///
/// The limit is an app-level preference (Settings → Content Restrictions) that parents
/// pair with Apple Screen Time's app/settings locks; reading the device's effective
/// movie/TV rating restrictions via ManagedSettings requires the Apple-granted Family
/// Controls entitlement and is documented as follow-up in `Documentation/ROADMAP.md`.
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
    static func admits(_ item: MediaItem, limit: Limit, hideUnrated: Bool) -> Bool {
        guard let maximumRank = limit.maximumRank else { return true }

        // Library containers and folders stay visible so navigation keeps working.
        switch item.type {
        case .collectionFolder, .folder, .musicArtist, .musicAlbum, .playlist, .photo, nil:
            return true
        default:
            break
        }

        guard let rank = rank(for: item.officialRating) else {
            return !hideUnrated
        }
        return rank <= maximumRank
    }

    /// Filters a list of items against the stored preference.
    static func filter(
        _ items: [MediaItem],
        userDefaults: UserDefaults = .standard
    ) -> [MediaItem] {
        let limit = storedLimit(userDefaults: userDefaults)
        guard limit != .off else { return items }
        let hideUnrated = userDefaults.bool(forKey: hideUnratedDefaultsKey)
        return items.filter { admits($0, limit: limit, hideUnrated: hideUnrated) }
    }

    /// Whether a single item is admitted under the stored preference. List filtering
    /// hides restricted items; this is the second layer that gates detail and playback
    /// for items reached another way (deep link, downloads, stale navigation).
    static func admitsStored(_ item: MediaItem, userDefaults: UserDefaults = .standard) -> Bool {
        let limit = storedLimit(userDefaults: userDefaults)
        guard limit != .off else { return true }
        return admits(item, limit: limit, hideUnrated: userDefaults.bool(forKey: hideUnratedDefaultsKey))
    }

    static func storedLimit(userDefaults: UserDefaults = .standard) -> Limit {
        userDefaults.string(forKey: limitDefaultsKey).flatMap(Limit.init(rawValue:)) ?? .off
    }
}
