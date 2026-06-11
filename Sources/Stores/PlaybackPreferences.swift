import Foundation

/// User-tunable playback preferences: written by Settings (`@AppStorage`), read by
/// `PlaybackStore` when a session starts or ends.
enum PlaybackPreferences {
    static let autoPlayNextEpisodeKey = "autoPlayNextEpisode"

    /// Defaults on — matching the system video players' continue-watching behavior.
    static var autoPlaysNextEpisode: Bool {
        UserDefaults.standard.object(forKey: autoPlayNextEpisodeKey) as? Bool ?? true
    }
}

/// Maximum streaming bitrate the playback negotiation requests from the server.
/// "Maximum" effectively means original quality — the cap sits above any realistic
/// home-media bitrate, so compatible sources direct-play untouched.
enum PlaybackQuality: String, CaseIterable, Identifiable {
    case maximum
    case high
    case medium
    case low

    static let defaultsKey = "playbackQuality"

    var id: String {
        rawValue
    }

    var maxStreamingBitrate: Int {
        switch self {
        case .maximum:
            return 120_000_000
        case .high:
            return 20_000_000
        case .medium:
            return 8_000_000
        case .low:
            return 3_000_000
        }
    }

    var title: String {
        switch self {
        case .maximum:
            return String(localized: "Maximum (Original)", comment: "Streaming quality option: no practical bitrate cap")
        case .high:
            return String(localized: "High (20 Mbps)", comment: "Streaming quality option")
        case .medium:
            return String(localized: "Medium (8 Mbps)", comment: "Streaming quality option")
        case .low:
            return String(localized: "Low (3 Mbps)", comment: "Streaming quality option")
        }
    }

    static var stored: PlaybackQuality {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(PlaybackQuality.init) ?? .maximum
    }
}
