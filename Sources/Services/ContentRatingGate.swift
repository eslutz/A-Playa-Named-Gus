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

    /// Rating-string → rank table covering US movie (MPA), US TV, and common Jellyfin
    /// parental-rating values. Rank 0 = all ages … 3 = mature, 4 = adults-only.
    private static let ratingRanks: [String: Int] = [
        // US movie (MPA)
        "g": 0, "pg": 1, "pg-13": 2, "r": 3, "nc-17": 4,
        // US TV
        "tv-y": 0, "tv-y7": 0, "tv-g": 0, "tv-pg": 1, "tv-14": 2, "tv-ma": 3,
        // Common defaults Jellyfin emits
        "approved": 1, "unrated": 4, "not rated": 4, "nr": 4, "x": 4, "xxx": 4,
    ]

    /// Rank for an official rating string; `nil` when the rating is unknown/absent.
    static func rank(for officialRating: String?) -> Int? {
        guard let officialRating else { return nil }
        let normalized = officialRating.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return ratingRanks[normalized]
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

    static func storedLimit(userDefaults: UserDefaults = .standard) -> Limit {
        userDefaults.string(forKey: limitDefaultsKey).flatMap(Limit.init(rawValue:)) ?? .off
    }
}
