import Foundation
@testable import Gus
import Testing

@Suite("System surface privacy")
struct SystemSurfaceTests {
    @MainActor
    @Test("consent and lock screen titles are independent and isolated per credential")
    func scopedConsent() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = SessionCredential(serverID: "A_B", userID: "C")
        let overlapping = SessionCredential(serverID: "A", userID: "B_C")
        let preferences = SystemSurfacePreferences(credential: first, defaults: defaults)
        #expect(!preferences.personalHistoryEnabled)
        #expect(!preferences.showsLockScreenTitles)
        preferences.personalHistoryEnabled = true
        let restored = SystemSurfacePreferences(credential: first, defaults: defaults)
        #expect(restored.personalHistoryEnabled)
        #expect(!restored.showsLockScreenTitles)
        preferences.showsLockScreenTitles = true
        let other = SystemSurfacePreferences(credential: overlapping, defaults: defaults)
        #expect(!other.personalHistoryEnabled)
        #expect(!other.showsLockScreenTitles)
        preferences.forget()
        let forgotten = SystemSurfacePreferences(credential: first, defaults: defaults)
        #expect(!forgotten.personalHistoryEnabled)
        #expect(!forgotten.showsLockScreenTitles)
    }

    @Test("widget snapshots expire, redact lock titles, and suppress unchanged writes")
    func widgetLifecycle() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { GusWidgetSnapshot.clear(at: url) }
        let now = Date.now
        var snapshot = GusWidgetSnapshot(title: "Big Buck Bunny", showsLockScreenTitles: false, progress: 0.5, updatedAt: now)
        #expect(snapshot.store(at: url))
        #expect(!snapshot.store(at: url))
        #expect(snapshot.visibleTitle(lockCapable: true) == nil)
        #expect(snapshot.visibleTitle(lockCapable: false) == "Big Buck Bunny")
        #expect(GusWidgetSnapshot.load(from: url, now: now) == snapshot)
        #expect(GusWidgetSnapshot.load(from: url, now: snapshot.expiresAt) == nil)
        #expect(GusWidgetSnapshot.load(from: url, now: now.addingTimeInterval(-1)) == nil)
        snapshot.showsLockScreenTitles = true
        #expect(snapshot.store(at: url))
        #expect(snapshot.visibleTitle(lockCapable: true) == "Big Buck Bunny")
        let fields = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(Set(fields.keys) == ["title", "showsLockScreenTitles", "progress", "updatedAt"])
        GusWidgetSnapshot.clear(at: url)
        #expect(GusWidgetSnapshot.load(from: url, now: now) == nil)
    }

    @Test("Top Shelf actions expire when the publication or item changes")
    func scopedShelfAction() throws {
        var shelf = TopShelfSnapshot(
            items: [.init(id: "item-1", title: "Example", imageURL: nil, playbackProgress: nil)],
            serverID: "server",
            userID: "profile"
        )
        let link = try #require(shelf.actionURL(for: "item-1", play: true))
        let selection = try #require(shelf.selection(for: link))
        #expect(selection.userID == "profile")
        #expect(selection.play)
        shelf.items.removeAll()
        #expect(shelf.selection(for: link) == nil)
        shelf.publicationID = nil
        #expect(shelf.actionURL(for: "item-1", play: true) == nil)
    }

    #if os(iOS)
        @Test("remote session attributes expire and carry presentation values only")
        func remoteSnapshot() throws {
            guard #available(iOS 27, *) else { return }
            let now = Date.now
            let attributes = GusRemotePlaybackAttributes(
                id: UUID().uuidString,
                deviceID: UUID().uuidString,
                deviceType: .tv,
                contentID: UUID().uuidString,
                title: nil,
                isAudio: false,
                isPaused: true,
                duration: 20,
                elapsed: 10,
                observedAt: now
            )
            #expect(attributes.isFresh(at: now))
            #expect(!attributes.isFresh(at: now.addingTimeInterval(45)))
            #expect(!attributes.isFresh(at: now.addingTimeInterval(-1)))
            let fields = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(attributes)) as? [String: Any])
            #expect(Set(fields.keys) == ["id", "deviceID", "deviceType", "contentID", "isAudio", "isPaused", "duration", "elapsed", "observedAt"])
        }
    #endif
}
