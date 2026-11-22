import Foundation

/// A glance never needs a Jellyfin address, credential, item ID, artwork URL or user ID.
struct GusWidgetSnapshot: Equatable, Codable, Sendable {
    static let kind = "dev.ericslutz.gus.next-up"
    static let lifetime: TimeInterval = 4 * 60 * 60

    var title: String?
    var showsLockScreenTitles: Bool
    var progress: Double?
    var updatedAt: Date

    var expiresAt: Date {
        updatedAt.addingTimeInterval(Self.lifetime)
    }

    func visibleTitle(lockCapable: Bool) -> String? {
        lockCapable && !showsLockScreenTitles ? nil : title
    }

    static func fileURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.dev.ericslutz.gus")?
            .appending(path: "next-up-widget-v1.json")
    }

    static func load(from url: URL?, now: Date = .now) -> Self? {
        guard let url, let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.updatedAt <= now, value.expiresAt > now else { return nil }
        return value
    }

    /// Writes only when the visible value changed or its timeline is close to expiry.
    @discardableResult
    func store(at url: URL?) -> Bool {
        guard let url else { return false }
        if let saved = Self.load(from: url, now: updatedAt),
           saved.title == title, saved.progress == progress,
           saved.showsLockScreenTitles == showsLockScreenTitles,
           saved.expiresAt.timeIntervalSince(updatedAt) > Self.lifetime / 2
        {
            return false
        }
        do {
            let data = try JSONEncoder().encode(self)
            #if os(iOS) || os(watchOS) || os(visionOS)
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
                try data.write(to: url, options: .atomic)
            #endif
            return true
        } catch {
            Self.clear(at: url)
            return true
        }
    }

    static func clear(at url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
